#!/bin/bash
# Get the build number for a GitHub repository and save the incremented value to .build_number.txt

set -euo pipefail

: "${GITHUB_REPOSITORY:?}"
GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
PROPERTIES_API_URL="repos/${GITHUB_REPOSITORY}/properties/values"
# The custom-properties API has no conditional/atomic update (no If-Match support), so
# concurrent runs (e.g. GitHub Stacked PRs) can race on the read-increment-write cycle and
# claim the same number. Verify after writing and retry on a detected collision to close
# most of that window; see PREQ-7781.
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"

get_property_value() {
  gh api -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" --jq '.[] | select(.property_name == "build_number") | .value'
}

echo "Fetching build number from repository properties..."

attempt=1
while true; do
  BUILD_NUMBER=$(get_property_value)
  echo "Current build number from repo: ${BUILD_NUMBER:=0}"
  if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "::error title=Invalid build number::Build number '${BUILD_NUMBER}' is not a valid positive integer." >&2
    exit 1
  fi

  NEXT_BUILD_NUMBER=$((BUILD_NUMBER + 1))
  gh api --method PATCH -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" \
    -f "properties[][property_name]=build_number" \
    -f "properties[][value]=${NEXT_BUILD_NUMBER}"

  CONFIRMED_BUILD_NUMBER=$(get_property_value)
  if [[ "$CONFIRMED_BUILD_NUMBER" == "$NEXT_BUILD_NUMBER" ]]; then
    echo "Incremented 'build_number' repository property to ${NEXT_BUILD_NUMBER}"
    echo "${NEXT_BUILD_NUMBER}" > "$BUILD_NUMBER_FILE"
    exit 0
  fi

  if (( attempt >= MAX_ATTEMPTS )); then
    echo "::error title=Build number race::Could not obtain a unique build number after ${MAX_ATTEMPTS} attempts; concurrent runs kept overwriting each other." >&2
    exit 1
  fi

  echo "Concurrent update detected (expected ${NEXT_BUILD_NUMBER}, found ${CONFIRMED_BUILD_NUMBER}); retrying (attempt $((attempt + 1))/${MAX_ATTEMPTS})..."
  sleep "0.$((RANDOM % 900 + 100))"
  attempt=$((attempt + 1))
done
