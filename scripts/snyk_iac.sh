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
fail_on_issues="$(yq -r '.snyk_iac.fail_on_issues // "enabled"' "${SNYK_CONFIG_FILE}")"

if [[ "${status}" != "enabled" ]]; then
  echo "[INFO] snyk_iac is disabled. Skipping."
  exit 0
fi

if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "[ERROR] SNYK_TOKEN is required for Snyk IaC."
  exit 1
fi

mkdir -p "${REPORTS_DIR}"

scan_exit=0
html_exit=0

if [[ "${report_status}" == "enabled" ]]; then
  echo "[INFO] Running Snyk IaC (JSON report)..."
  set +e
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk iac test --json-file-output="${REPORTS_DIR}/snyk-iac.json"
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
    sh -c "npm -s i -g snyk-to-html >/dev/null 2>&1 && cat ${REPORTS_DIR}/snyk-iac.json | snyk-to-html -o ${REPORTS_DIR}/snyk-iac.html"
  html_exit=$?
  set -e
  if [[ ${html_exit} -ne 0 ]]; then
    echo "[WARN] Could not generate HTML report for Snyk IaC. Keeping JSON output only."
  fi
else
  echo "[INFO] Running Snyk IaC..."
  set +e
  docker run --rm \
    -e SNYK_TOKEN="${SNYK_TOKEN}" \
    -v "${PWD}:/app" \
    -w /app \
    snyk/snyk:alpine \
    snyk iac test
  scan_exit=$?
  set -e

  if [[ ${scan_exit} -gt 1 ]]; then
    exit ${scan_exit}
  fi
fi

if [[ ${scan_exit} -eq 1 ]]; then
  echo "[WARN] Snyk IaC found issues."
  if [[ "${fail_on_issues}" == "enabled" ]]; then
    exit 1
  fi
fi
