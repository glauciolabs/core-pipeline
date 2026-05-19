#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="container"
DOCKER_OPTIONS="${DOCKER_OPTIONS:-build_and_push}"
built_any="false"
noop_existing="false"
processed_services=0
existing_services=0
built_services=0

emit_outputs() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "built_any=${built_any}"
      echo "noop_existing=${noop_existing}"
    } >> "${GITHUB_OUTPUT}"
  fi
}

trap emit_outputs EXIT

if [[ "$DOCKER_OPTIONS" == "disable" || "$DOCKER_OPTIONS" == "disable_docker" ]]; then
  echo "[INFO] DOCKER_OPTIONS is disabled. Skipping container build."
  exit 0
fi

OCI_LABEL_ARGS=()
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  OCI_LABEL_ARGS+=(--label "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}")
fi
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  OCI_LABEL_ARGS+=(--label "org.opencontainers.image.url=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}")
fi
if [[ -n "${GITHUB_SHA:-}" ]]; then
  OCI_LABEL_ARGS+=(--label "org.opencontainers.image.revision=${GITHUB_SHA}")
fi

if [[ ! -d "${ROOT_DIR}" ]]; then
  echo "[INFO] Directory ${ROOT_DIR} not found. Nothing to build."
  exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "[ERROR] yq is required."
  exit 1
fi

