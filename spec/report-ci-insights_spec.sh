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
End
