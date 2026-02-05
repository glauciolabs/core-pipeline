# Core Pipelines (GitHub Actions)

This repository contains reusable GitHub Actions workflows that replace the previous Azure DevOps templates.

## What you get
- One reusable workflow: `.github/workflows/core-pipeline.yml`
- Container build support (multi-arch, buildx)
- Git tagging based on `info.yaml`
- GitOps deploy via Argo CD or Flux

## Requirements
- `info.yaml` at repository root
- For container builds: `container/*/info.yaml` and `container/*/Dockerfile`
- Secrets configured in the caller repository or organization

## Example (containers)
```yaml
name: CI/CD

on:
  push:
    branches:
      - develop
      - production
  workflow_dispatch:
    inputs:
      docker_options:
        type: choice
        options:
          - build_and_push
          - build_only
          - disable_docker
        default: build_and_push

jobs:
  pipeline:
    uses: SpartanOps/core-pipelines/.github/workflows/core-pipeline.yml@v1.0.0
    with:
      archetype: containers
      docker_options: ${{ github.event_name == 'workflow_dispatch' && inputs.docker_options || 'build_and_push' }}
      kustomization_overlay: false
      helm_chart: false
      gitops_app: argocd
      namespace_override: false
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
      REGISTRY: ${{ secrets.REGISTRY }}
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
      ARGOCD_SERVER: ${{ secrets.ARGOCD_SERVER }}
      ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
      GITOPS_SSH_PRIVATE_KEY: ${{ secrets.GITOPS_SSH_PRIVATE_KEY }}
      CLUSTER_PROD: ${{ secrets.CLUSTER_PROD }}
```

## Example (k8s-apps + Flux)
```yaml
name: CD

on:
  push:
    branches:
      - develop
      - production

jobs:
  pipeline:
    uses: SpartanOps/core-pipelines/.github/workflows/core-pipeline.yml@v1.0.0
    with:
      archetype: k8s-apps
      gitops_app: flux
      kustomization_overlay: false
      namespace_override: false
    secrets:
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
      SP_RG_DEVOPS_APP_ID: ${{ secrets.SP_RG_DEVOPS_APP_ID }}
      SP_RG_DEVOPS_SECRET: ${{ secrets.SP_RG_DEVOPS_SECRET }}
      TENANT_ID: ${{ secrets.TENANT_ID }}
      GITOPS_SSH_PRIVATE_KEY: ${{ secrets.GITOPS_SSH_PRIVATE_KEY }}
      CLUSTER_PROD: ${{ secrets.CLUSTER_PROD }}
```

## Notes
- The workflow tags commits as `<version>-<short_sha>-<environment>`.
- Only `develop` and `production` branches are supported (matching the Azure pipeline behavior).
