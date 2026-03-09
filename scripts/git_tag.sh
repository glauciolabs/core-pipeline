#!/usr/bin/env bash
set -euo pipefail

load_release_notes() {
  local path="${RELEASE_NOTES_FILE:-}"
  if [[ -n "${path}" ]]; then
    if [[ -f "${path}" ]]; then
      cat "${path}"
      return 0
    fi
    echo "[WARN] release_notes_file not found: ${path}. Falling back to defaults."
  fi

  for fallback in RELEASE_NOTES.md .github/RELEASE_NOTES.md CHANGELOG.md CHANGES.md; do
    if [[ -f "${fallback}" ]]; then
      cat "${fallback}"
      return 0
    fi
  done

  return 1
}

if [[ "${TAG_EXISTS}" == "true" ]]; then
  echo "Tag ${REPO_TAG} already exists. Skipping."
else
  git config user.name "core-pipelines"
  git config user.email "actions@github.com"

  commit_message=$(git log --format=%B -n 1 | head -n 1)

  git tag -a "${REPO_TAG}" -m "${commit_message}"
  git push origin "${REPO_TAG}"
fi

if [[ "${CREATE_RELEASE}" == "true" ]] || [[ "${ENVIRONMENT}" == "production" ]]; then
  release_by_tag_api="https://api.github.com/repos/${REPO}/releases/tags/${REPO_TAG}"
  release_status="$(curl -sS -o /tmp/release-by-tag.json -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${release_by_tag_api}")"

  if [[ "${release_status}" == "200" ]]; then
    echo "Release for ${REPO_TAG} already exists. Skipping creation."
    exit 0
  fi

  if [[ "${release_status}" != "404" ]]; then
    echo "[ERROR] Unexpected response while checking release by tag: HTTP ${release_status}"
    cat /tmp/release-by-tag.json || true
    exit 1
  fi

  prerelease_value="false"
  if [[ "${PRERELEASE:-false}" == "true" ]]; then
    prerelease_value="true"
  fi

  echo "Creating GitHub release for ${REPO_TAG}"
  api="https://api.github.com/repos/${REPO}/releases"
  if release_body="$(load_release_notes)"; then
    payload="$(jq -nc \
      --arg tag "${REPO_TAG}" \
      --arg name "${REPO_TAG}" \
      --arg body "${release_body}" \
      --arg target "${GITHUB_SHA:-}" \
      --argjson prerelease "${prerelease_value}" \
      '{tag_name:$tag,name:$name,target_commitish:$target,body:$body,prerelease:$prerelease,generate_release_notes:false}')"
  else
    payload="$(jq -nc \
      --arg tag "${REPO_TAG}" \
      --arg name "${REPO_TAG}" \
      --arg target "${GITHUB_SHA:-}" \
      --argjson prerelease "${prerelease_value}" \
      '{tag_name:$tag,name:$name,target_commitish:$target,prerelease:$prerelease,generate_release_notes:true}')"
  fi

  create_status="$(curl -sS -o /tmp/release-create.json -w "%{http_code}" -X POST "${api}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "${payload}")"

  if [[ "${create_status}" != "201" ]]; then
    echo "[ERROR] Failed to create release for ${REPO_TAG}: HTTP ${create_status}"
    cat /tmp/release-create.json || true
    exit 1
  fi
fi
