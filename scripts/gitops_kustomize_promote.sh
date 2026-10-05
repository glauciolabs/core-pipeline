#!/usr/bin/env bash
set -euo pipefail

app_full="${GITOPS_APPLICATION_NAME:-${APP_NAME}-${ENVIRONMENT}}"
gitops_repo_url="${GITOPS_REPO_URL:-}"
if [[ -z "${GITOPS_REPO_BRANCH:-}" ]]; then
  if [[ "${ENVIRONMENT:-develop}" == "production" ]]; then
    gitops_repo_branch="master"
  else
    gitops_repo_branch="develop"
  fi
else
  gitops_repo_branch="${GITOPS_REPO_BRANCH}"
fi
manifest_override="${GITOPS_APPLICATION_MANIFEST_PATH:-}"

if [[ -z "${gitops_repo_url}" ]]; then
  echo "[ERROR] GITOPS_REPO_URL is required for kustomize promotion."
  exit 1
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

if [[ -z "${manifest_override}" ]]; then
  echo "[ERROR] GITOPS_APPLICATION_MANIFEST_PATH is required to specify the kustomization.yaml path."
  exit 1
fi

manifest_path="${workdir}/repo/${manifest_override}"
if [[ ! -f "${manifest_path}" ]]; then
  echo "[ERROR] Kustomization file not found: ${manifest_override}"
  exit 1
fi

echo "[INFO] Updating image tag to ${REPO_TAG} in ${manifest_override}"
cd "$(dirname "${manifest_path}")"
# Assuming the base image name matches APP_NAME, but kustomize allows editing by name.
# To be robust, if we know the image name, we use it, otherwise we could do a generic replace or pass IMAGE_NAME
image_name="${CONTAINER_REGISTRY:-ghcr.io}/${GITHUB_REPOSITORY}"
# using kustomize edit set image
kustomize edit set image "${image_name}=${image_name}:${REPO_TAG}" || true

git -C "${workdir}/repo" config user.name "core-pipeline"
git -C "${workdir}/repo" config user.email "actions@github.com"
git -C "${workdir}/repo" add "${manifest_override}"

if git -C "${workdir}/repo" diff --cached --quiet; then
  echo "[INFO] No changes detected. Tag is already ${REPO_TAG}."
  exit 0
fi

git -C "${workdir}/repo" commit -m "chore(gitops): promote ${app_full} image to ${REPO_TAG}"
git -C "${workdir}/repo" push origin "HEAD:${gitops_repo_branch}"

echo "[INFO] GitOps image promotion committed successfully."
