#!/bin/bash
# Get the build number for a GitHub repository and save it to .build_number.txt, reusing one already claimed by this workflow run.
#
# refs/build-number/<N>: the atomic claim itself and the sole source of truth for uniqueness. Claiming a number and deleting the
# one it superseded both happen while holding build-number-lock below.
# refs/build-runs/<run_id>/<N>: marker recording which number this workflow run claimed. Checked first, and lock-free, so reruns
# and other jobs in the same run reuse it without ever touching build-number-lock.
# refs/build-number-lock: exclusive, transient, repository-wide lock serializing every new claim, not just those within one run.
# Released immediately after use (success or failure) via the trap below, not held for a run's lifetime.
#
# Every ref points at $GITHUB_SHA purely because creation requires some valid target; that target is never read back.
# All ref reads/writes use the ambient GITHUB_TOKEN. LEGACY_PROPERTY_TOKEN (from Vault) is only used to read the legacy
# build_number property during migration - see README.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/refs"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
PROPERTIES_API_URL="repos/${GITHUB_REPOSITORY}/properties/values"
PROPS_JQ='.[] | select(.property_name == "build_number") | .value'
NUMBER_NS="build-number"
RUN_NS="build-runs/${GITHUB_RUN_ID}"
NUMBER_LOCK_REF="build-number-lock/global" # git/refs requires at least 3 slash-separated components; a bare name is rejected
LOCK_POLL_INTERVAL_SECONDS="${LOCK_POLL_INTERVAL_SECONDS:-3}"
LOCK_WAIT_MAX_ATTEMPTS="${LOCK_WAIT_MAX_ATTEMPTS:-40}" # ~2 minutes at the default interval

create_ref() {
  local ref="$1"
  gh api --method POST -H "$GH_API_VERSION_HEADER" "$REFS_API_URL" -f "ref=refs/${ref}" -f "sha=${GITHUB_SHA}" 2>&1
}

delete_ref() {
  local ref="$1"
  gh api --method DELETE -H "$GH_API_VERSION_HEADER" "${REFS_API_URL}/${ref}" >/dev/null 2>&1
}

# Reports a fatal ref-creation failure, calling out the common "caller still has contents: read" cause by name instead of only
# dumping the raw API response, since that response alone reads as a generic permission error, not a fix.
fail_claim() {
  local response="$1"
  if [[ "$response" == *"Resource not accessible by integration"* ]]; then
    echo "::error title=Build number claim failed::${response} This action requires 'contents: write' in the calling workflow's" \
      "permissions (contents: read is no longer sufficient)." >&2
  else
    echo "::error title=Build number claim failed::${response}" >&2
  fi
  exit 1
}

