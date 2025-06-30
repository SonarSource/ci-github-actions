#!/bin/bash
# Get the build number for a GitHub repository and save the incremented value to build_number.txt

set -euo pipefail

: "${GITHUB_REPOSITORY:?}"
GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
CACHE_FILE="build_number.txt"

echo "Fetching build number from repository properties..."
PROPERTIES_API_URL="/repos/${GITHUB_REPOSITORY}/properties/values"
BUILD_NUMBER=$(gh api -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" --jq '.[] | select(.property_name == "build_number") | .value')
echo "Current build number from repo: ${BUILD_NUMBER:=0}"
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Build number '${BUILD_NUMBER}' is not a valid positive integer."
  exit 1
fi

BUILD_NUMBER=$((BUILD_NUMBER + 1))
gh api --method PATCH -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" \
  -f "properties[][property_name]=build_number" \
  -f "properties[][value]=${BUILD_NUMBER}"
echo "Incremented 'build_number' repository property to ${BUILD_NUMBER}"
echo "${BUILD_NUMBER}" > "$CACHE_FILE"
