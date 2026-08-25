#!/bin/bash
# Try to become the exclusive claimer of a build number for this workflow run, so at most one number is ever claimed per run_id.
# Winner: exits 0 and lets the caller proceed to get_build_number.sh. Loser (lock already held, by a concurrent job or a rerun): waits
# for the winner's marker and reuses that number instead of claiming an independent one.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_OUTPUT:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/refs"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
RUN_LOCK_REF="build-run-locks/${GITHUB_RUN_ID}"
RUNS_NS="build-runs/${GITHUB_RUN_ID}"
LOCK_POLL_INTERVAL_SECONDS="${LOCK_POLL_INTERVAL_SECONDS:-3}"
LOCK_WAIT_MAX_ATTEMPTS="${LOCK_WAIT_MAX_ATTEMPTS:-40}" # ~2 minutes at the default interval

echo "::group::Acquire build-number lock for this workflow run"
RESPONSE=$(gh api --method POST -H "$GH_API_VERSION_HEADER" "$REFS_API_URL" -f "ref=refs/${RUN_LOCK_REF}" -f "sha=${GITHUB_SHA}" 2>&1) &&
  CLAIM_STATUS=0 || CLAIM_STATUS=$?

if [[ "$CLAIM_STATUS" -eq 0 ]]; then
  echo "::debug::Acquired refs/${RUN_LOCK_REF}; proceeding to claim a build number"
  echo "::endgroup::"
  exit 0
fi

if [[ "$RESPONSE" != *"Reference already exists"* ]]; then
  echo "::error title=Build number lock failed::${RESPONSE}" >&2
  exit 1
fi

echo "::debug::refs/${RUN_LOCK_REF} already held; waiting for its build number marker"
attempt=1
while true; do
  # Tolerate a transient/network failure of this specific call: treat it the same as "no marker yet" and retry on the next poll,
  # rather than letting one flaky request abort the whole wait.
  MARKER=$(gh api -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${RUNS_NS}/" --jq '.[0].ref // empty') || MARKER=""
  if [[ -n "$MARKER" ]]; then
    if ! [[ "$MARKER" =~ ^refs/${RUNS_NS}/([0-9]+)$ ]]; then
      echo "::error title=Build number lock failed::Unexpected ref format: ${MARKER}" >&2
      exit 1
    fi
    EXISTING="${BASH_REMATCH[1]}"
    echo "Reusing build number ${EXISTING}, claimed by another job in this workflow run (refs/${RUNS_NS}/${EXISTING})"
    echo "${EXISTING}" >"$BUILD_NUMBER_FILE"
    echo "skip=true" >>"$GITHUB_OUTPUT"
    echo "::endgroup::"
    exit 0
  fi

  if ((attempt >= LOCK_WAIT_MAX_ATTEMPTS)); then
    echo "::error title=Build number lock timed out::Waited ${LOCK_WAIT_MAX_ATTEMPTS} attempts for refs/${RUNS_NS}/* to appear; the job" \
      "holding refs/${RUN_LOCK_REF} may have failed before publishing its claim." >&2
    exit 1
  fi

  sleep "$LOCK_POLL_INTERVAL_SECONDS"
  attempt=$((attempt + 1))
done
