#!/usr/bin/env bash
set -euo pipefail

app_full="${APP_NAME}-${ENVIRONMENT}"
project="${APP_PROJECT:-${APP_NAME}}"
cluster_url="${CLUSTER_URL:-}"
delivery_mode="${DELIVERY_MODE:-self-service}"
sync_strategy="${SYNC_STRATEGY:-safe}"

if [[ -z "${cluster_url}" ]]; then
  cluster_url="https://kubernetes.default.svc"
  echo "[WARN] CLUSTER_URL is empty. Falling back to ${cluster_url}"
fi

if [[ "${delivery_mode}" != "self-service" && "${delivery_mode}" != "declarative" ]]; then
  echo "[ERROR] Unsupported DELIVERY_MODE: ${delivery_mode}"
  exit 1
fi

if [[ "${sync_strategy}" != "safe" && "${sync_strategy}" != "replace-force" ]]; then
  echo "[ERROR] Unsupported SYNC_STRATEGY: ${sync_strategy}"
  exit 1
fi

if [[ "${delivery_mode}" == "declarative" ]]; then
  echo "[INFO] DELIVERY_MODE=declarative"
  echo "[INFO] No imperative Argo CD mutation will be executed."

  if [[ -n "${GITOPS_REPO_URL:-}" ]]; then
    echo "[INFO] GitOps repository configured. Promoting revision by Git commit."
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitops_promote.sh"
  else
    echo "[INFO] Publish/tag completed. Promotion must happen in the GitOps environment repository."
  fi

  if argocd app get "${app_full}" \
    --grpc-web \
    --insecure \
    --server "${ARGOCD_SERVER}" \
    --auth-token "${ARGOCD_TOKEN}" \
    -o json >/tmp/argocd-app.json 2>/tmp/argocd-app.err; then
    current_revision="$(jq -r '.spec.source.targetRevision // ""' /tmp/argocd-app.json)"
    sync_status="$(jq -r '.status.sync.status // ""' /tmp/argocd-app.json)"
    health_status="$(jq -r '.status.health.status // ""' /tmp/argocd-app.json)"
    echo "[INFO] Existing app: ${app_full}"
    echo "[INFO] Current targetRevision: ${current_revision}"
    echo "[INFO] Current status: sync=${sync_status} health=${health_status}"
    if [[ "${current_revision}" != "${REPO_TAG}" ]]; then
      echo "[INFO] Desired revision ${REPO_TAG} is not active yet. Update the GitOps repo to promote it."
    fi
  else
    echo "[WARN] App ${app_full} was not found in Argo CD."
    echo "[WARN] In declarative mode, bootstrap must happen from the GitOps repo or a dedicated bootstrap workflow."
    cat /tmp/argocd-app.err || true
  fi

  exit 0
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

if [[ "${DEPLOYMENT_MODE}" != "application" ]]; then
  echo "Validating app target revision: ${REPO_TAG}"
  revision_ok=false
  for _ in {1..10}; do
    current_revision="$(
      argocd app get "${app_full}" \
        --grpc-web \
        --insecure \
        --server "${ARGOCD_SERVER}" \
        --auth-token "${ARGOCD_TOKEN}" \
        -o json | jq -r '.spec.source.targetRevision // ""'
    )"

    if [[ "${current_revision}" == "${REPO_TAG}" ]]; then
      revision_ok=true
      break
    fi

    sleep 2
  done

  if [[ "${revision_ok}" != "true" ]]; then
    echo "[ERROR] App ${app_full} target revision mismatch. Expected: ${REPO_TAG} | Current: ${current_revision}"
    exit 1
  fi
fi

echo "Syncing app ${app_full}"
sync_args=(
  --grpc-web
  --insecure
  --server "${ARGOCD_SERVER}"
  --auth-token "${ARGOCD_TOKEN}"
  --project "${project}"
  --prune
  --timeout 200
)

if [[ "${sync_strategy}" == "replace-force" ]]; then
  sync_args+=(--force --replace)
fi

attempt=1
max_attempts=5
sync_ok=false
while [[ ${attempt} -le ${max_attempts} ]]; do
  set +e
  argocd app sync "${app_full}" "${sync_args[@]}"
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
