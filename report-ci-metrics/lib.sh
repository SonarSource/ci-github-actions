#!/usr/bin/env bash
# report-ci-metrics library functions. Tested directly via shellspec.

# Recover the last sentinel-wrapped metrics JSON from a job log's text. Empty if absent.
extract_metrics_json() {
  local text=$1
  printf '%s' "$text" \
    | grep -o '===CI_METRICS_JSON_BEGIN===.*===CI_METRICS_JSON_END===' \
    | tail -1 \
    | sed -e 's/.*===CI_METRICS_JSON_BEGIN===//' -e 's/===CI_METRICS_JSON_END===.*//'
}

# List a run's jobs and emit "<name>\t<json>" for each completed sibling whose log
# carries a metrics block. Skips: non-completed jobs, the report job itself (exact or
# matrix "id (val)" prefix match on SELF_JOB), log-download failures, and jobs with no
# metrics block. Record format relies on job names having no tab/newline.
# $1: run id to collect (defaults to the current $RUN_ID). The arg form is used to
# collect a baseline run for trend comparison.
collect_job_metrics() {
  local run_id=${1:-$RUN_ID}
  local jobs id name status log metrics
  jobs=$(gh api "repos/$REPO/actions/runs/$run_id/jobs" --paginate -q '.jobs[] | "\(.id)\t\(.name)\t\(.status)"') || return 0
  while IFS=$'\t' read -r id name status; do
    [[ -z "$id" ]] && continue
    [[ "$status" == "completed" ]] || continue
    [[ "$name" == "$SELF_JOB" || "$name" == "$SELF_JOB "* ]] && continue
    log=$(gh api "repos/$REPO/actions/jobs/$id/logs" 2>/dev/null) || continue
    metrics=$(extract_metrics_json "$log")
    [[ -n "$metrics" ]] || continue
    # Drop malformed/truncated JSON so it never reaches the renderers.
    jq -e . >/dev/null 2>&1 <<< "$metrics" || continue
    printf '%s\t%s\n' "$name" "$metrics"
  done <<< "$jobs"
}

