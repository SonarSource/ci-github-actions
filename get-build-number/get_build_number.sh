#!/bin/bash
# Get the build number for a GitHub repository and save the incremented value to .build_number.txt
# See check_existing_claim.sh for the read-only check for an existing claim by this workflow run.
# refs/build-locks/<N> is the only source of truth for uniqueness (atomic create).
# refs/build-runs/<run_id>/<N> is a best-effort marker so a rerun can reuse its number; it is not authoritative.
# All ref reads/writes use the ambient GITHUB_TOKEN.
# LEGACY_PROPERTY_TOKEN (from Vault) is only used to read the legacy build_number property during migration - see README.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/refs"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
PROPERTIES_API_URL="repos/${GITHUB_REPOSITORY}/properties/values"
LOCKS_NS="build-locks"
RUNS_NS="build-runs/${GITHUB_RUN_ID}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-100}" # retries when a concurrent claim beats us to the next number

claim_ref() {
  gh api --method POST -H "$GH_API_VERSION_HEADER" "$REFS_API_URL" -f "ref=refs/$1" -f "sha=${GITHUB_SHA}" 2>&1
}

echo "::group::Claim build number"
echo "::debug::Scanning refs/${LOCKS_NS}/* for the highest claimed build number"
LOCK_REFS=$(gh api --paginate -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${LOCKS_NS}/" --jq '.[].ref')
MAX_CLAIMED=0
if [[ -n "$LOCK_REFS" ]]; then
  while IFS= read -r ref; do
    [[ "$ref" =~ ^refs/${LOCKS_NS}/([0-9]+)$ ]] || continue
    n="${BASH_REMATCH[1]}"
    ((n > MAX_CLAIMED)) && MAX_CLAIMED=$n
  done <<<"$LOCK_REFS"
fi

if [[ "$MAX_CLAIMED" -eq 0 ]]; then
  echo "::debug::No refs/${LOCKS_NS}/* found yet; checking the legacy build_number property as a migration seed"
  LEGACY_BUILD_NUMBER=$(GH_TOKEN="${LEGACY_PROPERTY_TOKEN:-}" gh api -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" \
    --jq '.[] | select(.property_name == "build_number") | .value')
  if [[ -n "$LEGACY_BUILD_NUMBER" ]]; then
    if ! [[ "$LEGACY_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "::error title=Invalid build number::Legacy build_number property '${LEGACY_BUILD_NUMBER}' is not a valid positive integer." >&2
      exit 1
    fi
    echo "Seeding from legacy build_number property: ${LEGACY_BUILD_NUMBER}"
    MAX_CLAIMED=$((LEGACY_BUILD_NUMBER + 1000)) # Add a buffer to avoid collisions with legacy numbers
  fi
fi
echo "::debug::Highest known build number: ${MAX_CLAIMED}"

attempt=1
CANDIDATE=$((MAX_CLAIMED + 1))
while true; do
  RESPONSE=$(claim_ref "${LOCKS_NS}/${CANDIDATE}") && CLAIM_STATUS=0 || CLAIM_STATUS=$?

  if [[ "$CLAIM_STATUS" -eq 0 ]]; then
    echo "Claimed build number ${CANDIDATE} (refs/${LOCKS_NS}/${CANDIDATE})"
    break
  fi

  if [[ "$RESPONSE" != *"Reference already exists"* ]]; then
    echo "::error title=Build number claim failed::${RESPONSE}" >&2
    exit 1
  fi

  if ((attempt >= MAX_ATTEMPTS)); then
    echo "::error title=Build number race::Could not claim a build number after ${MAX_ATTEMPTS} attempts (concurrent claims)." >&2
    exit 1
  fi

  echo "::debug::Build number ${CANDIDATE} already claimed; trying $((CANDIDATE + 1)) (attempt $((attempt + 1))/${MAX_ATTEMPTS})"
  CANDIDATE=$((CANDIDATE + 1))
  attempt=$((attempt + 1))
done

claim_ref "${RUNS_NS}/${CANDIDATE}" >/dev/null ||
  echo "::warning title=Build number run-marker not recorded::Failed to record refs/${RUNS_NS}/${CANDIDATE}; a rerun of this workflow" \
    "run may claim a new build number instead of reusing this one."
echo "::endgroup::"

echo "${CANDIDATE}" >"$BUILD_NUMBER_FILE"
