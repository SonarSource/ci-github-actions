#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Sentinels used by the producer hook to wrap its metrics JSON on one line.
BEGIN='===CI_METRICS_JSON_BEGIN==='
END='===CI_METRICS_JSON_END==='

Describe 'report-ci-metrics/lib.sh'
  Include report-ci-metrics/lib.sh

  Describe 'extract_metrics_json()'
    It 'extracts the JSON from a realistic timestamped multi-line log'
      log=$(printf '%s\n' \
        '2026-06-12T09:00:00.0000000Z Starting job' \
        '2026-06-12T09:00:01.1234567Z Running build step' \
        "2026-06-12T09:00:02.7654321Z ${BEGIN}{\"duration_ms\":1234,\"cache_hit\":true}${END}" \
        '2026-06-12T09:00:03.0000000Z Build complete')
      When call extract_metrics_json "$log"
      The status should be success
      The output should equal '{"duration_ms":1234,"cache_hit":true}'
    End

    It 'returns empty string when no sentinel is present'
      log=$(printf '%s\n' \
        '2026-06-12T09:00:00.0000000Z Starting job' \
        '2026-06-12T09:00:01.0000000Z nothing to see here')
      When call extract_metrics_json "$log"
      The status should be success
      The output should equal ''
    End

    It 'returns the LAST block when multiple are present'
      log=$(printf '%s\n' \
        "2026-06-12T09:00:01.0000000Z ${BEGIN}{\"n\":1}${END}" \
        "2026-06-12T09:00:02.0000000Z ${BEGIN}{\"n\":2}${END}")
      When call extract_metrics_json "$log"
      The status should be success
      The output should equal '{"n":2}'
    End

    It 'ignores an earlier prose mention of the BEGIN sentinel and extracts the real block'
      # Decoy BEGIN sentinel without a matching END must not be matched.
      log=$(printf '%s\n' \
        "2026-06-12T09:00:00.0000000Z note: the producer prints ${BEGIN} then the payload" \
        '2026-06-12T09:00:01.0000000Z unrelated log noise' \
        "2026-06-12T09:00:02.0000000Z ${BEGIN}{\"real\":true}${END}" \
        '2026-06-12T09:00:03.0000000Z done')
      When call extract_metrics_json "$log"
      The status should be success
      The output should equal '{"real":true}'
    End

    It 'passes through percent signs and JSON string escapes intact'
      payload='{"path":"/tmp/x_y.z-1","cache_key":"deps-100%-\"v2\"","ratio":"50%"}'
      log=$(printf '%s\n' \
        '2026-06-12T09:00:00.0000000Z start' \
        "2026-06-12T09:00:01.0000000Z ${BEGIN}${payload}${END}")
      When call extract_metrics_json "$log"
      The status should be success
      The output should equal "$payload"
    End
  End

  Describe 'collect_job_metrics()'
    # Mock job IDs: 10/11 emit, 12 in_progress, 13 self, 14 no-metrics, 15 log-fails, 16 corrupt.
    export REPO=o/r RUN_ID=123 SELF_JOB=report-ci-metrics

    Mock gh
      case "$*" in
        *runs/*/jobs*)
          printf '%s\n' \
            '10	build	completed' \
            '11	test (linux)	completed' \
            '12	flaky	in_progress' \
            '13	report-ci-metrics	completed' \
            '14	no-metrics-job	completed' \
            '15	boom	completed' \
            '16	corrupt	completed'
          ;;
        *jobs/10/logs*)
          # Sentinels written literally (Mock bodies don't inherit the BEGIN/END vars).
          printf '%s\n' \
            '2026-06-12T09:00:00Z start build' \
            '2026-06-12T09:00:01Z ===CI_METRICS_JSON_BEGIN==={"job":"build"}===CI_METRICS_JSON_END===' \
            '2026-06-12T09:00:02Z done'
          ;;
        *jobs/11/logs*)
          printf '%s\n' \
            '2026-06-12T09:00:00Z start test' \
            '2026-06-12T09:00:01Z ===CI_METRICS_JSON_BEGIN==={"job":"test-linux"}===CI_METRICS_JSON_END==='
          ;;
        *jobs/14/logs*)
          printf '%s\n' \
            '2026-06-12T09:00:00Z start no-metrics' \
            '2026-06-12T09:00:01Z nothing here'
          ;;
        *jobs/15/logs*)
          return 1
          ;;
        *jobs/16/logs*)
          printf '%s\n' \
            '2026-06-12T09:00:00Z start corrupt' \
            '2026-06-12T09:00:01Z ===CI_METRICS_JSON_BEGIN==={bad json,,,===CI_METRICS_JSON_END==='
          ;;
        *)
          echo "unexpected gh call: $*" >&2
          return 1
          ;;
      esac
    End

    It 'emits name\tjson only for completed siblings whose log carries metrics'
      # Exact-equality also pins emit order.
      expected=$(printf '%s\n' \
        "$(printf 'build\t{"job":"build"}')" \
        "$(printf 'test (linux)\t{"job":"test-linux"}')")
      When call collect_job_metrics
      The status should be success
      The output should equal "$expected"
    End

    It 'skips the in-progress job'
      When call collect_job_metrics
      The status should be success
      The output should not include 'flaky'
    End

    It 'skips the report job itself (name == SELF_JOB)'
      When call collect_job_metrics
      The status should be success
      The output should not include 'report-ci-metrics'
    End

    It 'skips a completed job whose log has no metrics block'
      When call collect_job_metrics
      The status should be success
      The output should not include 'no-metrics-job'
    End

    It 'continues past a job whose log download fails'
      When call collect_job_metrics
      The status should be success
      The output should not include 'boom'
    End

    It 'drops a job whose sentinel block contains malformed JSON'
      When call collect_job_metrics
      The status should be success
      The output should not include 'corrupt'
    End

    It 'also skips matrix-display self jobs prefixed with SELF_JOB'
      Mock gh
        case "$*" in
          *runs/*/jobs*)
            printf '%s\n' '20	report-ci-metrics (1)	completed'
            ;;
          *jobs/20/logs*)
            printf '%s\n' '2026-06-12T09:00:01Z ===CI_METRICS_JSON_BEGIN==={"job":"self-matrix"}===CI_METRICS_JSON_END==='
            ;;
          *)
            return 1
            ;;
        esac
      End
      When call collect_job_metrics
      The status should be success
      The output should equal ''
    End

    It 'returns 0 with empty output when the run has no jobs'
      Mock gh
        case "$*" in
          *runs/*/jobs*) : ;;
          *) return 1 ;;
        esac
      End
      When call collect_job_metrics
      The status should be success
      The output should equal ''
    End
  End

  # schema_version 3 fixtures (one "<name>\t<json>" record each):
  #   build = cache restored+saved, no flags; test = OOM-killed; lint = no disk, throttled.
  J_BUILD='{"schema_version":3,"captured_at":"t","duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":40.0,"throttled_seconds":0.0,"nr_throttled":0,"limit_cores":2.0,"request_cores":1.0,"online_count":4,"avg_utilization":0.32,"throttle_rate":null,"pressure_some_avg10":null,"pressure_some_avg60":null,"pressure_some_avg300":null},"memory":{"peak_bytes":3435973836,"limit_bytes":4294967296,"peak_utilization":0.80,"oom":0,"oom_kill":0}},"net":{"rx_bytes":1073741824,"tx_bytes":209715200,"by_interface":{}},"disk":{"path":"/","total_bytes":32212254720,"used_bytes":6442450944,"available_bytes":null,"utilization":0.20},"cache":[{"key":"maven-abc","cache_hit":true,"restore_key_hit":null,"backend":"s3","size_bytes_restored":471859200,"saved":true,"size_bytes_at_end":492832000}]}'
  J_TEST='{"schema_version":3,"captured_at":"t","duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":10.0,"throttled_seconds":0.0,"nr_throttled":0,"limit_cores":null,"request_cores":1.0,"online_count":4,"avg_utilization":null,"throttle_rate":null,"pressure_some_avg10":null,"pressure_some_avg60":null,"pressure_some_avg300":null},"memory":{"peak_bytes":104857600,"limit_bytes":4294967296,"peak_utilization":0.02,"oom":0,"oom_kill":1}},"net":{"rx_bytes":524288000,"tx_bytes":104857600,"by_interface":{}},"disk":{"path":"/","total_bytes":32212254720,"used_bytes":3221225472,"available_bytes":null,"utilization":0.10},"cache":[{"key":"npm-xyz","cache_hit":true,"restore_key_hit":null,"backend":"gha","size_bytes_restored":104857600,"saved":false,"size_bytes_at_end":null}]}'
  J_LINT='{"schema_version":3,"captured_at":"t","duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":2.0,"throttled_seconds":3.5,"nr_throttled":7,"limit_cores":2.0,"request_cores":1.0,"online_count":4,"avg_utilization":0.01,"throttle_rate":0.05,"pressure_some_avg10":null,"pressure_some_avg60":null,"pressure_some_avg300":null},"memory":{"peak_bytes":52428800,"limit_bytes":4294967296,"peak_utilization":0.01,"oom":0,"oom_kill":0}},"net":{"rx_bytes":0,"tx_bytes":0,"by_interface":{}},"disk":{"path":"/","total_bytes":null,"used_bytes":null,"available_bytes":null,"utilization":null}}'

  Describe 'render_headline()'
    It 'renders correct totals: CPU-seconds, worst peak mem with job, net, cache'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'test' "$J_TEST" 'lint' "$J_LINT")
      When call render_headline "$records"
      The status should be success
      The line 1 of output should equal '**3 jobs** · CPU 52.0 CPU-s · peak mem 3.20 GiB (build) · net 1.49 GiB ↓ / 300.00 MiB ↑ · cache 550.00 MiB restored / 470.00 MiB saved'
    End

    It 'emits a flags line with OOM and throttle counts when present'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'test' "$J_TEST" 'lint' "$J_LINT")
      When call render_headline "$records"
      The status should be success
      The line 2 of output should equal '> ⚠️ 1 job OOM-killed (test) · 1 job CPU-throttled (lint)'
    End

    It 'emits NO flags line when no job has OOM or throttle'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD")
      When call render_headline "$records"
      The status should be success
      The output should not include '⚠️'
      The lines of output should equal 1
    End

    It 'renders the saved-only cache segment when a job saved bytes but restored none'
      # saved>0 with restored==0 -> "cache <N> saved", no "restored" form.
      savedonly='{"schema_version":2,"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":5.0,"throttled_seconds":0.0},"memory":{"peak_bytes":1024,"oom_kill":0}},"net":{"rx_bytes":0,"tx_bytes":0},"disk":{"total_bytes":null,"used_bytes":null},"cache":[{"key":"npm-fresh","cache_hit":false,"backend":"s3","size_bytes_restored":0,"saved":true,"size_bytes_at_end":104857600}]}'
      records=$(printf '%s\t%s\n' 'build' "$savedonly")
      When call render_headline "$records"
      The status should be success
      The line 1 of output should include '· cache 100.00 MiB saved'
      The output should not include 'restored'
    End
  End

  Describe 'render_table()'
    It 'renders one row per job inside a details/summary block'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'test' "$J_TEST" 'lint' "$J_LINT")
      When call render_table "$records"
      The status should be success
      The output should include '<details><summary>Per-job breakdown (3 jobs)</summary>'
      The output should include '| Job |'
      The output should include '| build |'
      The output should include '| test |'
      The output should include '| lint |'
    End

    It 'drops the Disk column when no job has disk data'
      lint2=$(printf '%s' "$J_LINT")
      records=$(printf '%s\t%s\n' 'lint' "$lint2" 'lint-b' "$lint2")
      When call render_table "$records"
      The status should be success
      The output should not include 'Disk'
    End

    It 'keeps the Disk column when at least one job has disk data'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'lint' "$J_LINT")
      When call render_table "$records"
      The status should be success
      The output should include 'Disk'
    End

    It 'shows the Flags column with 🔴 only on the OOM-killed row'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'test' "$J_TEST")
      When call render_table "$records"
      The status should be success
      The output should include 'Flags'
      The output should include '🔴'
    End

    It 'drops the Flags column when no job has any flag'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD")
      When call render_table "$records"
      The status should be success
      The output should not include 'Flags'
      The output should not include '🔴'
      The output should not include '🟡'
    End

    It 'escapes pipe characters in a job name so it cannot inject phantom columns'
      records=$(printf '%s\t%s\n' 'build|x' "$J_BUILD")
      When call render_table "$records"
      The status should be success
      The output should include '| build\|x |'
    End

    It 'neutralizes angle brackets in a job name so it cannot inject HTML/details'
      records=$(printf '%s\t%s\n' 'build</details>' "$J_BUILD")
      When call render_table "$records"
      The status should be success
      The output should include '| build&lt;/details&gt; |'
      The output should not include '| build</details> |'
    End

    It 'shows n/a in the CPU cell when a job lacks CPU data but another has it'
      nocpu='{"schema_version":2,"duration_seconds":null,"cgroup":{"cpu":{"usage_seconds":null,"throttled_seconds":0.0,"nr_throttled":0,"limit_cores":null,"online_count":null,"avg_utilization":null,"throttle_rate":null},"memory":{"peak_bytes":1024,"limit_bytes":null,"peak_utilization":null,"oom":0,"oom_kill":0}},"net":{"rx_bytes":0,"tx_bytes":0,"by_interface":{}},"disk":{"path":"/","total_bytes":null,"used_bytes":null,"available_bytes":null,"utilization":null}}'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'job-x' "$nocpu")
      When call render_table "$records"
      The status should be success
      The output should include 'n/a'
    End
  End

  Describe '_rci_cpu_cell() denominator preference'
    # cores = usage/duration. Denominator: limit -> request -> online_count -> bare. (BUILD-11593)
    It 'uses the cgroup limit when present'
      j='{"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":31.0,"limit_cores":2.0,"avg_utilization":0.25,"request_cores":1.0,"online_count":32}}}'
      When call _rci_cpu_cell "$j"
      The output should equal '0.5 / 2 cores (25%)'
    End

    It 'uses the CPU request (not nproc) when there is no limit — the ARC bug fix'
      j='{"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":4.34,"limit_cores":null,"avg_utilization":null,"request_cores":1.0,"online_count":32}}}'
      When call _rci_cpu_cell "$j"
      The output should equal '0.07 / 1 cores requested (7%)'
    End

    It 'falls back to online_count (available) on WarpBuild when no limit/request'
      j='{"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":31.0,"limit_cores":null,"avg_utilization":null,"request_cores":null,"online_count":8}}}'
      When call _rci_cpu_cell "$j"
      The output should equal '0.5 / 8 cores available (6%)'
    End

    It 'shows bare cores when no denominator is available'
      j='{"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":31.0,"limit_cores":null,"avg_utilization":null,"request_cores":null,"online_count":null}}}'
      When call _rci_cpu_cell "$j"
      The output should equal '0.5 cores'
    End
  End

  Describe 'render_cache_fold()'
    It 'renders a cache block when at least one job has a cache entry'
      records=$(printf '%s\t%s\n' 'build' "$J_BUILD" 'test' "$J_TEST" 'lint' "$J_LINT")
      When call render_cache_fold "$records"
      The status should be success
      The output should include '<details><summary>Cache (2 entries)</summary>'
      The output should include 'maven-abc'
      The output should include 'npm-xyz'
    End

    It 'returns empty string when no job has a cache entry'
      records=$(printf '%s\t%s\n' 'lint' "$J_LINT")
      When call render_cache_fold "$records"
      The status should be success
      The output should equal ''
    End

    It 'escapes pipe characters in a cache key so it cannot inject phantom columns'
      pipekey='{"schema_version":2,"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":1.0,"throttled_seconds":0.0},"memory":{"peak_bytes":1024,"oom_kill":0}},"net":{"rx_bytes":0,"tx_bytes":0},"disk":{"total_bytes":null,"used_bytes":null},"cache":[{"key":"deps|v2","cache_hit":true,"backend":"s3","size_bytes_restored":1024,"saved":false,"size_bytes_at_end":null}]}'
      records=$(printf '%s\t%s\n' 'build' "$pipekey")
      When call render_cache_fold "$records"
      The status should be success
      The output should include 'deps\|v2'
      The output should include '| deps\|v2 | yes | s3 |'
    End

    It 'collapses newlines and neutralizes angle brackets in author-controlled cache cells'
      # jq -r turns JSON \n into a real newline; sanitizer must collapse it and escape <>.
      evilkey='{"schema_version":2,"duration_seconds":62.0,"cgroup":{"cpu":{"usage_seconds":1.0,"throttled_seconds":0.0},"memory":{"peak_bytes":1024,"oom_kill":0}},"net":{"rx_bytes":0,"tx_bytes":0},"disk":{"total_bytes":null,"used_bytes":null},"cache":[{"key":"deps\n</details>","cache_hit":true,"backend":"s3\nevil","size_bytes_restored":1024,"saved":false,"size_bytes_at_end":null}]}'
      records=$(printf '%s\t%s\n' 'build' "$evilkey")
      When call render_cache_fold "$records"
      The status should be success
      The output should include '| deps &lt;/details&gt; | yes | s3 evil |'
      The output should not include '</details></details>'
    End
  End

  Describe 'upsert_comment()'
    export REPO=o/r PR_NUMBER=7

    # gh mock branches on "$*": the LIST/GET stands in for the -q-filtered id output
    # (echoes the matched id or nothing); PATCH/POST are matched by '-X PATCH'/'-X POST'.

    It 'PATCHes the existing comment when a marker comment is found'
      Mock gh
        case "$*" in
          *"-X PATCH"*) echo "PATCHED 999" ;;
          *"-X POST"*)  echo "POSTED" ;;
          # LIST/GET: stand in for the -q jq-filtered output; marker comment id.
          *issues/*/comments*) echo "999" ;;
          *) echo "unexpected gh call: $*" >&2; return 1 ;;
        esac
      End
      When call upsert_comment '<!-- ci-metrics-report -->
