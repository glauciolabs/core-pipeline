#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for snyk ${SNYK_TEST_NAME:-}."
  exit 1
fi

snyk_monitor_arg=""
if [[ "${SNYK_ENABLE_MONITOR:-false}" == "true" && "${GIT_BRANCH_REF:-}" =~ ^(main|release)$ ]]; then
  echo "[INFO] snyk monitor is enabled"
  snyk_monitor_arg="monitor"
fi

snyk_iac_test() {
  npx snyk iac test \
  --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
  --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

snyk_open_source_test() {
  if [[ -n "$snyk_monitor_arg" ]]; then
    npx snyk "$snyk_monitor_arg" \
      --project-name="${GIT_REPOSITORY_NAME:-}" \
      --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
      ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
  fi
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
  if [[ -n "$snyk_monitor_arg" ]]; then
    npx snyk container "$snyk_monitor_arg" \
      --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
      ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
  fi
  npx snyk container test \
    --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
    --sarif-file-output="${SNYK_REPORTS_DIR}/snyk.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

mkdir -p "${SNYK_REPORTS_DIR}"

snyk_test_name="${SNYK_TEST_NAME:-code}"
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
esac

if [[ "${SNYK_ENABLE_REPORT:-true}" == "true" && -f "${SNYK_REPORTS_DIR}/snyk.sarif" ]]; then
  echo "[INFO] Generating HTML report..."
  npx snyk-to-html -i "${SNYK_REPORTS_DIR}/snyk.sarif" -o "${SNYK_REPORTS_DIR}/snyk.html" || echo "[WARN] HTML generation failed."
fi

if [[ "${SNYK_FAIL_ON_ISSUES:-true}" == "true" && $snyk_scan_exit -ne 0 ]]; then
  echo "[ERROR] Issues found!"
  exit $snyk_scan_exit
fi

exit 0