#!/usr/bin/env bash
# report-ci-insights library functions. Tested directly via shellspec.

# Recover the last sentinel-wrapped metrics JSON from a job log's text. Empty if absent.
# grep -o is line-oriented, so a decoy mention of the BEGIN sentinel on its own
# line (without a matching END sentinel) cannot match and is ignored.
extract_metrics_json() {
  local text=$1
  printf '%s' "$text" \
    | grep -o '===CI_METRICS_JSON_BEGIN===.*===CI_METRICS_JSON_END===' \
    | tail -1 \
    | sed -e 's/.*===CI_METRICS_JSON_BEGIN===//' -e 's/===CI_METRICS_JSON_END===.*//'
}

# List the run's jobs and emit "<name>\t<json>" for each completed sibling whose log
# carries a metrics block. Skips, with distinct reasons:
#   - non-completed jobs (still running / queued have no final metrics);
#   - the report job itself: github.job is the YAML job id (SELF_JOB) while the jobs
#     API reports the DISPLAY name, which usually matches but for matrix jobs becomes
#     "id (val)". We skip on exact match OR "$SELF_JOB " prefix to cover both, AND
#     defensively `continue` when the log download fails — the running report job's own
#     log 404s mid-run, so a failed download must never abort the whole collection;
#   - jobs whose log has no sentinel-wrapped metrics block (nothing to report).
# A failure to list jobs at all is treated as "nothing to collect" (return 0).
collect_job_metrics() {
  local jobs id name status log metrics
  jobs=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
           -q '.jobs[] | "\(.id)\t\(.name)\t\(.status)"') || return 0
  while IFS=$'\t' read -r id name status; do
    [[ -z "$id" ]] && continue
    [[ "$status" == "completed" ]] || continue
    [[ "$name" == "$SELF_JOB" || "$name" == "$SELF_JOB "* ]] && continue
    log=$(gh api "repos/$REPO/actions/jobs/$id/logs" 2>/dev/null) || continue
    metrics=$(extract_metrics_json "$log")
    [[ -n "$metrics" ]] || continue
    printf '%s\t%s\n' "$name" "$metrics"
  done <<< "$jobs"
}

# Entry point. Implemented across later phases (collect → render → upsert).
main() {
  :
}
