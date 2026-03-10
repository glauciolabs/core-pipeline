#!/usr/bin/env bash
set -euo pipefail

project="${APP_PROJECT}"
cluster_url="${CLUSTER_URL:-}"
project_namespace="${ARGOCD_PROJECT_NAMESPACE:-}"

if [[ -z "${cluster_url}" ]]; then
  cluster_url="https://kubernetes.default.svc"
  echo "[WARN] CLUSTER_URL is empty. Falling back to ${cluster_url}"
fi

add_destination() {
  local server="$1"
  local namespace="$2"
  [[ -z "${server}" || -z "${namespace}" ]] && return 0
  local item="${server},${namespace}"
  for existing in "${DESTINATIONS[@]:-}"; do
    [[ "${existing}" == "${item}" ]] && return 0
  done
  DESTINATIONS+=("${item}")
}

DESTINATIONS=()
add_destination "${cluster_url}" "${project_namespace}"

# Keep both environments allowed by default when namespace follows <base>-<env>.
if [[ "${NAMESPACE_OVERRIDE:-false}" != "true" && -n "${project_namespace}" ]]; then
  namespace_base="${project_namespace}"
  if [[ "${namespace_base}" == *-develop ]]; then
    namespace_base="${namespace_base%-develop}"
  elif [[ "${namespace_base}" == *-production ]]; then
    namespace_base="${namespace_base%-production}"
  fi

  add_destination "${CLUSTER_DEVELOP:-${cluster_url}}" "${namespace_base}-develop"
  add_destination "${CLUSTER_PRODUCTION:-${cluster_url}}" "${namespace_base}-production"
fi

destination_args=()
for destination in "${DESTINATIONS[@]}"; do
  destination_args+=("-d" "${destination}")
done

if argocd proj list --auth-token "${ARGOCD_TOKEN}" --grpc-web --insecure --server "${ARGOCD_SERVER}" -o json | jq -r '.[] | .metadata.name' | grep -x "${project}"; then
  echo "Project exists: ${project}"
  echo "APP_PROJECT=${project}" >> "$GITHUB_ENV"
else
  echo "Creating project ${project}"
  if argocd proj create "${project}" \
    "${destination_args[@]}" \
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
    if argocd proj get "${project}" \
      --auth-token "${ARGOCD_TOKEN}" \
      --grpc-web \
      --insecure \
      --server "${ARGOCD_SERVER}" >/dev/null 2>&1; then
      echo "WARNING: no permission to update project ${project}; using existing project as-is"
      echo "APP_PROJECT=${project}" >> "$GITHUB_ENV"
    else
      echo "WARNING: could not create project ${project}; falling back to default"
      echo "APP_PROJECT=default" >> "$GITHUB_ENV"
    fi
  fi
fi
