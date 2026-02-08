# Inputs and Secrets

## Inputs
- `pipeline_mode` (string)
  - `build_and_push`, `build_only`, or `deploy_only`
- `archetype` (string, required)
  - `containers` or `k8s-apps`
- `namespace_override` (boolean)
  - If `true`, use the namespace without environment suffix
- `kustomization_overlay` (boolean)
  - If `true`, use `./app/<env>/overlays`
- `helm_chart` (boolean)
  - Reserved for future use
- `gitops_app` (string)
  - `argocd`
- `argocd_deployment_mode` (string)
  - `kustomize` or `application`
- `argocd_application_manifest` (string)
  - Path to an Argo CD Application manifest file (used when `argocd_deployment_mode=application`)

## Secrets
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`
  - Docker Hub credentials (optional)
- `REGISTRY`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`
  - Custom registry credentials (optional)
- `SNYK_TOKEN`
  - Required if `snyk_job.yaml` enables `snyk_code` or `snyk_container`
- `ARGOCD_SERVER`, `ARGOCD_TOKEN`
  - Argo CD API access (required for `gitops_app: argocd`)
- `GITOPS_SSH_PRIVATE_KEY`
  - SSH key used by Argo CD/Flux to read the Git repository (recommended for private repos)
- `CLUSTER_PROD`
- `CLUSTER_DEVELOP`
  - Cluster API endpoint for `develop`
- `CLUSTER_PRODUCTION`
  - Cluster API endpoint for `production`

## Snyk toggles
Create a `snyk_job.yaml` at the repository root:
```yaml
snyk_code:
  status: enabled
  monitor: disabled
  report: enabled
snyk_iac:
  status: disabled
snyk_oss:
  status: enabled
snyk_container:
  status: disabled
  monitor: disabled
  report: disabled
```

Supported toggles per check:
- `status`: `enabled` or `disabled`
- `monitor`: `enabled` or `disabled` (OSS and Container)
- `report`: `enabled` or `disabled` (outputs HTML + JSON)

## Dual registry push
If `REGISTRY` is set, images are pushed to both:
- Primary: `container_repository` from `info.yaml`
- Secondary: `${REGISTRY}/<repository-path>`
