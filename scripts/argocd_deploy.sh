#!/usr/bin/env bash
set -euo pipefail

app_full="${APP_NAME}-${ENVIRONMENT}"
project="${APP_PROJECT:-${APP_NAME}}"
cluster_url="${CLUSTER_URL:-}"

if [[ -z "${cluster_url}" ]]; then
  cluster_url="https://kubernetes.default.svc"
  echo "[WARN] CLUSTER_URL is empty. Falling back to ${cluster_url}"
fi

if [[ "${DEPLOYMENT_MODE}" == "application" ]]; then
  if [[ -z "${APPLICATION_MANIFEST_PATH}" ]]; then
    echo "[ERROR] application_manifest_path is required when deployment_mode=application."
    exit 1
  fi
  if [[ ! -f "${APPLICATION_MANIFEST_PATH}" ]]; then
    echo "[ERROR] Application manifest not found: ${APPLICATION_MANIFEST_PATH}"
    exit 1
  fi
  manifest_app_name="$(yq -r '.metadata.name' "${APPLICATION_MANIFEST_PATH}")"
  if [[ -n "${manifest_app_name}" && "${manifest_app_name}" != "null" ]]; then
    app_full="${manifest_app_name}"
  fi

  echo "Applying application manifest: ${APPLICATION_MANIFEST_PATH}"
  argocd app create -f "${APPLICATION_MANIFEST_PATH}" \
    --grpc-web --insecure \
    --server "${ARGOCD_SERVER}" \
    --auth-token "${ARGOCD_TOKEN}" \
    --upsert
else
  if argocd app list --auth-token "${ARGOCD_TOKEN}" --grpc-web --insecure --server "${ARGOCD_SERVER}" -o json | jq -r '.[].metadata.name' | grep -x "${app_full}"; then
    echo "App exists. Updating and syncing..."
    argocd app set "${app_full}" \
      --grpc-web --insecure \
      --server "${ARGOCD_SERVER}" \
      --path "${KUSTOMIZATION_PATH}" \
      --dest-server "${cluster_url}" \
      --dest-namespace "${NAMESPACE}" \
      --revision "${REPO_TAG}" \
      --project "${project}" \
      --sync-policy automated \
      --auto-prune \
      --self-heal \
      --sync-retry-limit 4 \
      --auth-token "${ARGOCD_TOKEN}"
  else
    echo "Creating app ${app_full}"
    argocd app create "${app_full}" \
      --repo "${REPO_URL}" \
      --path "${KUSTOMIZATION_PATH}" \
      --dest-server "${cluster_url}" \
      --dest-namespace "${NAMESPACE}" \
      --revision "${REPO_TAG}" \
      --project "${project}" \
      --sync-policy automated \
      --self-heal \
      --auto-prune \
      --sync-retry-limit 4 \
      --sync-option CreateNamespace=true \
      --insecure \
      --grpc-web \
      --server "${ARGOCD_SERVER}" \
      --auth-token "${ARGOCD_TOKEN}" \
      --set-finalizer \
      --revision-history-limit 3
  fi
fi

echo "Syncing app ${app_full}"
attempt=1
max_attempts=5
sync_ok=false
while [[ ${attempt} -le ${max_attempts} ]]; do
  set +e
  argocd app sync "${app_full}" \
    --grpc-web \
    --insecure \
    --server "${ARGOCD_SERVER}" \
    --auth-token "${ARGOCD_TOKEN}" \
    --revision "${REPO_TAG}" \
    --project "${project}" \
    --prune \
    --force \
    --replace \
    --timeout 200
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    sync_ok=true
    break
  fi
  echo "Sync attempt ${attempt} failed with code ${status}. Retrying..."
  sleep 10
  attempt=$((attempt+1))
done

if [[ "${sync_ok}" != "true" ]]; then
  echo "[ERROR] Unable to sync app after ${max_attempts} attempts."
  exit 1
fi

echo "Waiting for app ${app_full} to reach Healthy (sync already requested)"
argocd app wait "${app_full}" \
  --health \
  --timeout 600 \
  --grpc-web \
  --insecure \
  --server "${ARGOCD_SERVER}" \
  --auth-token "${ARGOCD_TOKEN}"
