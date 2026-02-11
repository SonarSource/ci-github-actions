#!/bin/bash
# Cleanup caches and artifacts for a pull request in a GitHub repository.
# Required environment variables:
#   GH_TOKEN          - GitHub token with actions:write permission for cache and artifact deletion
#   CACHE_REF         - Cache reference in the format "refs/pull/<pr_number>/merge"
#   GITHUB_REPOSITORY - Repository name with owner (e.g. "owner/repo")
#   GITHUB_HEAD_REF   - Head branch reference of the pull request

set -euo pipefail

: "${GH_TOKEN:?Required environment variable not set}" # used by gh CLI
: "${CACHE_REF:?Required environment variable not set}"
: "${GITHUB_REPOSITORY:?Required environment variable not set}"
: "${GITHUB_HEAD_REF:?Required environment variable not set}"

CURDIR=$(dirname "$0")
readonly CACHE_LIST_LIMIT=100000

echo "::group::Cache Cleanup"
echo "Fetching list of cache keys on $GITHUB_REPOSITORY for $CACHE_REF"
CACHE_TEMPLATE="$(cat "$CURDIR"/cache_template.tpl)"
gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --limit "$CACHE_LIST_LIMIT" --json id,key,sizeInBytes --template "$CACHE_TEMPLATE"
echo

cacheKeysForPR="$(gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --limit "$CACHE_LIST_LIMIT" --json id --jq '.[].id')"
echo "Deleting caches..."
for cacheKey in $cacheKeysForPR
do
  echo "Deleting cache key: $cacheKey"
  gh cache delete --repo "$GITHUB_REPOSITORY" "$cacheKey"
done
echo

echo "Fetching list of cache keys after deletion"
gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --limit "$CACHE_LIST_LIMIT" --json id,key,sizeInBytes --template "$CACHE_TEMPLATE"
echo
echo "::endgroup::"

echo "::group::Artifact Cleanup"
echo "Fetching list of artifacts on $GITHUB_REPOSITORY for $GITHUB_HEAD_REF"
tpl_tmp_file="$(mktemp)"
# shellcheck disable=SC2016
envsubst '$GITHUB_HEAD_REF' < "$CURDIR"/artifact_template.tpl > "$tpl_tmp_file"
ARTIFACT_TEMPLATE="$(cat "$tpl_tmp_file")"

ARTIFACT_API_URL="/repos/$GITHUB_REPOSITORY/actions/artifacts"
gh api "$ARTIFACT_API_URL" --paginate --template "$ARTIFACT_TEMPLATE"
echo

artifactIds="$(gh api "$ARTIFACT_API_URL" --paginate --jq '.artifacts[] | select(.workflow_run.head_branch == "'"$GITHUB_HEAD_REF"'") | .id')"
echo "Deleting artifacts..."
for artifactId in $artifactIds
do
  echo "Deleting artifact: $artifactId"
  gh api -X DELETE "$ARTIFACT_API_URL/$artifactId" || true
done
echo

echo "Fetching list of artifacts after deletion"
gh api "$ARTIFACT_API_URL" --paginate --template "$ARTIFACT_TEMPLATE"
echo "::endgroup::"
