#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Sentinels used by the producer hook to wrap its metrics JSON on one line.
BEGIN='===CI_METRICS_JSON_BEGIN==='
END='===CI_METRICS_JSON_END==='

Describe 'report-ci-insights/lib.sh'
  Include report-ci-insights/lib.sh

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
      # Decoy: an earlier line mentions the literal BEGIN sentinel in noise but
      # has NO matching END sentinel. A greedy match spanning lines would grab
      # from the decoy line. Correct line-oriented extraction returns the real JSON.
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
    # Job IDs map to distinct skip/emit paths exercised by the mock below:
    #   10 build           completed   -> log has metrics  -> emitted
    #   11 test (linux)    completed   -> log has metrics  -> emitted
    #   12 flaky           in_progress -> skipped (not completed)
    #   13 report-ci-insights completed -> skipped (name == SELF_JOB)
    #   14 no-metrics-job  completed   -> log lacks sentinel -> skipped
    #   15 boom            completed   -> log download fails -> continue
    export REPO=o/r RUN_ID=123 SELF_JOB=report-ci-insights

    Mock gh
      case "$*" in
        *runs/*/jobs*)
          printf '%s\n' \
            '10	build	completed' \
            '11	test (linux)	completed' \
            '12	flaky	in_progress' \
            '13	report-ci-insights	completed' \
            '14	no-metrics-job	completed' \
            '15	boom	completed'
          ;;
        *jobs/10/logs*)
          # Sentinels are written literally: shellspec Mock bodies do not inherit
          # the spec-level BEGIN/END shell vars, so referencing them would expand
          # to empty and silently strip the sentinels from the fixture.
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
        *)
          echo "unexpected gh call: $*" >&2
          return 1
          ;;
      esac
    End

    It 'emits name\tjson only for completed siblings whose log carries metrics'
      # Exact full-output equality also pins the order (build before test (linux)).
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
      The output should not include 'report-ci-insights'
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

    It 'also skips matrix-display self jobs prefixed with SELF_JOB'
      Mock gh
        case "$*" in
          *runs/*/jobs*)
            printf '%s\n' '20	report-ci-insights (1)	completed'
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
End
