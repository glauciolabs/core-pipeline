#!/usr/bin/env bash
set -euo pipefail

SNYK_TOKEN="${INPUT_SNYK_TOKEN:-${SNYK_TOKEN:-}}"

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for snyk ${SNYK_TEST_NAME:-}."
  exit 1
fi

snyk_iac_test() {
  npx snyk iac test \
  --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
  --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

snyk_open_source_test() {
  npx snyk test \
  --project-name="${GIT_REPOSITORY_NAME:-}" \
  --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
  --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

snyk_code_test() {
  npx snyk code test \
    --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
    --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

snyk_container_test() {
  npx snyk container test \
    --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
    --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

mkdir -p "${SNYK_REPORTS_DIR}"

snyk_test_name="${SNYK_TEST_OVERRIDE:-${SNYK_TEST_NAME:-code}}"

if [[ "${snyk_test_name}" == "code" && "${ARCHETYPE:-}" == "container" ]]; then
  echo "[INFO] Archetype is container and no test override. Falling back to container scan."
  snyk_test_name="container"
fi

if [[ "${snyk_test_name}" == "container" && "${ARCHETYPE:-}" == "container" ]]; then
  if [[ -z "${SNYK_ADDITIONAL_ARGS:-}" ]]; then
    echo "[INFO] Archetype is container, passing target image explicitly from repository name."
    # We default to dockerhub username or ghcr.io based image if we are in deploy_only
    SNYK_ADDITIONAL_ARGS="${GIT_ORGANIZATION_NAME}/${GIT_REPOSITORY_NAME#*/}"
    echo "[INFO] Target image inferred as: ${SNYK_ADDITIONAL_ARGS}"
  fi
  SNYK_ADDITIONAL_ARGS="--exclude-app-vulns ${SNYK_ADDITIONAL_ARGS}"
fi

echo "[INFO] Running ${snyk_test_name} Scan..."

snyk_scan_exit=0

case "${snyk_test_name}" in
  "open-source")
    snyk_open_source_test
    ;; 
  "iac")
    snyk_iac_test
    ;; 
  "code")
    snyk_code_test
    ;;
  "container")
    snyk_container_test
    ;;
  "all")
    echo "[INFO] Running ALL Snyk tests (open-source, iac, code, container)..."
    SNYK_REPORTS_DIR="${SNYK_REPORTS_DIR}/open-source" snyk_open_source_test || true
    SNYK_REPORTS_DIR="${SNYK_REPORTS_DIR}/iac" snyk_iac_test || true
    SNYK_REPORTS_DIR="${SNYK_REPORTS_DIR}/code" snyk_code_test || true
    SNYK_REPORTS_DIR="${SNYK_REPORTS_DIR}/container" snyk_container_test || true
    ;;
esac

if [[ "${SNYK_ENABLE_REPORT:-true}" == "true" && -f "${SNYK_REPORTS_DIR}/snyk.sarif" ]]; then
  echo "[INFO] Generating HTML report..."
  npx snyk-to-html -i "${SNYK_REPORTS_DIR}/snyk.sarif" -o "${SNYK_REPORTS_DIR}/snyk.html" || echo "[WARN] HTML generation failed."
  
  echo "[INFO] Generating Markdown report for GitHub Step Summary..."
  python3 "$(dirname "$0")/snyk_to_markdown.py" "${SNYK_REPORTS_DIR}/snyk.sarif" || echo "[WARN] Markdown generation failed."
fi

if [[ "${SNYK_FAIL_ON_ISSUES:-true}" == "true" && $snyk_scan_exit -ne 0 ]]; then
  if [[ $snyk_scan_exit -eq 3 ]]; then
    echo "[WARN] Snyk was unable to find supported files (Exit code 3). Continuing pipeline."
    exit 0
  else
    echo "[ERROR] Issues found!"
    exit $snyk_scan_exit
  fi
fi

exit 0
