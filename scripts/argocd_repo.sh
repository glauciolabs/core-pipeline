#!/usr/bin/env bash
set -euo pipefail

ssh_args=()
if [[ -n "${GITOPS_SSH_PRIVATE_KEY}" ]]; then
  key_file="/tmp/gitops_ssh_key"
  printf '%s' "${GITOPS_SSH_PRIVATE_KEY}" > "${key_file}"
  chmod 600 "${key_file}"
  ssh_args+=(--ssh-private-key-path "${key_file}")
fi

repos_json=$(argocd repo --grpc-web list \
  --server "${ARGOCD_SERVER}" \
  --auth-token "${ARGOCD_TOKEN}" \
  --insecure -o json)

if echo "$repos_json" | jq -r '.[].repo' | grep -x -- "${REPO_URL}"; then
  echo "Repo already registered in Argo CD."
else
  echo "Registering repo in Argo CD..."
  argocd repo add "${REPO_URL}" \
    --name "${APP_NAME}" \
    --project "${APP_PROJECT}" \
    --auth-token "${ARGOCD_TOKEN}" \
    --grpc-web --insecure \
    --server "${ARGOCD_SERVER}" \
    "${ssh_args[@]}"
fi
