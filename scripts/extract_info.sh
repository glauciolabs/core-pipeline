#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f info.yaml ]]; then
  echo "[ERROR] info.yaml not found at repository root."
  exit 1
fi

run_yq() {
  if command -v yq >/dev/null 2>&1; then
    yq "$@"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -i \
      -v "${PWD}:/workdir" \
      -w /workdir \
      mikefarah/yq:4 "$@"
    return
  fi
  echo "[ERROR] yq not found and docker unavailable."
  exit 1
}

org_name="${GITHUB_REPOSITORY_OWNER:-unknown}"
repo_full="${GITHUB_REPOSITORY:-unknown/unknown}"
repo_url="git@github.com:${repo_full}.git"

app_name=$(run_yq -r '.app.name' info.yaml)
app_project=$(run_yq -r '.app.project' info.yaml)
namespace=$(run_yq -r '.app.namespace' info.yaml)
repo_tag_base=$(run_yq -r '.app.version' info.yaml)
commit_id=$(git rev-parse --short HEAD)

last_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
last_tag_prefix="${last_tag%%-*}"

environment=""
cluster_name=""
# Branch mapping rule:
# - master => production
# - any other branch => develop
if [[ "${GITHUB_REF_NAME:-}" == "master" ]]; then
  environment="production"
  cluster_name="k8s-production-cluster"
else
  environment="develop"
  cluster_name="k8s-develop-cluster"
fi

full_tag_name="${repo_tag_base}-${commit_id}-${environment}"

tag_exists="false"
if git tag -l | grep -Fxq "$full_tag_name"; then
  tag_exists="true"
fi

kustomization_path="./app/${environment}"
if [[ "${KUSTOMIZATION_OVERLAY:-false}" == "true" ]]; then
  kustomization_path="./app/${environment}/overlays"
fi

resource_group="rg-devops"

if [[ "${NAMESPACE_OVERRIDE:-false}" == "true" ]]; then
  namespace_environment="$namespace"
  argocd_project_namespace="$namespace"
else
  namespace_environment="${namespace}-${environment}"
  argocd_project_namespace="${namespace}-${environment}"
fi

cluster_url=""
case "${environment}" in
  develop)
    cluster_url="${CLUSTER_DEVELOP:-}"
    ;;
  production)
    cluster_url="${CLUSTER_PRODUCTION:-}"
    ;;
esac

{
  echo "org_name=${org_name}"
  echo "app_name=${app_name}"
  echo "repo_tag=${full_tag_name}"
  echo "app_project=${app_project}"
  echo "environment=${environment}"
  echo "repo_url=${repo_url}"
  echo "cluster_url=${cluster_url}"
  echo "argocd_project_namespace=${argocd_project_namespace}"
  echo "namespace=${namespace_environment}"
  echo "tag_exists=${tag_exists}"
  echo "kustomization_path=${kustomization_path}"
  echo "resource_group=${resource_group}"
  echo "cluster_name=${cluster_name}"
  echo "commit_id=${commit_id}"
  echo "last_tag_prefix=${last_tag_prefix}"
  echo "last_tag=${last_tag}"
} >> "${GITHUB_OUTPUT}"

{
  echo "[INFO] app_name: ${app_name}"
  echo "[INFO] app_project: ${app_project}"
  echo "[INFO] repo_tag: ${full_tag_name}"
  echo "[INFO] environment: ${environment}"
  echo "[INFO] namespace: ${namespace_environment}"
  echo "[INFO] repo_url: ${repo_url}"
  echo "[INFO] tag_exists: ${tag_exists}"
  echo "[INFO] kustomization_path: ${kustomization_path}"
  echo "[INFO] cluster_name: ${cluster_name}"
} 
