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

# Entry point. Implemented across later phases (collect → render → upsert).
main() {
  :
}
