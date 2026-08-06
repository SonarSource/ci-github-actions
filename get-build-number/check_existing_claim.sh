#!/bin/bash
# Check whether this workflow run already claimed a build number (e.g. a rerun, or another job in the same run) and reuse it if so.
# Read-only check against refs/build-runs/<run_id>/*; see get_build_number.sh for the actual claim.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_OUTPUT:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_NUMBER_FILE="${BUILD_NUMBER_FILE:-.build_number.txt}"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
RUNS_NS="build-runs/${GITHUB_RUN_ID}"

echo "::group::Check for an existing build number claim from this workflow run"
echo "::debug::Checking for an existing claim by this workflow run (refs/${RUNS_NS}/*)"
RUN_CLAIMS=$(gh api -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${RUNS_NS}/" --jq '.[].ref')
EXISTING=""
if [[ -n "$RUN_CLAIMS" ]]; then
  while IFS= read -r ref; do
    [[ "$ref" =~ ^refs/${RUNS_NS}/([0-9]+)$ ]] || continue
    n="${BASH_REMATCH[1]}"
    # TODO PREQ-7781: two jobs racing here before either writes a marker can each claim a different number; this just picks the lowest.
    if [[ -z "$EXISTING" ]] || ((n < EXISTING)); then
      EXISTING="$n"
    fi
  done <<<"$RUN_CLAIMS"
fi

if [[ -n "$EXISTING" ]]; then
  echo "::debug::Reusing build number ${EXISTING}, already claimed by this workflow run (refs/${RUNS_NS}/${EXISTING})"
  echo "${EXISTING}" >"$BUILD_NUMBER_FILE"
  echo "skip=true" >>"$GITHUB_OUTPUT"
else
  echo "::debug::No existing claim found for this workflow run"
fi
echo "::endgroup::"