find_run_marker() {
  local output
  # Tolerate a transient/network failure of this specific call: treat it the same as "no marker yet" and retry on the next poll,
  # but log it so a *permanent* failure (e.g. an auth error) is visible instead of only ever surfacing as a wait timeout.
  if ! output=$(gh api -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${RUN_NS}/" --jq '.[0].ref // empty' 2>&1); then
    echo "::debug::Marker check failed, treating as not-yet-published and retrying: ${output}" >&2
    return 0
  fi
  echo "$output"
}

# Exits 0 (and tells the caller to stop) if this run already has a claim; exits 1 on a malformed marker.
try_reuse_existing_claim() {
  local marker existing
  marker=$(find_run_marker)
  [[ -n "$marker" ]] || return 1
  if ! [[ "$marker" =~ ^refs/${RUN_NS}/([0-9]+)$ ]]; then
    echo "::error title=Build number claim failed::Unexpected ref format: ${marker}" >&2
    exit 1
  fi
  existing="${BASH_REMATCH[1]}"
  echo "Reusing build number ${existing}, already claimed by this workflow run (refs/${RUN_NS}/${existing})"
  echo "${existing}" >"$BUILD_NUMBER_FILE"
}

HELD_LOCK=""
release_lock() {
  [[ -n "$HELD_LOCK" ]] || return 0
  delete_ref "$NUMBER_LOCK_REF" || echo "::warning title=Build number lock not released::Failed to delete refs/${NUMBER_LOCK_REF};" \
    "a later claim may have to wait out its timeout before proceeding." >&2
}
trap release_lock EXIT

echo "::group::Get build number"

attempt=1
while true; do
  try_reuse_existing_claim && { echo "::endgroup::" && exit 0; }

  RESPONSE=$(create_ref "$NUMBER_LOCK_REF") && LOCK_STATUS=0 || LOCK_STATUS=$?
  if [[ "$LOCK_STATUS" -eq 0 ]]; then
    HELD_LOCK=1
    break
  fi
  if [[ "$RESPONSE" != *"Reference already exists"* ]]; then
    fail_claim "$RESPONSE"
  fi

  if ((attempt >= LOCK_WAIT_MAX_ATTEMPTS)); then
    echo "::error title=Build number claim timed out::Waited ${LOCK_WAIT_MAX_ATTEMPTS} attempts for refs/${NUMBER_LOCK_REF} to" \
      "be released; the job holding it may have failed before completing its claim." >&2
    exit 1
  fi
  echo "::debug::refs/${NUMBER_LOCK_REF} already held; waiting (attempt $((attempt + 1))/${LOCK_WAIT_MAX_ATTEMPTS})"
  sleep "$LOCK_POLL_INTERVAL_SECONDS"
  attempt=$((attempt + 1))
done

# We now hold the lock, but this run's own marker may have appeared while we were waiting (another job in the same run).
try_reuse_existing_claim && { echo "::endgroup::" && exit 0; }

echo "::debug::Scanning refs/${NUMBER_NS}/* for the highest claimed build number"
NUMBER_REFS=$(gh api --paginate -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${NUMBER_NS}/" --jq '.[].ref')
MAX_CLAIMED=0
STALE_REFS=()
if [[ -n "$NUMBER_REFS" ]]; then
  while IFS= read -r ref; do
    [[ "$ref" =~ ^refs/${NUMBER_NS}/([0-9]+)$ ]] || continue
    n="${BASH_REMATCH[1]}"
    STALE_REFS+=("${NUMBER_NS}/${n}")
    ((n > MAX_CLAIMED)) && MAX_CLAIMED=$n
  done <<<"$NUMBER_REFS"
fi

if [[ "$MAX_CLAIMED" -eq 0 ]]; then
  if [[ -z "${LEGACY_PROPERTY_TOKEN:-}" ]]; then
    echo "::warning title=Legacy build number not checked::No refs/${NUMBER_NS}/* exist yet and no migration token is available;" \
      "starting from 1. If this repository has a legacy build_number property, its numbers will be reused." >&2
  else
    echo "::debug::No refs/${NUMBER_NS}/* found yet; checking the legacy build_number property as a migration seed"
    LEGACY_BUILD_NUMBER=$(GH_TOKEN="${LEGACY_PROPERTY_TOKEN}" gh api -H "$GH_API_VERSION_HEADER" "$PROPERTIES_API_URL" --jq "$PROPS_JQ")
    if [[ -n "$LEGACY_BUILD_NUMBER" ]]; then
      if ! [[ "$LEGACY_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "::error title=Invalid build number::Legacy build_number property '${LEGACY_BUILD_NUMBER}' is not a valid positive" \
          "integer." >&2
        exit 1
      fi
      echo "Seeding from legacy build_number property: ${LEGACY_BUILD_NUMBER}"
      MAX_CLAIMED=$((LEGACY_BUILD_NUMBER + 1000)) # buffer against the legacy property still advancing elsewhere during migration
    fi
  fi
fi
echo "::debug::Highest known build number: ${MAX_CLAIMED}"

CANDIDATE=$((MAX_CLAIMED + 1))
RESPONSE=$(create_ref "${NUMBER_NS}/${CANDIDATE}") && CLAIM_STATUS=0 || CLAIM_STATUS=$?
if [[ "$CLAIM_STATUS" -ne 0 ]]; then
  if [[ "$RESPONSE" == *"Reference already exists"* ]]; then
    echo "::error title=Build number claim failed::refs/${NUMBER_NS}/${CANDIDATE} already exists, which should be impossible" \
      "while holding refs/${NUMBER_LOCK_REF}. Check for another caller writing build-number refs without this lock (e.g. an" \
      "older, un-migrated version of this action) or a manual/external ref creation." >&2
    exit 1
  fi
  fail_claim "$RESPONSE"
fi
echo "Claimed build number ${CANDIDATE} (refs/${NUMBER_NS}/${CANDIDATE})"

for ref in "${STALE_REFS[@]}"; do
  delete_ref "$ref" || echo "::warning title=Stale build number ref not deleted::Failed to delete refs/${ref}; harmless, just" \
    "clutter - a future claim will retry." >&2
done

if ! create_ref "${RUN_NS}/${CANDIDATE}" >/dev/null; then
  echo "::error title=Build number claim failed::Failed to record refs/${RUN_NS}/${CANDIDATE}; other jobs/reruns of this workflow" \
    "run waiting on refs/${NUMBER_LOCK_REF} would otherwise time out instead of reusing it." >&2
  exit 1
fi

echo "::endgroup::"
echo "${CANDIDATE}" >"$BUILD_NUMBER_FILE"