extract_repo_path() {
  local repo="$1"
  local first="${repo%%/*}"
  local rest="${repo#*/}"
  if [[ "$repo" == */* && ( "$first" == *.* || "$first" == *:* || "$first" == "localhost" ) ]]; then
    echo "$rest"
  else
    echo "$repo"
  fi
}

echo "[INFO] Docker options: ${DOCKER_OPTIONS}"

echo "[INFO] Visible builders:"
docker buildx ls || true

for dir in "${ROOT_DIR}"/*; do
  [[ -d "${dir}" ]] || continue

  info_file="${dir}/info.yaml"
  dockerfile_path="${dir}/Dockerfile"

  if [[ ! -f "${info_file}" ]]; then
    echo ">> [SKIP] ${dir} - missing info.yaml"
    continue
  fi

  if [[ ! -f "${dockerfile_path}" ]]; then
    echo ">> [SKIP] ${dir} - missing Dockerfile"
    continue
  fi

  echo "========================================"
  echo "Processing directory: ${dir}"
  echo "info.yaml: ${info_file}"
  echo "Dockerfile: ${dockerfile_path}"

  app_name=$(yq -r '.app.name' "${info_file}")
  container_repository=$(yq -r '.app.container.repository' "${info_file}")
  container_registry=$(yq -r '.app.container.registry' "${info_file}")
  container_platform=$(yq -r '.app.container.platform // "linux/arm64,linux/amd64"' "${info_file}")
  container_tag=$(yq -r '.app.container.tag' "${info_file}")
  repo_tag=$(yq -r '.app.version' "${info_file}")

  branch_name="${GITHUB_REF_NAME:-}"
  image_tag="${container_tag}"
  if [[ -n "${branch_name}" && "${branch_name}" != "master" && "${image_tag}" != *-dev ]]; then
    image_tag="${image_tag}-dev"
  fi

  echo "app_name: ${app_name}"
  echo "container_repository: ${container_repository}"
  echo "container_registry: ${container_registry}"
  echo "container_platform: ${container_platform}"
  echo "container_tag: ${container_tag}"
  echo "image_tag: ${image_tag}"
  echo "repo_tag: ${repo_tag}"

  if [[ -z "${container_repository}" || -z "${container_tag}" ]]; then
    echo ">> [SKIP] ${dir} - container_repository or container_tag is empty."
    continue
  fi

  processed_services=$((processed_services + 1))
  image_ref="${container_repository}:${image_tag}"
  secondary_image_ref=""
  if [[ -n "${REGISTRY:-}" ]]; then
    repo_path="$(extract_repo_path "${container_repository}")"
    secondary_repo="${REGISTRY}/${repo_path}"
    secondary_image_ref="${secondary_repo}:${image_tag}"
    if [[ "${secondary_image_ref}" == "${image_ref}" ]]; then
      secondary_image_ref=""
    fi
  fi

  platforms_raw="${container_platform}"
  IFS=',' read -ra PLATFORMS <<< "${platforms_raw}"

  platforms_trimmed=()
  for p in "${PLATFORMS[@]}"; do
    plat="$(echo "${p}" | xargs)"
    [[ -n "${plat}" ]] && platforms_trimmed+=("${plat}")
  done

  ordered_platforms=()
  if printf '%s\n' "${platforms_trimmed[@]}" | grep -Fxq "linux/arm64"; then
    ordered_platforms+=("linux/arm64")
  fi
  if printf '%s\n' "${platforms_trimmed[@]}" | grep -Fxq "linux/amd64"; then
    ordered_platforms+=("linux/amd64")
  fi
  for plat in "${platforms_trimmed[@]}"; do
    if [[ "${plat}" != "linux/arm64" && "${plat}" != "linux/amd64" ]]; then
      ordered_platforms+=("${plat}")
    fi
  done

  PLATFORMS=("${ordered_platforms[@]}")

  if [[ "${DOCKER_OPTIONS}" == "build_and_push" ]]; then
    echo "Checking if image ${image_ref} exists..."
    if docker manifest inspect "${image_ref}" > /dev/null 2>&1; then
      echo ">> [WARN] Image ${image_ref} already exists. Skipping this service."
      existing_services=$((existing_services + 1))
      continue
    else
      echo ">> Image ${image_ref} does not exist. Building and pushing per platform..."
    fi

    arch_image_refs=()
    secondary_arch_image_refs=()
    skip_service_due_existing_arch="false"

    for p in "${PLATFORMS[@]}"; do
      plat="$(echo "${p}" | xargs)"
      [[ -z "${plat}" ]] && continue

      arch="${plat#linux/}"
      arch_tag="${image_ref}-${arch}"
      secondary_arch_tag=""
      if [[ -n "${secondary_image_ref}" ]]; then
        secondary_arch_tag="${secondary_image_ref}-${arch}"
      fi

      echo "Checking if tag ${arch_tag} exists..."
      if docker manifest inspect "${arch_tag}" > /dev/null 2>&1; then
        echo ">> [WARN] Tag ${arch_tag} already exists. Skipping this service."
        skip_service_due_existing_arch="true"
        arch_image_refs=()
        break
      fi
      if [[ -n "${secondary_arch_tag}" ]]; then
        echo "Checking if tag ${secondary_arch_tag} exists..."
        if docker manifest inspect "${secondary_arch_tag}" > /dev/null 2>&1; then
          echo ">> [WARN] Tag ${secondary_arch_tag} already exists. Skipping this service."
          skip_service_due_existing_arch="true"
          arch_image_refs=()
          break
        fi
      fi

      echo ">> Build & push for platform: ${plat} (tag: ${arch_tag})"

      build_tags=(-t "${arch_tag}")
      if [[ -n "${secondary_arch_tag}" ]]; then
        build_tags+=(-t "${secondary_arch_tag}")
      fi

      docker buildx build \
        --platform "${plat}" \
        "${build_tags[@]}" \
        "${OCI_LABEL_ARGS[@]}" \
        -f "${dockerfile_path}" "${ROOT_DIR}" \
        --push

      arch_image_refs+=("${arch_tag}")
      if [[ -n "${secondary_arch_tag}" ]]; then
        secondary_arch_image_refs+=("${secondary_arch_tag}")
      fi
    done

    if [[ ${#arch_image_refs[@]} -eq 0 ]]; then
      if [[ "${skip_service_due_existing_arch}" == "true" ]]; then
        existing_services=$((existing_services + 1))
      fi
      echo ">> [INFO] No new arch tags were built for ${image_ref}. Continuing."
      continue
    fi

    echo "Creating multi-arch manifest for ${image_ref} from tags:"
    printf '  - %s\n' "${arch_image_refs[@]}"

    docker buildx imagetools create \
      -t "${image_ref}" \
      "${arch_image_refs[@]}"

    echo "Multi-arch image ${image_ref} created successfully."
    built_services=$((built_services + 1))

    if [[ -n "${secondary_image_ref}" ]]; then
      echo "Creating multi-arch manifest for ${secondary_image_ref} from tags:"
      printf '  - %s\n' "${secondary_arch_image_refs[@]}"

      docker buildx imagetools create \
        -t "${secondary_image_ref}" \
        "${secondary_arch_image_refs[@]}"

      echo "Multi-arch image ${secondary_image_ref} created successfully."
    fi


  elif [[ "${DOCKER_OPTIONS}" == "build_only" ]]; then
    echo "Running build_only (no push) for ${image_ref}..."

    first_plat="$(echo "${container_platform}" | cut -d',' -f1 | xargs)"

    docker buildx build \
      --platform "${first_plat}" \
      -t "${image_ref}" \
      "${OCI_LABEL_ARGS[@]}" \
      -f "${dockerfile_path}" "${ROOT_DIR}" \
      --load

    echo "Docker image ${image_ref} built locally (no push)."

  else
    echo ">> [SKIP] docker_options='${DOCKER_OPTIONS}' not handled."
  fi

done

echo "========================================"
echo "Build loop finished."

if [[ "${DOCKER_OPTIONS}" == "build_and_push" ]]; then
  if [[ ${built_services} -gt 0 ]]; then
    built_any="true"
  fi
  if [[ ${processed_services} -gt 0 && ${built_services} -eq 0 && ${existing_services} -eq ${processed_services} ]]; then
    noop_existing="true"
    echo "[INFO] Build was a no-op because all target image tags already existed."
  fi
fi
