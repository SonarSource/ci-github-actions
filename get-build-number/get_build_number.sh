#!/bin/bash
# Get the build number for a GitHub repository and save the incremented value to .build_number.txt
# Only runs after acquire_run_lock.sh has confirmed this is the sole claimer for this workflow run.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/refs"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
PROPERTIES_API_URL="repos/${GITHUB_REPOSITORY}/properties/values"
LOCKS_NS="build-locks"
RUNS_NS="build-runs/${GITHUB_RUN_ID}"
# refs/build-locks/<N> is the only source of truth for uniqueness (atomic create, never deleted).
# refs/build-runs/<run_id>/<N> lets other jobs/reruns of this run reuse this number instead of waiting out their lock timeout; other
# waiters may be blocked on it (acquire_run_lock.sh), so it must be recorded, not merely best-effort.
# All ref reads/writes use the ambient GITHUB_TOKEN (contents: write). LEGACY_PROPERTY_TOKEN (Vault) is only used to read the legacy
# build_number property during migration - see README.
MAX_ATTEMPTS="${MAX_ATTEMPTS:-100}" # retries when a concurrent claim beats us to the next number

claim_ref() {
  local ref="$1"
  gh api --method POST -H "$GH_API_VERSION_HEADER" "$REFS_API_URL" -f "ref=refs/${ref}" -f "sha=${GITHUB_SHA}" 2>&1
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
    # TODO PREQ-7781: drop this gap once repo migration to build-locks refs is confirmed complete
    MAX_CLAIMED=$((LEGACY_BUILD_NUMBER + 1000))
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

if ! claim_ref "${RUNS_NS}/${CANDIDATE}" >/dev/null; then
  echo "::error title=Build number run-marker not recorded::Failed to record refs/${RUNS_NS}/${CANDIDATE}; other jobs/reruns of this" \
    "workflow run waiting on refs/build-run-locks/${GITHUB_RUN_ID} would otherwise time out instead of reusing it." >&2
  exit 1
fi
echo "::endgroup::"

echo "${CANDIDATE}" >"$BUILD_NUMBER_FILE"