hello'
      The status should be success
      The output should include 'PATCHED 999'
      The output should not include 'POSTED'
    End

    It 'POSTs a new comment when no marker comment exists'
      Mock gh
        case "$*" in
          *"-X PATCH"*) echo "PATCHED 999" ;;
          *"-X POST"*)  echo "POSTED" ;;
          # LIST/GET: no marker match -> empty -> id is empty -> create path.
          *issues/*/comments*) : ;;
          *) echo "unexpected gh call: $*" >&2; return 1 ;;
        esac
      End
      When call upsert_comment '<!-- ci-metrics-report -->
hello'
      The status should be success
      The output should include 'POSTED'
      The output should not include 'PATCHED'
    End

    It 'PATCHes only the first marked id when several ids are returned'
      # Two ids returned; head -1 must pick 999, never 1001.
      Mock gh
        case "$*" in
          *comments/1001*) echo "PATCHED 1001" ;;
          *comments/999*)  echo "PATCHED 999" ;;
          *"-X POST"*)     echo "POSTED" ;;
          *issues/*/comments*) printf '%s\n' 999 1001 ;;
          *) echo "unexpected gh call: $*" >&2; return 1 ;;
        esac
      End
      When call upsert_comment '<!-- ci-metrics-report -->
body'
      The status should be success
      The output should include 'PATCHED 999'
      The output should not include 'POSTED'
      The output should not include '1001'
    End
  End

  Describe 'main()'
    # Isolate main()'s orchestration by overriding the lib functions it calls with stubs.

    # shellcheck disable=SC2329  # Stubs are invoked indirectly by main()
    stub_renderers() {
      render_headline()    { echo "HEADLINE"; return 0; }
      render_table()       { echo "TABLE"; return 0; }
      render_cache_fold()  { echo "CACHE"; return 0; }
      upsert_comment()     { local body=$1; echo "UPSERT:$body"; return 0; }
      return 0
    }

    It 'skips with no PR context (PR_NUMBER unset) and never upserts'
      export REPO=o/r RUN_ID=1 SELF_JOB=report-ci-metrics
      unset PR_NUMBER
      # shellcheck disable=SC2329  # Invoked indirectly by main()
      collect_job_metrics() { printf 'build\t{"job":"build"}\n'; return 0; }
      stub_renderers
      When call main
      The status should be success
      The output should include '::notice::'
      The output should not include 'UPSERT:'
    End

    It 'skips when collect returns no metrics and never upserts'
      export REPO=o/r RUN_ID=1 SELF_JOB=report-ci-metrics PR_NUMBER=7
      # shellcheck disable=SC2329  # Invoked indirectly by main()
      collect_job_metrics() { return 0; }
      stub_renderers
      When call main
      The status should be success
      The output should include '::notice::'
      The output should include 'no CI metrics'
      The output should not include 'UPSERT:'
    End

    It 'upserts once with the marker as the FIRST body line when records are present'
      export REPO=o/r RUN_ID=1 SELF_JOB=report-ci-metrics PR_NUMBER=7
      # shellcheck disable=SC2329  # Invoked indirectly by main()
      collect_job_metrics() { printf 'build\t{"job":"build"}\n'; return 0; }
      stub_renderers
      When call main
      The status should be success
      The output should include 'UPSERT:'
      # Marker must lead the body so re-runs update the same comment.
      The line 1 of output should equal 'UPSERT:<!-- ci-metrics-report -->'
      The output should include 'HEADLINE'
      The output should include 'TABLE'
    End
  End
End

Describe 'report-ci-metrics/report-ci-metrics.sh'
  # Run the entry script as a subprocess so kcov attributes its lines.
  It 'skips with status 0 and a notice when there is no PR context'
    export REPO=o/r RUN_ID=1 SELF_JOB=report-ci-metrics
    unset PR_NUMBER
    When run script report-ci-metrics/report-ci-metrics.sh
    The status should be success
    The output should include '::notice::'
    The output should include 'no PR context'
  End
End
