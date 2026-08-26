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
RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-1}" # between internal retries of a single marker check or marker write

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

# A false "no marker" here would make this run claim a second, unnecessary number instead of reusing an existing one, so a
# single transient failure isn't enough to conclude that - retried once before falling back to "not yet published".
find_run_marker() {
  local output check_attempt
  for check_attempt in 1 2; do
    if output=$(gh api -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${RUN_NS}/" --jq '.[0].ref // empty' 2>&1); then
      echo "$output"
      return 0
    fi
    ((check_attempt < 2)) && sleep "$RETRY_INTERVAL_SECONDS"
  done
  echo "::warning title=Marker check inconclusive::Could not confirm whether refs/${RUN_NS}/* exists after 2 attempts (${output});" \
    "proceeding as if not yet published." >&2
  return 0
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
      "be released; the job holding it may have failed before completing its claim. If no claim is genuinely in progress, the" \
      "lock leaked (e.g. a runner killed without running its cleanup) and blocks every claim in this repository until removed:" \
      "gh api --method DELETE ${REFS_API_URL}/${NUMBER_LOCK_REF}" >&2
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
    # Force base-10: a leading-zero ref name like build-number/08 would otherwise be parsed as an (invalid) octal literal.
    ((10#$n > MAX_CLAIMED)) && MAX_CLAIMED=$((10#$n))
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
      # 10# forces base-10: a leading-zero property value would otherwise be parsed as an (invalid) octal literal.
      MAX_CLAIMED=$((10#$LEGACY_BUILD_NUMBER + 1000)) # buffer against the legacy property still advancing elsewhere during migration
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

if ((${#STALE_REFS[@]} > 0)); then
  for ref in "${STALE_REFS[@]}"; do
    delete_ref "$ref" || echo "::warning title=Stale build number ref not deleted::Failed to delete refs/${ref}; harmless, just" \
      "clutter - a future claim will retry." >&2
  done
fi

# Retried rather than a single attempt: a same-run job waiting on the lock reuses this marker as soon as it appears, so a
# transient failure here - left unretried - would make it claim its own, second number for this run instead of waiting further.
MARKER_WRITTEN=""
for marker_attempt in 1 2 3; do
  create_ref "${RUN_NS}/${CANDIDATE}" >/dev/null && { MARKER_WRITTEN=1; break; }
  ((marker_attempt < 3)) && sleep "$RETRY_INTERVAL_SECONDS"
done
if [[ -z "$MARKER_WRITTEN" ]]; then
  echo "::error title=Build number claim failed::Failed to record refs/${RUN_NS}/${CANDIDATE} after 3 attempts; other jobs/reruns" \
    "of this workflow run waiting on refs/${NUMBER_LOCK_REF} would otherwise time out instead of reusing it." >&2
  exit 1
fi

echo "::endgroup::"
echo "${CANDIDATE}" >"$BUILD_NUMBER_FILE"
