# Inputs and Secrets

## Inputs
- `archetype` (string, required)
  - `containers` or `k8s-apps`
- `docker_options` (string)
  - `build_and_push`, `build_only`, `disable_docker`
- `namespace_override` (boolean)
  - If `true`, use the namespace without environment suffix
- `kustomization_overlay` (boolean)
  - If `true`, use `./app/<env>/overlays`
- `helm_chart` (boolean)
  - Reserved for future use
- `gitops_app` (string)
  - `argocd` or `flux`
- `argocd_deployment_mode` (string)
  - `kustomize` or `application`
- `argocd_application_manifest` (string)
  - Path to an Argo CD Application manifest file (used when `argocd_deployment_mode=application`)

## Secrets
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`
  - Docker Hub credentials (optional)
- `REGISTRY`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`
  - Custom registry credentials (optional)
- `ARGOCD_SERVER`, `ARGOCD_TOKEN`
  - Argo CD API access (required for `gitops_app: argocd`)
- `GITOPS_SSH_PRIVATE_KEY`
  - SSH key used by Argo CD/Flux to read the Git repository (recommended for private repos)
- `CLUSTER_PROD`
  - Cluster API endpoint used by Argo CD
- `AZURE_CREDENTIALS`
  - Azure login JSON (required for `gitops_app: flux` unless using SP_* vars)
- `SP_RG_DEVOPS_APP_ID`, `SP_RG_DEVOPS_SECRET`, `TENANT_ID`
  - Azure service principal credentials (optional alternative to `AZURE_CREDENTIALS`)
