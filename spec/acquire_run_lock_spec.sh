#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
export GITHUB_SHA="deadbeefcafef00dfeed"
export GITHUB_RUN_ID="123456789"
export LOCK_POLL_INTERVAL_SECONDS=0
TEMP_DIR="${SHELLSPEC_TMPBASE:-/tmp}"
export BUILD_NUMBER_FILE="${TEMP_DIR}/build_number_run_lock.txt"

Mock gh
    echo "gh $*"
End

remove_build_number_file() {
  rm -f "$BUILD_NUMBER_FILE"
  return 0
}

Describe 'acquire_run_lock.sh'
  BeforeEach 'remove_build_number_file'

  It 'should win the lock and let the caller proceed, without writing a build number file'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_won.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      echo "gh $*"
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be success
    The output should include "Acquired refs/build-run-locks/${GITHUB_RUN_ID}"
    The path "$BUILD_NUMBER_FILE" should not be file
    The contents of file "$GITHUB_OUTPUT" should not include "skip=true"
  End

  It 'should reuse the build number immediately when the lock is already held and a marker already exists'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_immediate.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/${GITHUB_RUN_ID}/7"
      else
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be success
    The output should include "Reusing build number 7"
    The contents of file "$BUILD_NUMBER_FILE" should equal "7"
    The contents of file "$GITHUB_OUTPUT" should include "skip=true"
  End

  It 'should poll until the marker appears, then reuse it'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_poll.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_MARKER_CALLS_FILE"
        if [[ "$count" -lt 3 ]]; then
          echo ''
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/9"
        fi
      else
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be success
    The output should include "Reusing build number 9"
    The contents of file "$BUILD_NUMBER_FILE" should equal "9"
  End

  It 'should tolerate a transient error while polling and retry instead of aborting the wait'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_transient.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls_transient.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_MARKER_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo '{"message":"Internal Server Error"}' >&2
          exit 1
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/11"
        fi
      else
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be success
    The output should include "Reusing build number 11"
    The stderr should include "Internal Server Error"
    The contents of file "$BUILD_NUMBER_FILE" should equal "11"
  End

  It 'should fail after exhausting the wait if no marker ever appears'
    export LOCK_WAIT_MAX_ATTEMPTS=3
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_timeout.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      else
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be failure
    The output should include "::group::Acquire build-number lock for this workflow run"
    The stderr should include "::error title=Build number lock timed out::Waited 3 attempts"
  End

  It 'should fail immediately on an unexpected lock-acquire API error'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_error.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      if [[ "$*" == *"git/refs"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be failure
    The output should include "::group::Acquire build-number lock for this workflow run"
    The stderr should include "::error title=Build number lock failed::"
    The stderr should include "Internal Server Error"
  End

  It 'should fail if a marker ref has an unexpected format'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_malformed.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/${GITHUB_RUN_ID}/notanumber"
      else
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      fi
    End
    When run script get-build-number/acquire_run_lock.sh
    The status should be failure
    The output should include "::group::Acquire build-number lock for this workflow run"
    The stderr should include "::error title=Build number lock failed::Unexpected ref format"
  End
End
