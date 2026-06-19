#!/usr/bin/env bash
# CI metrics completion hook.
#
# Reads cgroup v2 + /proc/net/dev as totals (no baseline; ephemeral runners), writes ${CI_METRICS_DIR}/job-metrics.json, and appends a
# metrics table to $GITHUB_STEP_SUMMARY.
# Fail-open: any error → exit 0 without breaking the job.
#
# Feature flag: CI_METRICS_ENABLED=true written to $GITHUB_ENV by job-started.sh; no-op early exit unless this env var is true.
#
# Env overrides (used by tests; do not set in production):
#   CI_METRICS_CGROUP_ROOT     default /sys/fs/cgroup (mount root)
#   CI_METRICS_CGROUP_LEAF     override the resolved leaf cgroup dir
#   CI_METRICS_PROC_SELF_CGROUP default /proc/self/cgroup (for leaf discovery)
#   CI_METRICS_PROC_NET_DEV    default /proc/net/dev
#   CI_METRICS_PROC_PID1       default /proc/1
#   CI_METRICS_BASELINE_FILE   default /var/lib/ci-metrics/baseline.json (WarpBuild)
#   CI_METRICS_NOW_EPOCH       default $(date +%s) -- for golden tests
#   CI_METRICS_DIR             output dir, default /tmp/ci-metrics
#   CI_METRICS_DISK_PATH       filesystem to report disk usage for, default ${GITHUB_WORKSPACE:-/}
#   CI_METRICS_NPROC           override CPU count (no-quota denominator), default $(nproc)
#   GITHUB_STEP_SUMMARY        default /dev/null (skip table emission)

set -u

# Fail-open: any unexpected error returns rc=0.
# The script also has an explicit `exit 0` at the bottom, so the trap only fires on errors.
# No EXIT trap: it would suppress non-zero returns if the hook is sourced.
trap 'exit 0' ERR

# shellcheck disable=SC2317  # invoked indirectly via traps and helpers
log() {
  printf '[ci-metrics] %s\n' "$*" >&2;
}

# ---------- Feature flag ----------
if [[ "${CI_METRICS_ENABLED:-false}" == "true" ]]; then
    log "collecting metrics (CI_METRICS_ENABLED=true)"
else
    log "skipped: CI_METRICS_ENABLED is not true (value: ${CI_METRICS_ENABLED:-<unset>})"
    exit 0
fi

# ---------- Paths ----------
CGROUP_ROOT="${CI_METRICS_CGROUP_ROOT:-/sys/fs/cgroup}"
PROC_SELF_CGROUP="${CI_METRICS_PROC_SELF_CGROUP:-/proc/self/cgroup}"
PROC_NET_DEV="${CI_METRICS_PROC_NET_DEV:-/proc/net/dev}"
PROC_PID1="${CI_METRICS_PROC_PID1:-/proc/1}"
BASELINE_FILE="${CI_METRICS_BASELINE_FILE:-/var/lib/ci-metrics/baseline.json}"
CI_METRICS_DIR="${CI_METRICS_DIR:-/tmp/ci-metrics}"
mkdir -p "$CI_METRICS_DIR" 2>/dev/null || true

# Resolve the leaf cgroup directory. On cgroup v2 the relevant line is the first one and has the shape "0::<relative-path>". The leaf dir is
# the concatenation of the mount root and that relative path. Tests can short-circuit discovery with CI_METRICS_CGROUP_LEAF.
if [[ -n "${CI_METRICS_CGROUP_LEAF:-}" ]]; then
    CGROUP_LEAF="$CI_METRICS_CGROUP_LEAF"
else
    # Cgroup v2 entry has the shape "0::<path>". On hybrid (v1+v2) systems the v2 line may not be the first one, so select it explicitly
    # rather than blindly taking NR==1. Fall back to the mount root on no match.
    cg_rel=""
    if [[ -r "$PROC_SELF_CGROUP" ]]; then
        cg_rel=$(awk -F: '$1=="0" && $2=="" {print $3; exit}' "$PROC_SELF_CGROUP" 2>/dev/null || true)
    fi
    if [[ -n "$cg_rel" && "$cg_rel" != "/" ]]; then
        CGROUP_LEAF="${CGROUP_ROOT}${cg_rel}"
    else
        CGROUP_LEAF="$CGROUP_ROOT"
    fi
