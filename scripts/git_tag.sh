#!/usr/bin/env bash
set -euo pipefail

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
  echo "Creating GitHub release for ${REPO_TAG}"
  api="https://api.github.com/repos/${REPO}/releases"
  payload=$(jq -nc --arg tag "${REPO_TAG}" --arg name "${REPO_TAG}" '{tag_name:$tag,name:$name,prerelease:false}')
  curl -sSf -X POST "${api}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload}"
fi
