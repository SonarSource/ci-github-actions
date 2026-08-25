#!/bin/bash
# Delete refs/build-runs/<run_id>/<number> markers (written by get-build-number) whose workflow run no longer exists on GitHub.
# That is the only condition under which deleting one is safe: re-running a workflow needs its run record to still exist, so a
# run missing from the Actions API can never be re-run again - not merely "probably won't be". An old-but-still-existing run,
# or one still in progress, is left alone: age alone says nothing about whether someone will click "Re-run" tomorrow.
#
# Bounded rather than exhaustive, so this stays cheap whether invoked as a build-workflow step or a separately scheduled one
# (see README): the expensive part - one Actions API call per distinct run_id - is capped at PRUNE_MAX_CHECKS per invocation,
# oldest run_id first (run_ids only increase over time, so the oldest markers are the likeliest to already be gone). A large
# backlog is worked off gradually across invocations rather than in a single pass.
#
# refs/build-number/<number> is intentionally not handled here - see get_build_number.sh for why that namespace is never deleted.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}"

GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
MATCHING_REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/matching-refs"
REFS_API_URL="repos/${GITHUB_REPOSITORY}/git/refs"
RUNS_API_URL="repos/${GITHUB_REPOSITORY}/actions/runs"
RUN_NS="build-runs"
PRUNE_MAX_CHECKS="${PRUNE_MAX_CHECKS:-20}"

# Exit 0 = run still exists (keep its markers); 1 = confirmed gone via a 404 (safe to delete); 2 = inconclusive (any other
# failure, e.g. a transient network error or rate limit) - treated the same as "still exists" so a delete is never a guess.
check_run_status() {
  local run_id="$1" output
  output=$(gh api -H "$GH_API_VERSION_HEADER" "${RUNS_API_URL}/${run_id}" 2>&1) && return 0
  [[ "$output" == *"(HTTP 404)"* ]] && return 1
  echo "::warning title=Run status check inconclusive::Could not confirm whether run ${run_id} still exists (${output}); leaving" \
    "its markers alone." >&2
  return 2
}

echo "::group::Prune obsolete build-runs markers"
if ! MARKERS=$(gh api --paginate -H "$GH_API_VERSION_HEADER" "${MATCHING_REFS_API_URL}/${RUN_NS}/" --jq '.[].ref' 2>&1); then
  echo "::warning title=Marker pruning skipped::Could not list refs/${RUN_NS}/* (${MARKERS}); nothing pruned this invocation." >&2
  echo "::endgroup::"
  exit 0
fi

deleted=0
kept=0
checked_run_ids=0
skipped=0
declare -A RUN_STATUS_CACHE
if [[ -n "$MARKERS" ]]; then
  SORTED_MARKERS=$(grep -E "^refs/${RUN_NS}/[0-9]+/[0-9]+\$" <<<"$MARKERS" | sort -t/ -k3 -n) || true
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ "$ref" =~ ^refs/${RUN_NS}/([0-9]+)/[0-9]+$ ]] || continue
    run_id="${BASH_REMATCH[1]}"

    if [[ -z "${RUN_STATUS_CACHE[$run_id]:-}" ]]; then
      if ((checked_run_ids >= PRUNE_MAX_CHECKS)); then
        skipped=$((skipped + 1))
        continue
      fi
      check_run_status "$run_id" && run_status=0 || run_status=$?
      [[ "$run_status" -eq 1 ]] && RUN_STATUS_CACHE[$run_id]="gone" || RUN_STATUS_CACHE[$run_id]="exists"
      checked_run_ids=$((checked_run_ids + 1))
    fi

    if [[ "${RUN_STATUS_CACHE[$run_id]}" != "gone" ]]; then
      kept=$((kept + 1))
      continue
    fi

    ref_path="${ref#refs/}"
    if gh api --method DELETE -H "$GH_API_VERSION_HEADER" "${REFS_API_URL}/${ref_path}" >/dev/null 2>&1; then
      echo "::debug::Deleted ${ref} (run ${run_id} no longer exists on GitHub, so it can never be re-run)"
      deleted=$((deleted + 1))
    else
      echo "::warning title=Marker not deleted::Failed to delete ${ref}; harmless, just clutter." >&2
    fi
  done <<<"$SORTED_MARKERS"
fi

echo "Pruned ${deleted} obsolete build-runs marker(s); kept ${kept} whose run still exists on GitHub; skipped ${skipped} not" \
  "checked this invocation (checked ${checked_run_ids} distinct run(s), capped at ${PRUNE_MAX_CHECKS})."
if ((skipped)); then
  echo "::notice title=Marker pruning incomplete::${skipped} marker(s) exceeded the ${PRUNE_MAX_CHECKS}-per-invocation cap; they" \
    "will be picked up on a future invocation, or raise PRUNE_MAX_CHECKS." >&2
fi
echo "::endgroup::"