fi

# ---------- Helpers ----------
read_file() { [[ -r "$1" ]] && cat "$1" 2>/dev/null || printf ''; }

# Parse cgroup file. $1=file, $2=key. Echo value or empty.
cg_field() {
    local file=$1 key=$2 line
    line=$(awk -v k="$key" '$1==k {print $2}' "$file" 2>/dev/null) || true
    printf '%s' "$line"
}

# Numeric guard: prints $1 if it looks like a number, else "null".
num() {
    local v=${1:-}
    if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "$v"; else printf 'null'; fi
}

# Bytes → human-readable.
fmt_bytes() {
    local b=${1:-0}
    if   (( b >= 1073741824 )); then awk -v b="$b" 'BEGIN{printf "%.2f GiB", b/1073741824}'
    elif (( b >= 1048576   )); then awk -v b="$b" 'BEGIN{printf "%.2f MiB", b/1048576}'
    elif (( b >= 1024      )); then awk -v b="$b" 'BEGIN{printf "%.2f KiB", b/1024}'
    else                            printf '%s B' "$b"
    fi
}

# Round a float to 2dp/3dp safely.
# shellcheck disable=SC2317  # all helpers below are called via command substitution
round2() { awk -v v="${1:-0}" 'BEGIN{printf "%.2f", v}'; }
# shellcheck disable=SC2317,SC2329
round3() { awk -v v="${1:-0}" 'BEGIN{printf "%.3f", v}'; }

# Ratio (0–1) → percentage strings. pct0 = integer dp, pct1 = one dp.
# Centralised so the display precision is consistent everywhere.
# shellcheck disable=SC2317
pct0() { awk -v r="${1:-0}" 'BEGIN{printf "%.0f", r*100}'; }
# shellcheck disable=SC2317
pct1() { awk -v r="${1:-0}" 'BEGIN{printf "%.1f", r*100}'; }

# ---------- Timestamps + duration ----------
now_epoch="${CI_METRICS_NOW_EPOCH:-$(date +%s)}"
# GNU `date` supports -d "@epoch" and %6N (microseconds).
# On BSD `date` (e.g. macOS) the call may succeed but emit a literal "%6N"; fall back to an ISO-8601 second-resolution when that happens.
captured_at=$(date -u -d "@${now_epoch}" +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null \
              || date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ "$captured_at" == *"%6N"* || -z "$captured_at" ]]; then
    captured_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
# Belt-and-braces: an ISO-8601-ish timestamp uses only [0-9T:.Z-+]. Reject anything else so a misbehaving date can't inject characters that
# would break the JSON we emit below.
[[ "$captured_at" =~ ^[0-9T:.Z+-]+$ ]] || captured_at=""

# Job-start proxy: cgroup leaf directory's mtime, which is set when the cgroup is created. On ARC that equals container/job start.
# Fall back to /proc/1 mtime, then to "now" (→ duration_seconds 0.000).
job_start_epoch=$(stat -c %Y "$CGROUP_LEAF" 2>/dev/null || true)
if [[ -z "$job_start_epoch" ]]; then
    job_start_epoch=$(stat -c %Y "$PROC_PID1" 2>/dev/null || echo "$now_epoch")
fi
duration_seconds=$(awk -v n="$now_epoch" -v s="$job_start_epoch" \
                       'BEGIN{d=n-s; if (d<0) d=0; printf "%.3f", d}')

# ---------- cgroup CPU ----------
cpu_stat_file="$CGROUP_LEAF/cpu.stat"
cpu_usage_usec=$(cg_field "$cpu_stat_file" usage_usec)
cpu_throttled_usec=$(cg_field "$cpu_stat_file" throttled_usec)
cpu_nr_throttled=$(cg_field "$cpu_stat_file" nr_throttled)

