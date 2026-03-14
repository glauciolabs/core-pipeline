#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="container"
SNYK_CONFIG_FILE="${SNYK_CONFIG_FILE:-snyk_job.yaml}"
PIPELINE_MODE="${PIPELINE_MODE:-build_and_push}"
REPORTS_DIR="${REPORTS_DIR:-reports/snyk}"

if [[ ! -f "${SNYK_CONFIG_FILE}" ]]; then
  echo "[INFO] ${SNYK_CONFIG_FILE} not found. Skipping Snyk Container."
  exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "[ERROR] yq is required."
  exit 1
fi

status="$(yq -r '.snyk_container.status // "disabled"' "${SNYK_CONFIG_FILE}")"
monitor_status="$(yq -r '.snyk_container.monitor // "disabled"' "${SNYK_CONFIG_FILE}")"
report_status="$(yq -r '.snyk_container.report // "disabled"' "${SNYK_CONFIG_FILE}")"
fail_on_issues="$(yq -r '.snyk_container.fail_on_issues // "enabled"' "${SNYK_CONFIG_FILE}")"
if [[ "${status}" != "enabled" ]]; then
  echo "[INFO] snyk_container is disabled. Skipping."
  exit 0
fi

if [[ "${PIPELINE_MODE}" != "build_and_push" ]]; then
  echo "[INFO] pipeline_mode=${PIPELINE_MODE}. Snyk Container requires pushed images. Skipping."
  exit 0
fi

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for Snyk Container."
  exit 1
fi

if [[ ! -d "${ROOT_DIR}" ]]; then
  echo "[INFO] Directory ${ROOT_DIR} not found. Nothing to scan."
  exit 0
fi

mkdir -p "${REPORTS_DIR}"
overall_issue_exit=0
overall_error_exit=0

extract_repo_path() {
  local repo="$1"
  local first="${repo%%/*}"
  local rest="${repo#*/}"
  if [[ "$repo" == */* && ( "$first" == *.* || "$first" == *:* || "$first" == "localhost" ) ]]; then
    echo "$rest"
  else
    echo "$repo"
  fi
}

for dir in "${ROOT_DIR}"/*; do
  [[ -d "${dir}" ]] || continue

  info_file="${dir}/info.yaml"
  dockerfile_path="${dir}/Dockerfile"

  if [[ ! -f "${info_file}" ]]; then
    echo ">> [SKIP] ${dir} - missing info.yaml"
    continue
  fi

  if [[ ! -f "${dockerfile_path}" ]]; then
    echo ">> [SKIP] ${dir} - missing Dockerfile"
    continue
  fi

  container_repository=$(yq -r '.app.container.repository' "${info_file}")
  container_tag=$(yq -r '.app.container.tag' "${info_file}")

  if [[ -z "${container_repository}" || -z "${container_tag}" ]]; then
    echo ">> [SKIP] ${dir} - container_repository or container_tag is empty."
    continue
  fi

  branch_name="${GITHUB_REF_NAME:-}"
  image_tag="${container_tag}"
  if [[ -n "${branch_name}" && "${branch_name}" != "master" && "${image_tag}" != *-dev ]]; then
    image_tag="${image_tag}-dev"
  fi

  image_ref="${container_repository}:${image_tag}"
  echo "[INFO] Running Snyk Container scan for ${image_ref}..."
  scan_exit=0
  html_exit=0
  monitor_exit=0

  if [[ "${report_status}" == "enabled" ]]; then
    safe_name="$(echo "${image_ref}" | tr '/:' '__')"
    set +e
    dockerfile_arg=()
    if [[ -n "${dockerfile_path}" ]]; then
      dockerfile_arg+=(--file="${dockerfile_path}")
    fi
    docker run --rm \
      -e SNYK_TOKEN="${SNYK_TOKEN}" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "${PWD}:/app" \
      -w /app \
      snyk/snyk:alpine \
      snyk container test "${image_ref}" "${dockerfile_arg[@]}" --json-file-output="${REPORTS_DIR}/snyk-container-${safe_name}.json"
    scan_exit=$?
    set -e

    if [[ ${scan_exit} -gt 1 ]]; then
      echo "[ERROR] Snyk Container scan failed for ${image_ref} with exit code ${scan_exit}."
      overall_error_exit=1
      continue
    fi

    set +e
    docker run --rm \
      -v "${PWD}:/work" \
      -w /work \
      node:24-alpine \
      sh -c "npm -s i -g snyk-to-html >/dev/null 2>&1 && cat ${REPORTS_DIR}/snyk-container-${safe_name}.json | snyk-to-html -o ${REPORTS_DIR}/snyk-container-${safe_name}.html"
    html_exit=$?
    set -e
    if [[ ${html_exit} -ne 0 ]]; then
      echo "[WARN] Could not generate HTML report for ${image_ref}. Keeping JSON output only."
    fi
  else
    set +e
    dockerfile_arg=()
    if [[ -n "${dockerfile_path}" ]]; then
      dockerfile_arg+=(--file="${dockerfile_path}")
    fi
    docker run --rm \
      -e SNYK_TOKEN="${SNYK_TOKEN}" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "${PWD}:/app" \
      -w /app \
      snyk/snyk:alpine \
      snyk container test "${image_ref}" "${dockerfile_arg[@]}"
    scan_exit=$?
    set -e

    if [[ ${scan_exit} -gt 1 ]]; then
      echo "[ERROR] Snyk Container scan failed for ${image_ref} with exit code ${scan_exit}."
      overall_error_exit=1
      continue
    fi
  fi

  if [[ ${scan_exit} -eq 1 ]]; then
    echo "[WARN] Snyk Container found issues for ${image_ref}."
    overall_issue_exit=1
  fi

  if [[ "${monitor_status}" == "enabled" ]]; then
    echo "[INFO] Running Snyk Container monitor for ${image_ref}..."
    set +e
    dockerfile_arg=()
    if [[ -n "${dockerfile_path}" ]]; then
      dockerfile_arg+=(--file="${dockerfile_path}")
    fi
    docker run --rm \
      -e SNYK_TOKEN="${SNYK_TOKEN}" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "${PWD}:/app" \
      -w /app \
      snyk/snyk:alpine \
      snyk container monitor "${image_ref}" "${dockerfile_arg[@]}"
    monitor_exit=$?
    set -e
    if [[ ${monitor_exit} -ne 0 ]]; then
      echo "[WARN] Snyk Container monitor failed for ${image_ref} with exit code ${monitor_exit}."
    fi
  fi

done

if [[ ${overall_error_exit} -eq 1 ]]; then
  exit 2
fi

if [[ ${overall_issue_exit} -eq 1 && "${fail_on_issues}" == "enabled" ]]; then
  exit 1
fi
