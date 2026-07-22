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

# Emit "<name>\t<json>" for completed jobs with metrics. $1 defaults to RUN_ID.
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

# Sanitize author-influenced markdown table cells.
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

# Bytes → human-readable IEC units. Blank/non-numeric renders as "n/a".
_rci_fmt_bytes() {
  local b=${1:-}
  [[ "$b" =~ ^[0-9]+$ ]] || { printf 'n/a'; return; }
  if   (( b >= 1073741824 )); then awk -v b="$b" 'BEGIN{printf "%.2f GiB", b/1073741824}'
  elif (( b >= 1048576   )); then awk -v b="$b" 'BEGIN{printf "%.2f MiB", b/1048576}'
  elif (( b >= 1024      )); then awk -v b="$b" 'BEGIN{printf "%.2f KiB", b/1024}'
  else                            printf '%s B' "$b"
  fi
}

# CPU-avg display cell. Denominator: limit -> request -> online cores.
_rci_cpu_cell() {
  local json=$1
  jq -r '.cgroup.cpu as $c | .duration_seconds as $d | if ($c.usage_seconds != null and $d != null and $d > 0) then (($c.usage_seconds / $d) * 100 | round / 100) as $cores | if ($c.limit_cores != null and $c.avg_utilization != null) then "\($cores) / \(($c.limit_cores*100|round)/100) cores (\(($c.avg_utilization*100)|round)%)" elif ($c.request_cores != null and $c.request_cores > 0) then "\($cores) / \(($c.request_cores*100|round)/100) cores requested (\((($cores/$c.request_cores)*100)|round)%)" elif ($c.online_count != null and $c.online_count > 0) then "\($cores) / \($c.online_count) cores available (\((($cores/$c.online_count)*100)|round)%)" else "\($cores) cores" end else "n/a" end' <<< "$json"
}

# Sum a numeric jq path across all record JSONs; nulls count as 0.
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

# Integer cache hit-rate percent. Restore-key matches count as hits.
_rci_cache_hit_rate() {
  local records=$1 total=0 hits=0 name json
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local n h
    n=$(jq -r '(.cache // []) | length' <<< "$json" 2>/dev/null); [[ "$n" =~ ^[0-9]+$ ]] || n=0
    h=$(jq -r '[.cache[]? | select(.cache_hit == true or .restore_key_hit != null)] | length' <<< "$json" 2>/dev/null); [[ "$h" =~ ^[0-9]+$ ]] || h=0
    total=$((total + n)); hits=$((hits + h))
  done <<< "$records"
  (( total == 0 )) && return 0
  awk -v h="$hits" -v t="$total" 'BEGIN{printf "%.0f", (h/t)*100}'
}

# CPU utilisation ratio shown by _rci_cpu_cell, or empty without a percentage denominator.
_rci_cpu_util() {
  local json=$1
  jq -r '.cgroup.cpu as $c | .duration_seconds as $d |
    if ($c.usage_seconds != null and $d != null and $d > 0) then
      (($c.usage_seconds / $d) * 100 | round / 100) as $cores |
      if ($c.limit_cores != null and $c.avg_utilization != null) then $c.avg_utilization
      elif ($c.request_cores != null and $c.request_cores > 0) then ($cores / $c.request_cores)
      elif ($c.online_count != null and $c.online_count > 0) then ($cores / $c.online_count)
      else empty end
    else empty end' <<< "$json" 2>/dev/null
}

# Memory peak utilisation ratio, or empty when unavailable.
_rci_mem_util() {
  local json=$1
  jq -r '.cgroup.memory.peak_utilization // empty' <<< "$json" 2>/dev/null
}

_rci_worst_by_metric() {
  local records=$1 metric_fn=$2 name json worst="-1" worst_name=""
  while IFS=$'\t' read -r name json; do
    [[ -z "$json" ]] && continue
    local u
    u=$("$metric_fn" "$json")
    [[ -n "$u" ]] || continue
    if awk -v a="$u" -v b="$worst" 'BEGIN{exit !(a+0>b+0)}'; then worst=$u; worst_name=$name; fi
  done <<< "$records"
  [[ -n "$worst_name" ]] || return 0
  printf '%s\t%s' "$worst" "$worst_name"
}

