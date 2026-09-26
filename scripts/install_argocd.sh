#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y curl git jq yq ca-certificates

arch_raw="$(uname -m)"
case "$arch_raw" in
  x86_64) arch="amd64" ;;
  aarch64) arch="arm64" ;;
  armv7l) arch="armhf" ;;
  *) arch="$arch_raw" ;;
esac

argocd_version="${ARGOCD_CLI_VERSION:-v3.4.3}"

sudo curl -L -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${argocd_version}/argocd-linux-${arch}"
sudo chmod +x /usr/local/bin/argocd
