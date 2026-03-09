#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="container"
DOCKER_OPTIONS="${DOCKER_OPTIONS:-build_and_push}"

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

  echo "app_name: ${app_name}"
  echo "container_repository: ${container_repository}"
  echo "container_registry: ${container_registry}"
  echo "container_platform: ${container_platform}"
  echo "container_tag: ${container_tag}"
  echo "repo_tag: ${repo_tag}"

  if [[ -z "${container_repository}" || -z "${container_tag}" ]]; then
    echo ">> [SKIP] ${dir} - container_repository or container_tag is empty."
    continue
  fi

  image_ref="${container_repository}:${container_tag}"
  secondary_image_ref=""
  if [[ -n "${REGISTRY:-}" ]]; then
    repo_path="$(extract_repo_path "${container_repository}")"
    secondary_repo="${REGISTRY}/${repo_path}"
    secondary_image_ref="${secondary_repo}:${container_tag}"
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
      echo ">> [SKIP] Image ${image_ref} already exists. Skipping build."
      continue
    else
      echo ">> Image ${image_ref} does not exist. Building and pushing per platform..."
    fi

    arch_image_refs=()
    secondary_arch_image_refs=()

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
        echo ">> [FAIL] Tag ${arch_tag} already exists. Not overwriting."
        exit 0
      fi
      if [[ -n "${secondary_arch_tag}" ]]; then
        echo "Checking if tag ${secondary_arch_tag} exists..."
        if docker manifest inspect "${secondary_arch_tag}" > /dev/null 2>&1; then
          echo ">> [FAIL] Tag ${secondary_arch_tag} already exists. Not overwriting."
          exit 0
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

    echo "Creating multi-arch manifest for ${image_ref} from tags:"
    printf '  - %s\n' "${arch_image_refs[@]}"

    docker buildx imagetools create \
      -t "${image_ref}" \
      "${arch_image_refs[@]}"

    echo "Multi-arch image ${image_ref} created successfully."

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