_rci_metric_for_job() {
  local records=$1 target=$2 metric_fn=$3 name json
  while IFS=$'\t' read -r name json; do
    [[ "$name" == "$target" ]] || continue
    local u
    u=$("$metric_fn" "$json")
    [[ -n "$u" ]] || return 0
    printf '%s' "$u"
    return 0
  done <<< "$records"
  return 0
}

_rci_worst_cpu_util() {
  _rci_worst_by_metric "$1" _rci_cpu_util
}

_rci_cpu_util_for_job() {
  _rci_metric_for_job "$1" "$2" _rci_cpu_util
}

_rci_worst_mem_util() {
  _rci_worst_by_metric "$1" _rci_mem_util
}

_rci_mem_util_for_job() {
  _rci_metric_for_job "$1" "$2" _rci_mem_util
}

# Neutral signed delta; empty baseline renders as n/a.
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

# Render one default-branch trend line from cache, worst CPU avg, and worst memory utilisation.
render_trend() {
  local records=$1 baseline=$2 branch=${3:-${DEFAULT_BRANCH:-master}}
  local label="Trend vs ${branch}:"
  if [[ -z "$baseline" ]]; then
    printf '%s no baseline yet\n' "$label"
    return 0
  fi

  local segs=""

  local cur_hr base_hr
  cur_hr=$(_rci_cache_hit_rate "$records")
  base_hr=$(_rci_cache_hit_rate "$baseline")
  if [[ -n "$cur_hr" ]]; then
    segs="${segs:+$segs · }cache hit ${cur_hr}% ($(_rci_fmt_delta "$cur_hr" "$base_hr" pp))"
  fi

  local cur_cpu cpu_pct base_cpu_util base_cpu_pct cpu_job
  cur_cpu=$(_rci_worst_cpu_util "$records")
  if [[ -n "$cur_cpu" ]]; then
    cpu_job=${cur_cpu#*$'\t'}
    cpu_pct=$(awk -v u="${cur_cpu%%$'\t'*}" 'BEGIN{printf "%.0f", u*100}')
    base_cpu_util=$(_rci_cpu_util_for_job "$baseline" "$cpu_job")
    base_cpu_pct=""
    [[ -n "$base_cpu_util" ]] && base_cpu_pct=$(awk -v u="$base_cpu_util" 'BEGIN{printf "%.0f", u*100}')
    segs="${segs:+$segs · }CPU avg $(_rci_md_cell "$cpu_job") ${cpu_pct}% ($(_rci_fmt_delta "$cpu_pct" "$base_cpu_pct" pp))"
  fi

  local cur_mem cur_pct base_util base_pct mem_job
  cur_mem=$(_rci_worst_mem_util "$records")
  if [[ -n "$cur_mem" ]]; then
    mem_job=${cur_mem#*$'\t'}
    cur_pct=$(awk -v u="${cur_mem%%$'\t'*}" 'BEGIN{printf "%.0f", u*100}')
    base_util=$(_rci_mem_util_for_job "$baseline" "$mem_job")
    base_pct=""
    [[ -n "$base_util" ]] && base_pct=$(awk -v u="$base_util" 'BEGIN{printf "%.0f", u*100}')
    segs="${segs:+$segs · }peak mem $(_rci_md_cell "$mem_job") ${cur_pct}% ($(_rci_fmt_delta "$cur_pct" "$base_pct" pp))"
  fi

  [[ -n "$segs" ]] && printf '%s %s\n' "$label" "$segs"
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
      hit=$(jq -r ".cache[$i] | if .cache_hit == true then \"yes\" elif ((.restore_key_hit // \"\") != \"\") then \"partial\" else \"no\" end" <<< "$json")
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

# Echo the default-branch baseline run id, or empty on first run/API failure.
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
    # On default-branch pushes, skip the current run and use the previous one.
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

# Entry point: collect metrics, compare to the default branch, then comment or summarize.
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

$(render_trend "$records" "$baseline" "${DEFAULT_BRANCH:-master}")

$(render_table "$records")
$(render_cache_fold "$records")"
    upsert_comment "$body"
  else
    # Default-branch push: no PR comment — emit the headline + trend to the job summary.
    {
      printf '## 📊 CI Metrics\n\n'
      render_headline "$records"
      printf '\n'
      render_trend "$records" "$baseline" "${DEFAULT_BRANCH:-master}"
    } >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true
  fi
}
