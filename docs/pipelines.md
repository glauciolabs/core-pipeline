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
      pipeline_mode:
        type: choice
        options:
          - build_and_push
          - build_only
          - deploy_only
        default: build_and_push

jobs:
  pipeline:
    uses: SpartanOps/core-pipelines/.github/workflows/core-pipeline.yml@v1.0.0
    with:
      pipeline_mode: ${{ github.event_name == 'workflow_dispatch' && inputs.pipeline_mode || 'build_and_push' }}
      archetype: containers
      kustomization_overlay: false
      helm_chart: false
      gitops_app: argocd
      argocd_deployment_mode: kustomize
      argocd_application_manifest: ""
      namespace_override: false
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
      REGISTRY: ${{ secrets.REGISTRY }}
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
      SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      ARGOCD_SERVER: ${{ secrets.ARGOCD_SERVER }}
      ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
      GITOPS_SSH_PRIVATE_KEY: ${{ secrets.GITOPS_SSH_PRIVATE_KEY }}
      CLUSTER_DEVELOP: ${{ secrets.CLUSTER_DEVELOP }}
      CLUSTER_PRODUCTION: ${{ secrets.CLUSTER_PRODUCTION }}
```

## Notes
- The workflow tags commits as `<version>-<short_sha>-<environment>`.
- Only `develop` and `production` branches are supported (matching the Azure pipeline behavior).
- Security checks are controlled by `snyk_job.yaml` in the caller repository.
- Security runs as a dedicated gate job after build and before tag/deploy.
