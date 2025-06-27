#!/bin/bash
set -e

# Required environment variables:
#   GH_TOKEN         - GitHub token with actions:write permission for cache and artifact deletion
#   CACHE_REF       - Cache reference in the format "refs/pull/<pr_number>/merge"
#   GITHUB_REPOSITORY - Repository name with owner (e.g. "owner/repo")
#   GITHUB_HEAD_REF  - Head branch reference of the pull request

# Check required environment variables
: "${GH_TOKEN:?Required environment variable not set}"
: "${CACHE_REF:?Required environment variable not set}"
: "${GITHUB_REPOSITORY:?Required environment variable not set}"
: "${GITHUB_HEAD_REF:?Required environment variable not set}"

echo "Fetching list of cache keys on $GITHUB_REPOSITORY for $CACHE_REF"
TEMPLATE='{{tablerow "ID" "KEY" "SIZE (BYTES)"}}
  {{- range . -}}
    {{- tablerow .id .key .sizeInBytes -}}
  {{- end -}}
  {{- tablerender -}}'
gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --json id,key,sizeInBytes --template "$TEMPLATE"
echo

cacheKeysForPR="$(gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --json id --jq '.[].id')"
echo "Deleting caches..."
for cacheKey in $cacheKeysForPR
do
  echo "Deleting cache key: $cacheKey"
  gh cache delete --repo "$GITHUB_REPOSITORY" "$cacheKey"
done
echo

echo "Fetching list of cache keys after deletion"
gh cache list --repo "$GITHUB_REPOSITORY" --ref "$CACHE_REF" --json id,key,sizeInBytes --template "$TEMPLATE"

echo "Fetching list of artifacts"
TEMPLATE='{{tablerow "NAME" "ID" "SIZE (BYTES)" "BRANCH" "HEAD_SHA" "RUN_ID"}}
  {{- range .artifacts -}}
    {{- if eq .workflow_run.head_branch "'"$GITHUB_HEAD_REF"'" -}}
      {{- tablerow .name .id .size_in_bytes .workflow_run.head_branch .workflow_run.head_sha .workflow_run.id -}}
    {{- end -}}
  {{- end -}}
  {{- tablerender -}}'
gh api -X GET "/repos/$GITHUB_REPOSITORY/actions/artifacts" --template "$TEMPLATE"
echo

artifactIds="$(gh api -X GET "/repos/$GITHUB_REPOSITORY/actions/artifacts" \
  --jq '.artifacts[] | select(.workflow_run.head_branch == "'"$GITHUB_HEAD_REF"'") | .id')"
echo "Deleting artifacts..."
for artifactId in $artifactIds
do
  echo "Deleting artifact: $artifactId"
  gh api -X DELETE "/repos/$GITHUB_REPOSITORY/actions/artifacts/$artifactId" || true
done
echo

echo "Fetching list of artifacts after deletion"
gh api -X GET "/repos/$GITHUB_REPOSITORY/actions/artifacts" --template "$TEMPLATE"
