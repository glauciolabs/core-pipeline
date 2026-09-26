#!/usr/bin/env bash
set -euo pipefail

app_full="${GITOPS_APPLICATION_NAME:-${APP_NAME}-${ENVIRONMENT}}"
gitops_repo_url="${GITOPS_REPO_URL:-}"
gitops_repo_branch="${GITOPS_REPO_BRANCH:-}"
manifest_override="${GITOPS_APPLICATION_MANIFEST_PATH:-}"

if [[ -z "${gitops_repo_url}" ]]; then
  echo "[ERROR] GITOPS_REPO_URL is required for declarative promotion."
  exit 1
fi

if [[ -z "${gitops_repo_branch}" ]]; then
  gitops_repo_branch="${ENVIRONMENT}"
fi

if [[ -z "${GITOPS_SSH_PRIVATE_KEY:-}" ]]; then
  echo "[ERROR] GITOPS_SSH_PRIVATE_KEY is required to update the GitOps repository."
  exit 1
fi

workdir="$(mktemp -d)"
key_file="$(mktemp)"

cleanup() {
  rm -rf "${workdir}"
  rm -f "${key_file}"
}
trap cleanup EXIT

printf '%s\n' "${GITOPS_SSH_PRIVATE_KEY}" > "${key_file}"
chmod 600 "${key_file}"
export GIT_SSH_COMMAND="ssh -i ${key_file} -o StrictHostKeyChecking=no"

echo "[INFO] Cloning GitOps repo ${gitops_repo_url} (branch: ${gitops_repo_branch})"
git clone --depth 1 --branch "${gitops_repo_branch}" "${gitops_repo_url}" "${workdir}/repo"

manifest_path=""

if [[ -n "${manifest_override}" ]]; then
  manifest_path="${workdir}/repo/${manifest_override}"
  if [[ ! -f "${manifest_path}" ]]; then
    echo "[ERROR] Explicit GitOps manifest path not found: ${manifest_override}"
    exit 1
  fi
else
  fallback_match=""
  while IFS= read -r file; do
    if ! APP_FULL="${app_full}" yq -e '.kind == "Application" and .metadata.name == env(APP_FULL)' "${file}" >/dev/null 2>&1; then
      continue
    fi

    source_repo="$(yq -r '.spec.source.repoURL // ""' "${file}")"
    if [[ "${source_repo}" == "${REPO_URL}" ]]; then
      manifest_path="${file}"
      break
    fi

    if [[ -z "${fallback_match}" ]]; then
      fallback_match="${file}"
    fi
  done < <(find "${workdir}/repo" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

  if [[ -z "${manifest_path}" && -n "${fallback_match}" ]]; then
    manifest_path="${fallback_match}"
  fi

  if [[ -z "${manifest_path}" ]]; then
    echo "[ERROR] Could not find Application ${app_full} in ${gitops_repo_url}."
    echo "[ERROR] Provide gitops_application_manifest explicitly or add the Application to the GitOps repo first."
    exit 1
  fi
fi

current_target_revision="$(yq -r '.spec.source.targetRevision // ""' "${manifest_path}")"

echo "[INFO] GitOps manifest: ${manifest_path#${workdir}/repo/}"
echo "[INFO] Current targetRevision: ${current_target_revision}"
echo "[INFO] Desired targetRevision: ${REPO_TAG}"

if [[ "${current_target_revision}" == "${REPO_TAG}" ]]; then
  echo "[INFO] GitOps repo already points to ${REPO_TAG}. Nothing to do."
  exit 0
fi

REPO_TAG="${REPO_TAG}" yq -i '.spec.source.targetRevision = strenv(REPO_TAG)' "${manifest_path}"

git -C "${workdir}/repo" config user.name "core-pipeline"
git -C "${workdir}/repo" config user.email "actions@github.com"
git -C "${workdir}/repo" add "${manifest_path}"
git -C "${workdir}/repo" commit -m "chore(gitops): promote ${app_full} to ${REPO_TAG}"
git -C "${workdir}/repo" push origin "HEAD:${gitops_repo_branch}"

echo "[INFO] GitOps promotion committed successfully."
