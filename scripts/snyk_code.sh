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
if [[ "${status}" != "enabled" ]]; then
  echo "[INFO] snyk_code is disabled. Skipping."
  exit 0
fi

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for Snyk Code."
  exit 1
fi

mkdir -p "${REPORTS_DIR}"

if [[ "${report_status}" == "enabled" ]]; then
  echo "[INFO] Running Snyk Code (JSON report)..."
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk code test --json > "${REPORTS_DIR}/snyk-code.json"

  echo "[INFO] Generating HTML report..."
  docker run --rm \
    -v "${PWD}:/work" \
    -w /work \
    node:20-alpine \
    sh -c "npm -s i -g snyk-to-html >/dev/null 2>&1 && cat ${REPORTS_DIR}/snyk-code.json | snyk-to-html -o ${REPORTS_DIR}/snyk-code.html"
else
  echo "[INFO] Running Snyk Code..."
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk code test
fi

if [[ "${monitor_status}" == "enabled" ]]; then
  echo "[WARN] snyk_code monitor is not supported by CLI. Skipping monitor for code."
fi
