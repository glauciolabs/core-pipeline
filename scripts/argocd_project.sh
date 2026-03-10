#!/usr/bin/env bash
set -euo pipefail

project="${APP_PROJECT}"
cluster_url="${CLUSTER_URL:-}"

if [[ -z "${cluster_url}" ]]; then
  cluster_url="https://kubernetes.default.svc"
  echo "[WARN] CLUSTER_URL is empty. Falling back to ${cluster_url}"
fi

if argocd proj list --auth-token "${ARGOCD_TOKEN}" --grpc-web --insecure --server "${ARGOCD_SERVER}" -o json | jq -r '.[] | .metadata.name' | grep -x "${project}"; then
  echo "Project exists: ${project}"
  echo "APP_PROJECT=${project}" >> "$GITHUB_ENV"
else
  echo "Creating project ${project}"
  if argocd proj create "${project}" \
    -d "${cluster_url}","${ARGOCD_PROJECT_NAMESPACE}" \
    -s "${REPO_URL}" \
    --upsert \
    --auth-token "${ARGOCD_TOKEN}" \
    --grpc-web \
    --insecure \
    --server "${ARGOCD_SERVER}" \
    --allow-namespaced-resource '*/*' \
    --allow-cluster-resource '*/*'; then
    echo "APP_PROJECT=${project}" >> "$GITHUB_ENV"
  else
    echo "WARNING: could not create project ${project}; falling back to default"
    echo "APP_PROJECT=default" >> "$GITHUB_ENV"
  fi
fi