# Sanitize an author-influenced value for safe inclusion in a markdown table cell:
# escape pipes (column injection), collapse CR/LF (row/line injection), and neutralize
# angle brackets (HTML/details injection) since the comment is posted with write scope.
_rci_md_cell() {
  local s=$1
  s=${s//|/\\|}
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  # Escape the & in the replacement: bash 4.3+ treats a bare & as the matched text.
  s=${s//</\&lt;}
  s=${s//>/\&gt;}
  printf '%s' "$s"
}

# Bytes → human-readable, matching the producer hook's fmt_bytes (2dp, IEC units).
# A blank/non-numeric arg renders as "n/a" so callers can pass jq nulls directly.
_rci_fmt_bytes() {
  local b=${1:-}
  [[ "$b" =~ ^[0-9]+$ ]] || { printf 'n/a'; return; }
  if   (( b >= 1073741824 )); then awk -v b="$b" 'BEGIN{printf "%.2f GiB", b/1073741824}'
  elif (( b >= 1048576   )); then awk -v b="$b" 'BEGIN{printf "%.2f MiB", b/1048576}'
  elif (( b >= 1024      )); then awk -v b="$b" 'BEGIN{printf "%.2f KiB", b/1024}'
  else                            printf '%s B' "$b"
  fi
}

# CPU-avg display cell for one job's JSON, mirroring the hook's step-summary logic.
# Denominator preference: limit_cores -> request_cores ("requested", ARC burstable) ->
# online_count ("available", WarpBuild VM) -> bare cores -> "n/a".
_rci_cpu_cell() {
  local json=$1
  jq -r '.cgroup.cpu as $c | .duration_seconds as $d | if ($c.usage_seconds != null and $d != null and $d > 0) then (($c.usage_seconds / $d) * 100 | round / 100) as $cores | if ($c.limit_cores != null and $c.avg_utilization != null) then "\($cores) / \(($c.limit_cores*100|round)/100) cores (\(($c.avg_utilization*100)|round)%)" elif ($c.request_cores != null and $c.request_cores > 0) then "\($cores) / \(($c.request_cores*100|round)/100) cores requested (\((($cores/$c.request_cores)*100)|round)%)" elif ($c.online_count != null and $c.online_count > 0) then "\($cores) / \($c.online_count) cores available (\((($cores/$c.online_count)*100)|round)%)" else "\($cores) cores" end else "n/a" end' <<< "$json"
}

# Sum a numeric jq path across all record JSONs; nulls count as 0. Echoes an integer-ish sum.
_rci_sum() {
  local records=$1 path=$2 total=0 name json
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local v
    v=$(jq -r "($path) // 0" <<< "$json" 2>/dev/null)
    total=$(awk -v a="$total" -v b="$v" 'BEGIN{printf "%.0f", a+b}')
  done <<< "$records"
  printf '%s' "$total"
}

# --- Trend metrics ---------------------------------------------------------------------
# All three operate on the "<name>\t<json>" record stream so they're testable without gh.

# _rci_cache_hit_rate <records> — integer hit-rate percent across every job's cache entries
# (.cache[].cache_hit). Empty when there are no cache entries at all (nothing to rate).
_rci_cache_hit_rate() {
  local records=$1 total=0 hits=0 name json
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local n h
    n=$(jq -r '(.cache // []) | length' <<< "$json" 2>/dev/null); [[ "$n" =~ ^[0-9]+$ ]] || n=0
    h=$(jq -r '[.cache[]? | select(.cache_hit == true)] | length' <<< "$json" 2>/dev/null); [[ "$h" =~ ^[0-9]+$ ]] || h=0
    total=$((total + n)); hits=$((hits + h))
  done <<< "$records"
  (( total == 0 )) && return 0
  awk -v h="$hits" -v t="$total" 'BEGIN{printf "%.0f", (h/t)*100}'
}

# _rci_worst_mem_util <records> — "<util_ratio>\t<job_name>" for the job with the highest
# memory.peak_utilization (the OOM-risk job). Empty when no job reports peak_utilization.
# Mirrors the worst-peak scan in render_headline but keys on utilisation, not raw bytes.
_rci_worst_mem_util() {
  local records=$1 name json worst="-1" worst_name=""
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local u
    u=$(jq -r '.cgroup.memory.peak_utilization // empty' <<< "$json" 2>/dev/null)
    [[ -n "$u" ]] || continue
    if awk -v a="$u" -v b="$worst" 'BEGIN{exit !(a+0>b+0)}'; then worst=$u; worst_name=$name; fi
  done <<< "$records"
  [[ -n "$worst_name" ]] || return 0
  printf '%s\t%s' "$worst" "$worst_name"
}

# _rci_fmt_delta <current> <baseline> [unit] — neutral arrow + signed delta vs a baseline.
# "→ ±0<unit>" within epsilon, "↑/↓ +N<unit>" otherwise, "n/a" when baseline is empty.
# Direction is presented without good/bad coloring; the reader judges significance.
_rci_fmt_delta() {
  local cur=$1 base=$2 unit=${3:-}
  [[ -n "$base" ]] || { printf 'n/a'; return; }
  awk -v c="$cur" -v b="$base" -v u="$unit" 'BEGIN{
    d = c - b
    a = (d < 0) ? -d : d
    if (a < 0.5) { printf "→ ±0%s", u }
    else if (d > 0) { printf "↑ +%.0f%s", d, u }
    else { printf "↓ %.0f%s", d, u }
  }'
}

# render_headline <records> — a totals line, then a flags line if any job OOM'd/throttled.
render_headline() {
  local records=$1
  local njobs cpu_total rx tx restored saved
  local worst_name="" worst_peak=-1
  local oom_jobs="" oom_count=0 thr_jobs="" thr_count=0
  local name json

  njobs=0
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    njobs=$((njobs + 1))
    local peak okill thr
    peak=$(jq -r '.cgroup.memory.peak_bytes // -1' <<< "$json" 2>/dev/null)
    if [[ "$peak" =~ ^[0-9]+$ ]] && (( peak > worst_peak )); then
      worst_peak=$peak; worst_name=$name
    fi
    okill=$(jq -r '.cgroup.memory.oom_kill // 0' <<< "$json" 2>/dev/null)
    if [[ "$okill" =~ ^[0-9]+$ ]] && (( okill > 0 )); then
      oom_count=$((oom_count + 1))
      oom_jobs="${oom_jobs:+$oom_jobs, }$name"
    fi
    thr=$(jq -r '.cgroup.cpu.throttled_seconds // 0' <<< "$json" 2>/dev/null)
    if awk -v t="$thr" 'BEGIN{exit !(t+0>0)}'; then
      thr_count=$((thr_count + 1))
      thr_jobs="${thr_jobs:+$thr_jobs, }$name"
    fi
  done <<< "$records"

  cpu_total=$(_rci_sum "$records" '.cgroup.cpu.usage_seconds')
  cpu_total=$(awk -v u="$cpu_total" 'BEGIN{printf "%.1f", u}')
  rx=$(_rci_sum "$records" '.net.rx_bytes')
  tx=$(_rci_sum "$records" '.net.tx_bytes')
  restored=$(_rci_sum "$records" '([.cache[]?.size_bytes_restored // 0] | add) // 0')
  saved=$(_rci_sum "$records" '([.cache[]? | select(.saved == true) | .size_bytes_at_end // 0] | add) // 0')

  local job_word="jobs"; [[ "$njobs" -eq 1 ]] && job_word="job"
  local line="**${njobs} ${job_word}** · CPU ${cpu_total} CPU-s"
  if [[ -n "$worst_name" ]]; then
    line="${line} · peak mem $(_rci_fmt_bytes "$worst_peak") (${worst_name})"
  fi
  line="${line} · net $(_rci_fmt_bytes "$rx") ↓ / $(_rci_fmt_bytes "$tx") ↑"
  local cache_seg=""
  [[ "$restored" -gt 0 ]] && cache_seg="cache $(_rci_fmt_bytes "$restored") restored"
  if [[ "$saved" -gt 0 ]]; then
    if [[ -n "$cache_seg" ]]; then cache_seg="${cache_seg} / $(_rci_fmt_bytes "$saved") saved"
    else cache_seg="cache $(_rci_fmt_bytes "$saved") saved"; fi
  fi
  [[ -n "$cache_seg" ]] && line="${line} · ${cache_seg}"
  printf '%s\n' "$line"

  # Flags line only when something actually went wrong.
  if (( oom_count > 0 || thr_count > 0 )); then
    local flags=""
    if (( oom_count > 0 )); then
      local w="jobs"; [[ "$oom_count" -eq 1 ]] && w="job"
      flags="${oom_count} ${w} OOM-killed (${oom_jobs})"
    fi
    if (( thr_count > 0 )); then
      local w="jobs"; [[ "$thr_count" -eq 1 ]] && w="job"
      local seg="${thr_count} ${w} CPU-throttled (${thr_jobs})"
      flags="${flags:+$flags · }${seg}"
    fi
    printf '> ⚠️ %s\n' "$flags"
  fi
}

# render_trend <records> <baseline_records> — one "Trend vs master:" line comparing the two
# PR-attributable signals against a baseline run: cache hit-rate and worst-job peak memory
# utilisation. Emits "no baseline yet" when baseline_records is empty (first run / retention
# gap). Metrics with no current data are omitted; the line is skipped entirely if neither
# metric is present. Percentages: cache rate is already 0-100; mem util is a 0-1 ratio → ×100.
render_trend() {
  local records=$1 baseline=$2
  if [[ -z "$baseline" ]]; then
    printf 'Trend vs master: no baseline yet\n'
    return 0
  fi

  local segs=""

  local cur_hr base_hr
  cur_hr=$(_rci_cache_hit_rate "$records")
  base_hr=$(_rci_cache_hit_rate "$baseline")
  if [[ -n "$cur_hr" ]]; then
    segs="${segs:+$segs · }cache hit ${cur_hr}% ($(_rci_fmt_delta "$cur_hr" "$base_hr" pp))"
  fi

  local cur_mem base_mem cur_pct base_pct mem_job
  cur_mem=$(_rci_worst_mem_util "$records")
  base_mem=$(_rci_worst_mem_util "$baseline")
  if [[ -n "$cur_mem" ]]; then
    mem_job=${cur_mem#*$'\t'}
    cur_pct=$(awk -v u="${cur_mem%%$'\t'*}" 'BEGIN{printf "%.0f", u*100}')
    base_pct=""
    [[ -n "$base_mem" ]] && base_pct=$(awk -v u="${base_mem%%$'\t'*}" 'BEGIN{printf "%.0f", u*100}')
    segs="${segs:+$segs · }peak mem $(_rci_md_cell "$mem_job") ${cur_pct}% ($(_rci_fmt_delta "$cur_pct" "$base_pct" pp))"
  fi

  [[ -n "$segs" ]] && printf 'Trend vs master: %s\n' "$segs"
  return 0
}

# render_table <records> — foldable per-job table. Columns with no data in any job are
# dropped: pre-scan to pick the surviving columns, then render header + one row per job.
render_table() {
  local records=$1
  local njobs=0 name json
  local has_cpu=0 has_mem=0 has_disk=0 has_net=0 has_flags=0

  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    njobs=$((njobs + 1))
    jq -e '.cgroup.cpu.usage_seconds != null and .duration_seconds != null' <<< "$json" >/dev/null 2>&1 && has_cpu=1
    jq -e '.cgroup.memory.peak_bytes != null' <<< "$json" >/dev/null 2>&1 && has_mem=1
    jq -e '.disk.used_bytes != null and .disk.total_bytes != null' <<< "$json" >/dev/null 2>&1 && has_disk=1
    jq -e '.net.rx_bytes != null or .net.tx_bytes != null' <<< "$json" >/dev/null 2>&1 && has_net=1
    jq -e '(.cgroup.memory.oom_kill // 0) > 0 or (.cgroup.cpu.throttled_seconds // 0) > 0' <<< "$json" >/dev/null 2>&1 && has_flags=1
  done <<< "$records"

  # Build the ordered column list from the surviving sections. "Job" is always present.
  local cols=("Job")
  (( has_cpu ))   && cols+=("CPU avg")
  (( has_mem ))   && cols+=("Mem peak")
  (( has_disk ))  && cols+=("Disk")
  (( has_net ))   && cols+=("Net ↓/↑")
  (( has_flags )) && cols+=("Flags")

  local job_word="jobs"; [[ "$njobs" -eq 1 ]] && job_word="job"
  printf '<details><summary>Per-job breakdown (%d %s)</summary>\n\n' "$njobs" "$job_word"

  # Header + separator.
  local header="|" sep="|" c
  for c in "${cols[@]}"; do header="${header} ${c} |"; sep="${sep}---|"; done
  printf '%s\n%s\n' "$header" "$sep"

  # One row per job, emitting only the surviving columns.
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    name=$(_rci_md_cell "$name")
    local row="| ${name} |"
    if (( has_cpu )); then row="${row} $(_rci_cpu_cell "$json") |"; fi
    if (( has_mem )); then
      local pk; pk=$(jq -r '.cgroup.memory.peak_bytes // empty' <<< "$json")
      row="${row} $(_rci_fmt_bytes "$pk") |"
    fi
    if (( has_disk )); then
      local du dt cell
      du=$(jq -r '.disk.used_bytes // empty' <<< "$json")
      dt=$(jq -r '.disk.total_bytes // empty' <<< "$json")
      if [[ "$du" =~ ^[0-9]+$ && "$dt" =~ ^[0-9]+$ ]]; then
        cell="$(_rci_fmt_bytes "$du") / $(_rci_fmt_bytes "$dt")"
      else cell="n/a"; fi
      row="${row} ${cell} |"
    fi
    if (( has_net )); then
      local rxb txb
      rxb=$(jq -r '.net.rx_bytes // empty' <<< "$json")
      txb=$(jq -r '.net.tx_bytes // empty' <<< "$json")
      row="${row} $(_rci_fmt_bytes "$rxb") ↓ / $(_rci_fmt_bytes "$txb") ↑ |"
    fi
    if (( has_flags )); then
      local f="" ok th
      ok=$(jq -r '.cgroup.memory.oom_kill // 0' <<< "$json")
      th=$(jq -r '.cgroup.cpu.throttled_seconds // 0' <<< "$json")
      [[ "$ok" =~ ^[0-9]+$ ]] && (( ok > 0 )) && f="🔴 OOM"
      if awk -v t="$th" 'BEGIN{exit !(t+0>0)}'; then f="${f:+$f }🟡 throttled"; fi
      row="${row} ${f} |"
    fi
    printf '%s\n' "$row"
  done <<< "$records"

  printf '\n</details>\n'
}

# render_cache_fold <records> — foldable cache table; empty string unless a job has cache.
render_cache_fold() {
  local records=$1
  local count=0 name json rows=""

  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local n
    n=$(jq -r '(.cache // []) | length' <<< "$json" 2>/dev/null)
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    (( n == 0 )) && continue
    count=$((count + n))
    local i
    for (( i = 0; i < n; i++ )); do
      local key hit backend restored_b saved_flag end_b
      key=$(jq -r ".cache[$i].key // \"\"" <<< "$json")
      hit=$(jq -r ".cache[$i].cache_hit // false | if . then \"yes\" else \"no\" end" <<< "$json")
      backend=$(jq -r ".cache[$i].backend // \"\"" <<< "$json")
      restored_b=$(jq -r ".cache[$i].size_bytes_restored // empty" <<< "$json")
      saved_flag=$(jq -r ".cache[$i].saved // false | if . then \"yes\" else \"no\" end" <<< "$json")
      end_b=$(jq -r ".cache[$i].size_bytes_at_end // empty" <<< "$json")
      key=$(_rci_md_cell "$key")
      backend=$(_rci_md_cell "$backend")
      rows="${rows}| ${key} | ${hit} | ${backend} | $(_rci_fmt_bytes "$restored_b") | ${saved_flag} | $(_rci_fmt_bytes "$end_b") |"$'\n'
    done
  done <<< "$records"

  (( count == 0 )) && return 0

  local word="entries"; [[ "$count" -eq 1 ]] && word="entry"
  printf '<details><summary>Cache (%d %s)</summary>\n\n' "$count" "$word"
  printf '| Key | Hit | Backend | Size Restored | Saved | Size Saved |\n'
  printf '|---|---|---|---|---|---|\n'
  printf '%s' "$rows"
  printf '\n</details>\n'
}

# find_baseline_run — echo the run id of the master run to compare against, or
# empty when none exists (first run / log-retention gap). Resolves this run's workflow id from
# the run object (no fragile workflow-name matching), then lists that workflow's completed runs
# on the default branch. PR context → newest such run; default-branch push → newest run that is
# not the current one (the previous master). Fail-open: any gh error echoes empty.
find_baseline_run() {
  local wf_id
  wf_id=$(gh api "repos/$REPO/actions/runs/$RUN_ID" -q '.workflow_id' 2>/dev/null) || return 0
  [[ -n "$wf_id" ]] || return 0
  local ids
  ids=$(gh api "repos/$REPO/actions/workflows/$wf_id/runs?branch=${DEFAULT_BRANCH}&status=completed&per_page=20" \
        -q '.workflow_runs[].id' 2>/dev/null) || return 0
  local id
  while read -r id; do
    [[ -n "$id" ]] || continue
    # On a default-branch push the current run is itself in this list — skip it so we compare
    # against the *previous* master. In PR context the current run is on a PR ref, not here.
    [[ "$id" == "$RUN_ID" ]] && continue
    printf '%s' "$id"
    return 0
  done <<< "$ids"
  return 0
}

# Post or update the sticky comment, matched by the marker in <body>'s first line:
# PATCH the first comment containing the marker, else POST a new one (idempotent on re-run).
upsert_comment() {
  local body=$1 marker='<!-- ci-metrics-report -->' id
  id=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate -q ".[] | select(.body | contains(\"$marker\")) | .id" | head -1) || true
  if [[ -n "$id" ]]; then
    gh api "repos/$REPO/issues/comments/$id" -X PATCH -f body="$body"
  else
    gh api "repos/$REPO/issues/$PR_NUMBER/comments" -X POST -f body="$body"
  fi
}

# Entry point: collect this run's sibling metrics, fetch a master baseline for trend deltas,
# render, and surface the report. On pull_request it upserts the sticky PR comment; on a
# default-branch push it writes to the job summary (no PR to comment on). Returns early when
# there's no usable context or no metrics. Marker must lead the comment body.
main() {
  local event=${EVENT_NAME:-pull_request}
  if [[ "$event" == "pull_request" && -z "${PR_NUMBER:-}" ]]; then
    echo "::notice::report-ci-metrics: no PR context, skipping"; return 0
  fi

  local records
  records=$(collect_job_metrics)
  [[ -n "$records" ]] || { echo "::notice::report-ci-metrics: no CI metrics found, skipping"; return 0; }

  # Baseline for trends. Fail-open: a fetch/collect failure leaves baseline empty → "no baseline yet".
  local baseline_run baseline=""
  baseline_run=$(find_baseline_run)
  [[ -n "$baseline_run" ]] && baseline=$(collect_job_metrics "$baseline_run")

  if [[ "$event" == "pull_request" ]]; then
    local marker='<!-- ci-metrics-report -->'
    local body
    body="$marker
## 📊 CI Metrics

$(render_headline "$records")

$(render_trend "$records" "$baseline")

$(render_table "$records")
$(render_cache_fold "$records")"
    upsert_comment "$body"
  else
    # Default-branch push: no PR comment — emit the headline + trend to the job summary.
    {
      printf '## 📊 CI Metrics\n\n'
      render_headline "$records"
      printf '\n'
      render_trend "$records" "$baseline"
    } >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true
  fi
}