cpu_max=$(read_file "$CGROUP_LEAF/cpu.max")
cpu_quota=${cpu_max%% *}
cpu_period=${cpu_max#* }
if [[ -z "$cpu_max" || "$cpu_quota" == "max" ]]; then
    cpu_limit_cores=""
else
    cpu_limit_cores=$(awk -v q="$cpu_quota" -v p="$cpu_period" \
        'BEGIN{ if (p+0>0) printf "%.3f", q/p; }')
fi

# CPU-avg denominator candidates, in preference order:
#   1. cpu_limit_cores  — hard cgroup quota (above), when set.
#   2. cpu_request_cores — the runner's CPU request from the Downward API env var
#      CI_METRICS_CPU_REQUEST_MILLI (millicores). Exact; the right denominator for our
#      burstable ARC runners (no quota, request set). Absent on WarpBuild.
#   3. cpu_online_count — nproc. Only correct when the runner owns the host (WarpBuild
#      dedicated VM); on ARC this is the whole node, so it's the last resort.
if [[ "${CI_METRICS_CPU_REQUEST_MILLI:-}" =~ ^[0-9]+$ ]] && (( CI_METRICS_CPU_REQUEST_MILLI > 0 )); then
    cpu_request_cores=$(awk -v m="$CI_METRICS_CPU_REQUEST_MILLI" 'BEGIN{printf "%.3f", m/1000}')
else
    cpu_request_cores=""
fi
cpu_online_count="${CI_METRICS_NPROC:-$(nproc 2>/dev/null || true)}"
[[ "$cpu_online_count" =~ ^[0-9]+$ ]] || cpu_online_count=""

# Derived CPU metrics.
# usage_seconds / throttled_seconds depend only on the raw counter being present. Rate / utilization additionally need a non-zero duration.
if [[ -n "$cpu_usage_usec" ]]; then
    cpu_usage_seconds=$(awk -v u="$cpu_usage_usec" 'BEGIN{printf "%.3f", u/1000000}')
else
    cpu_usage_seconds=""
fi
# Arithmetic guard on duration (not a string compare on the "%.3f" output).
if [[ -n "$cpu_usage_usec" && -n "$cpu_limit_cores" && -n "$duration_seconds" ]] \
   && awk -v d="$duration_seconds" 'BEGIN{exit !(d+0>0)}'; then
    cpu_avg_utilization=$(awk -v u="$cpu_usage_usec" -v d="$duration_seconds" -v c="$cpu_limit_cores" \
        'BEGIN{ if (d>0 && c>0) printf "%.4f", (u/1000000)/(d*c) }')
else
    cpu_avg_utilization=""
fi

if [[ -n "$cpu_throttled_usec" ]]; then
    cpu_throttled_seconds=$(awk -v t="$cpu_throttled_usec" 'BEGIN{printf "%.3f", t/1000000}')
else
    cpu_throttled_seconds=""
fi
if [[ -n "$cpu_throttled_usec" && -n "$duration_seconds" ]] \
   && awk -v d="$duration_seconds" 'BEGIN{exit !(d+0>0)}'; then
    cpu_throttle_rate=$(awk -v t="$cpu_throttled_usec" -v d="$duration_seconds" \
        'BEGIN{ if (d>0) printf "%.4f", (t/1000000)/d }')
else
    cpu_throttle_rate=""
fi

# CPU pressure (PSI). Line shape: "some avg10=X.YZ avg60=... avg300=... total=..."
# $1=line $2=key — explicit args (no closure on outer variables, mirroring cg_field).
# shellcheck disable=SC2317  # called via command substitution below
psi_field() {
    printf '%s' "$1" | awk -v k="$2" \
        '{ for (i=2;i<=NF;i++) { split($i,a,"="); if (a[1]==k) print a[2] } }'
}
cpu_pressure_file="$CGROUP_LEAF/cpu.pressure"
pressure_some_line=$(awk '$1=="some"' "$cpu_pressure_file" 2>/dev/null || true)
pressure_some_avg10=$(psi_field "$pressure_some_line" avg10)
pressure_some_avg60=$(psi_field "$pressure_some_line" avg60)
pressure_some_avg300=$(psi_field "$pressure_some_line" avg300)

# ---------- cgroup memory ----------
memory_peak_bytes=$(read_file "$CGROUP_LEAF/memory.peak")
memory_peak_bytes=${memory_peak_bytes//$'\n'/}
memory_limit_raw=$(read_file "$CGROUP_LEAF/memory.max")
memory_limit_raw=${memory_limit_raw//$'\n'/}
if [[ "$memory_limit_raw" == "max" || -z "$memory_limit_raw" ]]; then
    memory_limit_bytes=""
else
    memory_limit_bytes="$memory_limit_raw"
fi
if [[ -n "$memory_peak_bytes" && -n "$memory_limit_bytes" ]]; then
    memory_peak_utilization=$(awk -v p="$memory_peak_bytes" -v l="$memory_limit_bytes" \
        'BEGIN{ if (l>0) printf "%.4f", p/l }')
else
    memory_peak_utilization=""
fi

# OOM accounting from memory.events. `oom` = times the cgroup hit its limit and
# entered reclaim/OOM; `oom_kill` = processes actually killed. Either being >0 is
# the explanation for a job that died with no other signal, so it is surfaced.
memory_events_file="$CGROUP_LEAF/memory.events"
memory_oom=$(cg_field "$memory_events_file" oom)
memory_oom_kill=$(cg_field "$memory_events_file" oom_kill)

# ---------- /proc/net/dev ----------
declare -A net_rx net_tx
net_rx_total=0
net_tx_total=0
if [[ -r "$PROC_NET_DEV" ]]; then
    # Skip 2 header lines. Field 1 = "iface:" (with trailing colon),
    # field 2 = rx_bytes, field 10 = tx_bytes. Emit them with a single
    # awk per line to avoid spawning three processes per interface.
    while read -r iface rx tx; do
        [[ -z "$iface" || -z "$rx" || -z "$tx" ]] && continue
        # Defensive guards before arithmetic:
        # - rx/tx must be non-negative integers (malformed lines drop out)
        # - iface name kept to the IFNAMSIZ-safe alphanumeric + ._- set (Linux netdevice(7)), preventing any character that would require
        # JSON escaping later.
        [[ "$rx" =~ ^[0-9]+$ && "$tx" =~ ^[0-9]+$ ]] || continue
        [[ "$iface" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        net_rx[$iface]=$rx
        net_tx[$iface]=$tx
        # Skip loopback for totals; still include in by_interface.
        if [[ "$iface" != "lo" ]]; then
            net_rx_total=$(( net_rx_total + rx ))
            net_tx_total=$(( net_tx_total + tx ))
        fi
    done < <(tail -n +3 "$PROC_NET_DEV" 2>/dev/null \
             | awk '{ gsub(":","",$1); print $1, $2, $10 }' || true)
fi

# Apply baseline subtraction if present (WarpBuild boot snapshot).
# The awk parser below assumes baseline values are unquoted integers (rx_bytes / tx_bytes), which is what the WarpBuild snapshot writes.
# It is not a general JSON parser — strings containing spaces/commas would tokenise wrong, but that's fine for this file format.
# Non-numeric / missing values silently skip subtraction (fail-open).
if [[ -r "$BASELINE_FILE" ]]; then
    base_rx=$(awk -F'[":, ]+' '/"rx_bytes"/ { for (i=1;i<=NF;i++) if ($i=="rx_bytes") print $(i+1); exit }' \
              "$BASELINE_FILE" 2>/dev/null || true)
    base_tx=$(awk -F'[":, ]+' '/"tx_bytes"/ { for (i=1;i<=NF;i++) if ($i=="tx_bytes") print $(i+1); exit }' \
              "$BASELINE_FILE" 2>/dev/null || true)
    if [[ "$base_rx" =~ ^[0-9]+$ ]] && (( net_rx_total >= base_rx )); then
        net_rx_total=$(( net_rx_total - base_rx ))
    fi
    if [[ "$base_tx" =~ ^[0-9]+$ ]] && (( net_tx_total >= base_tx )); then
        net_tx_total=$(( net_tx_total - base_tx ))
    fi
fi

# ---------- Disk ----------
# Point-in-time filesystem usage at job end for the workspace mount. cgroup v2 has
# no per-job disk-space counter, so this is the runner-wide fs that holds the
# checkout/build artifacts — the thing that triggers "no space left on device".
# `df -kP` gives portable 1K-block output: cols 2/3/4 = total/used/available KiB.
disk_path="${CI_METRICS_DISK_PATH:-${GITHUB_WORKSPACE:-/}}"
disk_total_bytes=""
disk_used_bytes=""
disk_avail_bytes=""
disk_utilization=""
if df_line=$(df -kP "$disk_path" 2>/dev/null | awk 'NR==2{print $2, $3, $4}'); then
    read -r df_total_k df_used_k df_avail_k <<<"$df_line"
    if [[ "$df_total_k" =~ ^[0-9]+$ && "$df_used_k" =~ ^[0-9]+$ && "$df_avail_k" =~ ^[0-9]+$ ]]; then
        disk_total_bytes=$(( df_total_k * 1024 ))
        disk_used_bytes=$(( df_used_k * 1024 ))
        disk_avail_bytes=$(( df_avail_k * 1024 ))
        if (( disk_used_bytes + disk_avail_bytes > 0 )); then
            disk_utilization=$(awk -v u="$disk_used_bytes" -v a="$disk_avail_bytes" \
                'BEGIN{ printf "%.4f", u/(u+a) }')
        fi
    fi
fi
# Only emit the path in JSON if it is a plain, JSON-safe string (no quotes/control
# chars). Otherwise null it to avoid corrupting the document.
if [[ ! "$disk_path" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    disk_path_json="null"
else
    disk_path_json="\"$disk_path\""
fi

# ---------- JSON assembly ----------
json_by_interface=""
sep=""
for iface in "${!net_rx[@]}"; do
    json_by_interface+="${sep}\"${iface}\":{\"rx_bytes\":${net_rx[$iface]},\"tx_bytes\":${net_tx[$iface]}}"
    sep=","
done

job_metrics_json=$(cat <<EOF
{"schema_version":3,"captured_at":"$captured_at","duration_seconds":$(num "$duration_seconds"),"cgroup":{"version":2,"cpu":{"usage_seconds":$(num "$cpu_usage_seconds"),"throttled_seconds":$(num "$cpu_throttled_seconds"),"nr_throttled":$(num "$cpu_nr_throttled"),"limit_cores":$(num "$cpu_limit_cores"),"request_cores":$(num "$cpu_request_cores"),"online_count":$(num "$cpu_online_count"),"avg_utilization":$(num "$cpu_avg_utilization"),"throttle_rate":$(num "$cpu_throttle_rate"),"pressure_some_avg10":$(num "$pressure_some_avg10"),"pressure_some_avg60":$(num "$pressure_some_avg60"),"pressure_some_avg300":$(num "$pressure_some_avg300")},"memory":{"peak_bytes":$(num "$memory_peak_bytes"),"limit_bytes":$(num "$memory_limit_bytes"),"peak_utilization":$(num "$memory_peak_utilization"),"oom":$(num "$memory_oom"),"oom_kill":$(num "$memory_oom_kill")}},"net":{"rx_bytes":${net_rx_total},"tx_bytes":${net_tx_total},"by_interface":{${json_by_interface}}},"disk":{"path":${disk_path_json},"total_bytes":$(num "$disk_total_bytes"),"used_bytes":$(num "$disk_used_bytes"),"available_bytes":$(num "$disk_avail_bytes"),"utilization":$(num "$disk_utilization")}}
EOF
)

# ---------- Cache JSON ingestion ----------
# Each gh-action_cache invocation writes ${CI_METRICS_DIR}/cache-${slug}.json
# (schema documented in https://github.com/SonarSource/gh-action_cache/pull/62).
# We aggregate every snippet into one cache[] array, augment job_metrics_json with it, and render the summary table below.
# Skipped gracefully when:
#   - jq is missing (degraded ARC image)
#   - no cache-*.json files exist (no cache step in the job)
#   - all files fail to parse
cache_json="[]"
shopt -s nullglob
cache_files=("${CI_METRICS_DIR}"/cache-*.json)
shopt -u nullglob
# Filter to readable, non-empty files; sort by name for deterministic order.
readable_cache_files=()
for f in "${cache_files[@]}"; do
    [[ -s "$f" && -r "$f" ]] && readable_cache_files+=("$f")
done
if (( ${#readable_cache_files[@]} > 0 )) && command -v jq >/dev/null 2>&1; then
    # Bash globs are already sorted lexicographically, so `readable_cache_files` is in deterministic order — no extra sort needed.
    # Build a JSON array incrementally so a single bad file doesn't abort the whole pipeline.
    parsed=()
    for f in "${readable_cache_files[@]}"; do
        if obj=$(jq -c '.' "$f" 2>/dev/null); then
            parsed+=("$obj")
        else
            log "skipping invalid cache JSON: $f"
        fi
    done
    if (( ${#parsed[@]} > 0 )); then
        # Comma-join the validated objects into a JSON array literal.
        # `%` in the joined value is safe: `printf '[%s]' "$arg"` only honors specifiers in the format string, not in the substituted arg.
        printf -v cache_json '[%s]' "$(IFS=,; printf '%s' "${parsed[*]}")"
        # Merge into job_metrics_json. Fall back to the un-augmented value on jq failure (fail-open).
        # Skipped entirely when no cache file parsed: keeps `cache` key absent so M1.2 output stays byte-identical.
        merged=$(jq -cn --argjson base "$job_metrics_json" --argjson cache "$cache_json" \
            '$base + {cache: $cache}' 2>/dev/null) && job_metrics_json="$merged"
    fi
fi

# Persist + stdout-log. The stdout copy is wrapped in sentinels so report-ci-insights
# (BUILD-11310) can recover the metrics JSON from the job log via the Actions API.
printf '%s\n' "$job_metrics_json" > "${CI_METRICS_DIR}/job-metrics.json" 2>/dev/null || true
printf '===CI_METRICS_JSON_BEGIN===%s===CI_METRICS_JSON_END===\n' "$job_metrics_json"

# ---------- Step summary ----------
summary_target="${GITHUB_STEP_SUMMARY:-/dev/null}"

# Pretty values

# CPU avg: mean cores used over the job, shown against a denominator so the number is
# actionable for right-sizing. Denominator preference:
#   1. cgroup quota  -> "/ N cores (P%)"            (hard limit)
#   2. CPU request   -> "/ N cores requested (P%)"  (ARC burstable; P can exceed 100% when bursting)
#   3. nproc         -> "/ N cores available (P%)"  (WarpBuild dedicated VM)
# Falls back to bare cores, then n/a.
# This rendering mirrors _rci_cpu_cell in report-ci-metrics/lib.sh; the expected output per tier
# is pinned by the "_rci_cpu_cell() denominator preference" spec — keep both in sync if changed.
cpu_avg_cores=""
cpu_avg_pct=""   # set when a denominator exists; drives both the table % and the digest line
if [[ -n "$cpu_usage_seconds" && -n "$duration_seconds" ]]; then
    cpu_avg_cores=$(awk -v u="$cpu_usage_seconds" -v d="$duration_seconds" \
        'BEGIN{ if (d>0) printf "%.2f", u/d }')
fi
if [[ -n "$cpu_avg_cores" && -n "$cpu_limit_cores" && -n "$cpu_avg_utilization" ]]; then
    cpu_avg_pct=$(pct0 "$cpu_avg_utilization")
    v_cpu_avg="${cpu_avg_cores} / $(round2 "$cpu_limit_cores") cores (${cpu_avg_pct}%)"
elif [[ -n "$cpu_avg_cores" && -n "$cpu_request_cores" ]] \
     && awk -v r="$cpu_request_cores" 'BEGIN{exit !(r+0>0)}'; then
    cpu_avg_pct=$(awk -v c="$cpu_avg_cores" -v r="$cpu_request_cores" \
        'BEGIN{ printf "%.0f", (c/r)*100 }')
    v_cpu_avg="${cpu_avg_cores} / $(round2 "$cpu_request_cores") cores requested (${cpu_avg_pct}%)"
elif [[ -n "$cpu_avg_cores" && -n "$cpu_online_count" ]] \
     && (( cpu_online_count > 0 )); then
    cpu_avg_pct=$(awk -v c="$cpu_avg_cores" -v n="$cpu_online_count" \
        'BEGIN{ printf "%.0f", (c/n)*100 }')
    v_cpu_avg="${cpu_avg_cores} / ${cpu_online_count} cores available (${cpu_avg_pct}%)"
elif [[ -n "$cpu_avg_cores" ]]; then
    v_cpu_avg="${cpu_avg_cores} cores"
else
    v_cpu_avg="n/a"
fi

# Memory peak: high-water mark vs limit.
if [[ -n "$memory_peak_bytes" ]]; then
    if [[ -n "$memory_limit_bytes" && -n "$memory_peak_utilization" ]]; then
        # Reuse the ratio already computed for JSON to keep the two outputs in sync.
        v_mem="$(fmt_bytes "$memory_peak_bytes") / $(fmt_bytes "$memory_limit_bytes") ($(pct0 "$memory_peak_utilization")%)"
    else
        v_mem="$(fmt_bytes "$memory_peak_bytes") (no limit)"
    fi
else
    v_mem="n/a"
fi

# Disk: point-in-time fs usage at job end (used / total).
if [[ -n "$disk_used_bytes" && -n "$disk_total_bytes" && -n "$disk_utilization" ]]; then
    v_disk="$(fmt_bytes "$disk_used_bytes") / $(fmt_bytes "$disk_total_bytes") ($(pct0 "$disk_utilization")%)"
else
    v_disk="n/a"
fi

# Network total: cumulative bytes over the job, both directions on one row.
v_net="$(fmt_bytes "$net_rx_total") ↓ / $(fmt_bytes "$net_tx_total") ↑"

# CPU throttled (conditional): only meaningful when a CPU quota exists and throttling
# actually occurred. On our no-limit runners this is always absent.
show_throttled=0
if [[ -n "$cpu_limit_cores" && -n "$cpu_throttled_seconds" ]] \
   && awk -v t="$cpu_throttled_seconds" 'BEGIN{exit !(t+0>0)}'; then
    show_throttled=1
    if [[ -n "$cpu_throttle_rate" ]]; then
        v_cpu_throttled="${cpu_throttled_seconds}s ($(pct1 "$cpu_throttle_rate")%, ${cpu_nr_throttled:-0} events)"
    else
        v_cpu_throttled="${cpu_throttled_seconds}s (${cpu_nr_throttled:-0} events)"
    fi
fi

# OOM kills (conditional): only shown when the cgroup recorded a kill. This is the
# explanation for an otherwise-silent job failure.
show_oom=0
if [[ "$memory_oom_kill" =~ ^[0-9]+$ ]] && (( memory_oom_kill > 0 )); then
    show_oom=1
fi

# ---------- Step summary: one collapsible CI Metrics block per job ----------
# Folded by default to keep a multi-job matrix summary compact; the <summary> line carries a digest
# so the common case needs no expand. Title is plain "CI Metrics" to stay distinct from the
# aggregated CI Metrics table emitted by ci-github-actions' report-ci-metrics action.

# Digest: middot-joined token per available metric; n/a metrics are dropped. Anomaly tokens (OOM /
# throttling) lead and trigger a "[!]" prefix so they show while collapsed. Net is always present.
digest_parts=()
(( show_oom )) && digest_parts+=("OOM kill ×${memory_oom_kill}")
if (( show_throttled )); then
    if [[ -n "$cpu_throttle_rate" ]]; then
        digest_parts+=("throttled $(pct0 "$cpu_throttle_rate")%")
    else
        digest_parts+=("throttled ${cpu_throttled_seconds}s")
    fi
fi
if [[ -n "$cpu_avg_pct" ]]; then
    digest_parts+=("CPU ${cpu_avg_pct}%")
elif [[ -n "$cpu_avg_cores" ]]; then
    digest_parts+=("CPU ${cpu_avg_cores} cores")
fi
if [[ -n "$memory_peak_utilization" ]]; then
    digest_parts+=("Mem $(pct0 "$memory_peak_utilization")%")
elif [[ -n "$memory_peak_bytes" ]]; then
    digest_parts+=("Mem $(fmt_bytes "$memory_peak_bytes")")
fi
[[ -n "$disk_utilization" ]] && digest_parts+=("Disk $(pct0 "$disk_utilization")%")
digest_parts+=("Net $(fmt_bytes "$net_rx_total")↓ $(fmt_bytes "$net_tx_total")↑")

digest=""
for part in "${digest_parts[@]}"; do
    digest+="${digest:+ · }${part}"
done
summary_line="CI Metrics — ${digest}"
(( show_oom || show_throttled )) && summary_line="[!] ${summary_line}"

# Open the fold and emit the metric table. A blank line after </summary> is required for the
# Markdown table inside <details> to render on GitHub.
{
    printf '<details><summary>%s</summary>\n\n' "$summary_line"
    printf '| Metric | Value |\n'
    printf '|---|---|\n'
    printf '| CPU avg | %s |\n' "$v_cpu_avg"
    printf '| Memory peak | %s |\n' "$v_mem"
    printf '| Disk | %s |\n' "$v_disk"
    printf '| Network total | %s |\n' "$v_net"
    (( show_throttled )) && printf '| CPU throttled | %s |\n' "$v_cpu_throttled"
    (( show_oom ))       && printf '| OOM kills | %s |\n' "$memory_oom_kill"
} >> "$summary_target" 2>/dev/null || true

# ---------- Cache list (inside the same fold) ----------
# One line per ${CI_METRICS_DIR}/cache-*.json entry; skipped when none.
if [[ "$cache_json" != "[]" ]] && command -v jq >/dev/null 2>&1; then
    # Fields joined by ASCII Unit Separator ( / $'\x1f'); escaped so the file stays YAML-safe
    # when runner.yaml.gotmpl embeds it verbatim. Booleans as strings so jq `//` keeps `false`.
    # Numeric sizes are digits or "" (null/missing). Fail-open on jq error.
    cache_rows=$(jq -r --argjson c "$cache_json" -n '
        $c
        | sort_by(.step // "")
        | .[]
        | [
            (.key // ""),
            (if .cache_hit == true then "true" else "false" end),
            (.restore_key_hit // ""),
            (.backend // "unknown"),
            (if (.size_bytes_restored|type) == "number" then (.size_bytes_restored|tostring) else "" end),
            (if .saved == true then "true" elif .saved == false then "false" else "" end),
            (if (.size_bytes_at_end|type) == "number" then (.size_bytes_at_end|tostring) else "" end)
          ]
        | join("\u001f")
    ' 2>/dev/null) || cache_rows=""

    if [[ -n "$cache_rows" ]]; then
        {
            printf '\n**Cache**\n'
            # `|| [[ -n "$c_key" ]]` guards a final line without a trailing newline.
            while IFS=$'\x1f' read -r c_key c_hit c_rkey c_backend c_size_r c_saved c_size_e || [[ -n "$c_key" ]]; do
                # status: hit (+restored size when known) / partial (<restore-key>) / miss
                if [[ "$c_hit" == "true" ]]; then
                    v_status="hit"
                    [[ "$c_size_r" =~ ^[0-9]+$ ]] && v_status="hit ($(fmt_bytes "$c_size_r"))"
                elif [[ -n "$c_rkey" ]]; then
                    v_status="partial (${c_rkey})"
                else
                    v_status="miss"
                fi
                # "saved <size>" only when the action persisted it; size-at-end is otherwise just the
                # job-end on-disk size, which corresponds to nothing saved.
                v_saved=""
                if [[ "$c_saved" == "true" ]]; then
                    if [[ "$c_size_e" =~ ^[0-9]+$ ]]; then
                        v_saved=", saved $(fmt_bytes "$c_size_e")"
                    else
                        v_saved=", saved"
                    fi
                fi
                # shellcheck disable=SC2016  # backticks are literal Markdown code-span, not command substitution
                printf -- '- `%s` — %s, %s%s\n' "$c_key" "$v_status" "$c_backend" "$v_saved"
            done <<< "$cache_rows"
        } >> "$summary_target" 2>/dev/null || true
    fi
fi

# Close the fold (blank line so the preceding Markdown block terminates).
printf '\n</details>\n' >> "$summary_target" 2>/dev/null || true

exit 0
