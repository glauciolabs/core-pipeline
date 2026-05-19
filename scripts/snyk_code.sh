#!/usr/bin/env bash
set -euo pipefail

SNYK_CONFIG_FILE="${SNYK_CONFIG_FILE:-snyk_job.yaml}"
REPORTS_DIR="${REPORTS_DIR:-reports/snyk}"

if [[ ! -f "${SNYK_CONFIG_FILE}" ]]; then
  echo "[INFO] ${SNYK_CONFIG_FILE} not found. Skipping Snyk Code."
  exit 0
fi

status="$(yq -r '.snyk_code.status // "disabled"' "${SNYK_CONFIG_FILE}")"
monitor_status="$(yq -r '.snyk_code.monitor // "disabled"' "${SNYK_CONFIG_FILE}")"
report_status="$(yq -r '.snyk_code.report // "disabled"' "${SNYK_CONFIG_FILE}")"
fail_on_issues="$(yq -r '.snyk_code.fail_on_issues // "enabled"' "${SNYK_CONFIG_FILE}")"
severity_threshold="$(yq -r '.snyk_code.severity_threshold // .snyk_global.severity_threshold // "low"' "${SNYK_CONFIG_FILE}")"
if [[ "${status}" != "enabled" ]]; then
  echo "[INFO] snyk_code is disabled. Skipping."
  exit 0
fi

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for Snyk Code."
  exit 1
fi

mkdir -p "${REPORTS_DIR}"

scan_exit=0
html_exit=0

if [[ "${report_status}" == "enabled" ]]; then
  echo "[INFO] Running Snyk Code (JSON report)..."
  set +e
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk code test --severity-threshold="${severity_threshold}" --json > "${REPORTS_DIR}/snyk-code.json"
  scan_exit=$?
  set -e

  if [[ ${scan_exit} -gt 1 ]]; then
    exit ${scan_exit}
  fi

  echo "[INFO] Generating HTML report..."
  set +e
  docker run --rm \
    -v "${PWD}:/work" \
    -w /work \
    node:24-alpine \
    sh -c "npm -s i -g snyk-to-html >/dev/null 2>&1 && cat ${REPORTS_DIR}/snyk-code.json | snyk-to-html -o ${REPORTS_DIR}/snyk-code.html"
  html_exit=$?
  set -e
  if [[ ${html_exit} -ne 0 ]]; then
    echo "[WARN] Could not generate HTML report for Snyk Code. Keeping JSON output only."
  fi
else
  echo "[INFO] Running Snyk Code..."
  set +e
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk code test --severity-threshold="${severity_threshold}"
  scan_exit=$?
  set -e

  if [[ ${scan_exit} -gt 1 ]]; then
    exit ${scan_exit}
  fi
fi

if [[ "${monitor_status}" == "enabled" ]]; then
  echo "[WARN] snyk_code monitor is not supported by CLI. Skipping monitor for code."
fi

if [[ ${scan_exit} -eq 1 ]]; then
  echo "[WARN] Snyk Code found issues."
  if [[ "${fail_on_issues}" == "enabled" ]]; then
    exit 1
  fi
fi
