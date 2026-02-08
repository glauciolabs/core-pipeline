#!/usr/bin/env bash
set -euo pipefail

SNYK_CONFIG_FILE="${SNYK_CONFIG_FILE:-snyk_job.yaml}"
REPORTS_DIR="${REPORTS_DIR:-reports/snyk}"

if [[ ! -f "${SNYK_CONFIG_FILE}" ]]; then
  echo "[INFO] ${SNYK_CONFIG_FILE} not found. Skipping Snyk IaC."
  exit 0
fi

status="$(yq -r '.snyk_iac.status // "disabled"' "${SNYK_CONFIG_FILE}")"
report_status="$(yq -r '.snyk_iac.report // "disabled"' "${SNYK_CONFIG_FILE}")"

if [[ "${status}" != "enabled" ]]; then
  echo "[INFO] snyk_iac is disabled. Skipping."
  exit 0
fi

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for Snyk IaC."
  exit 1
fi

mkdir -p "${REPORTS_DIR}"

if [[ "${report_status}" == "enabled" ]]; then
  echo "[INFO] Running Snyk IaC (JSON report)..."
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk iac test --json > "${REPORTS_DIR}/snyk-iac.json"

  echo "[INFO] Generating HTML report..."
  docker run --rm \
    -v "${PWD}:/work" \
    -w /work \
    node:20-alpine \
    sh -c "npm -s i -g snyk-to-html >/dev/null 2>&1 && cat ${REPORTS_DIR}/snyk-iac.json | snyk-to-html -o ${REPORTS_DIR}/snyk-iac.html"
else
  echo "[INFO] Running Snyk IaC..."
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk iac test
fi
