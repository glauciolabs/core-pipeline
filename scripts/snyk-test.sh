#!/usr/bin/env bash
set -uo pipefail

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for snyk ${SNYK_TEST_NAME}."
  exit 1
fi

if [[ "${SNYK_ENABLE_MONITOR:-false}" == "true" && "${GIT_BRANCH_REF}" =~ ^(main|release)$ ]]; then
  echo "[INFO] snyk monitor is enabled"
  snyk_monitor_arg="monitor"
fi

snyk_iac_test() {
  snyk iac test \
  --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
  json-file-output="${SNYK_REPORTS_DIR}/snyk-iac.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?

}

snyk_open_source_test() {
  snyk "$snyk_monitor_arg" test \
  --project-name=${GIT_REPOSITORY_NAME} org=
  --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
  json-file-output="${SNYK_REPORTS_DIR}/snyk-iac.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?

}

snyk_code_test() {
  snyk code test \
    --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
    --json-file-output="${SNYK_REPORTS_DIR}/snyk-code.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

snyk_container_test() {
  snyk container "$snyk_monitor_arg" test \
    --severity-threshold="${SNYK_SEVERITY_THRESHOLD:-low}" \
    --json-file-output="${SNYK_REPORTS_DIR}/snyk-code.sarif" ${SNYK_ADDITIONAL_ARGS:-} || snyk_scan_exit=$?
}

mkdir -p "${SNYK_REPORTS_DIR}"

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

if [[ "${SNYK_ENABLE_REPORT:-true}" == "true" ]]; then
  echo "[INFO] Generating HTML report..."
  npx snyk-to-html -i "${SNYK_REPORTS_DIR:}/snyk-iac.json" -o "${SNYK_REPORTS_DIR:}/snyk-iac.html" || echo "[WARN] HTML generation failed."
fi

if [[ "${SNYK_FAIL_ON_ISSUES:-true}" == "true" && $snyk_scan_exit -ne 0 ]]; then
  echo "[ERROR] Misconfigurations found!"
  exit $snyk_scan_exit
fi

exit 0