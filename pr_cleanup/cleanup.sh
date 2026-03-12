#!/bin/bash
# Cleanup caches and artifacts for a pull request in a GitHub repository.
# Required environment variables:
#   GH_TOKEN          - GitHub token with actions:write permission for cache and artifact deletion. Used by gh CLI
#   CACHE_REF         - Cache reference in the format "refs/pull/<pr_number>/merge"
#   GITHUB_REPOSITORY - Repository name with owner (e.g. "owner/repo")
#   GITHUB_HEAD_REF   - Head branch reference of the pull request

set -euo pipefail

: "${GH_TOKEN:?}" "${CACHE_REF:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_HEAD_REF:?}"

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
ARTIFACT_TEMPLATE="$(cat "$CURDIR"/artifact_template.tpl)"

RUNS_API_URL="/repos/$GITHUB_REPOSITORY/actions/runs"

# List workflow runs scoped to the PR branch instead of paginating all repo artifacts.
# This avoids timeouts in large repositories with many accumulated artifacts.
runIds="$(gh api -X GET "$RUNS_API_URL" -f branch="$GITHUB_HEAD_REF" -f per_page=100 --paginate --jq '.workflow_runs[].id')"

for runId in $runIds; do
  gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$runId/artifacts" --paginate --template "$ARTIFACT_TEMPLATE"
done
echo

echo "Deleting artifacts..."
for runId in $runIds; do
  artifactIds="$(gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$runId/artifacts" --paginate --jq '.artifacts[].id')"
  for artifactId in $artifactIds
  do
    echo "Deleting artifact: $artifactId"
    gh api -X DELETE "/repos/$GITHUB_REPOSITORY/actions/artifacts/$artifactId" || true
  done
done
echo

echo "Fetching list of artifacts after deletion"
for runId in $runIds; do
  gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$runId/artifacts" --paginate --template "$ARTIFACT_TEMPLATE"
done
echo "::endgroup::"
