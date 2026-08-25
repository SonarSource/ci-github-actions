#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
export GITHUB_SHA="deadbeefcafef00dfeed"
export GITHUB_RUN_ID="123456789"
export LOCK_POLL_INTERVAL_SECONDS=0
export RETRY_INTERVAL_SECONDS=0
TEMP_DIR="${SHELLSPEC_TMPBASE:-/tmp}"
export BUILD_NUMBER_FILE="${TEMP_DIR}/build_number.txt"

Mock gh
    echo "gh $*"
End

remove_build_number_file() {
  rm -f "$BUILD_NUMBER_FILE"
  return 0
}

Describe 'get_build_number.sh'
  BeforeEach 'remove_build_number_file'

  It 'should reuse an existing claim immediately, without touching the lock or scanning build-number refs'
    export GH_LOCK_CALLS_FILE="${TEMP_DIR}/gh_lock_calls_reuse.txt"
    rm -f "$GH_LOCK_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/${GITHUB_RUN_ID}/5"
      elif [[ "$*" == *"build-number-lock"* ]]; then
        echo "1" >>"$GH_LOCK_CALLS_FILE"
        echo "gh $*"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Reusing build number 5"
    The contents of file "$BUILD_NUMBER_FILE" should equal "5"
    The path "$GH_LOCK_CALLS_FILE" should not be file
  End

  It 'should claim build number 1 and warn when there are no build-number refs and no migration token'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Claimed build number 1"
    The output should not include "checking the legacy build_number property"
    The stderr should include "::warning title=Legacy build number not checked::"
    The contents of file "$BUILD_NUMBER_FILE" should equal "1"
  End

  It 'should seed the starting candidate (with a safety buffer) from the legacy property when no build-number refs exist yet'
    export LEGACY_PROPERTY_TOKEN="vault-issued-token-placeholder"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Seeding from legacy build_number property: 42"
    The output should include "Claimed build number 1043"
    The contents of file "$BUILD_NUMBER_FILE" should equal "1043"
  End

  It 'should return an error if the legacy build number property is invalid'
    export LEGACY_PROPERTY_TOKEN="vault-issued-token-placeholder"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo 'notANumber'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Invalid build number::Legacy build_number property 'notANumber'"
  End

  It 'should claim the next number after the highest existing build-number ref, ignoring gaps, and delete the superseded ones'
    export GH_DELETE_CALLS_FILE="${TEMP_DIR}/gh_delete_calls_number.txt"
    rm -f "$GH_DELETE_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        printf 'refs/build-number/1\nrefs/build-number/2\nrefs/build-number/3\nrefs/build-number/5\n'
      elif [[ "$*" == *"--method DELETE"* && "$*" == *"build-number/"* ]]; then
        echo "$*" >>"$GH_DELETE_CALLS_FILE"
        echo "gh $*"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Claimed build number 6"
    The contents of file "$BUILD_NUMBER_FILE" should equal "6"
    The contents of file "$GH_DELETE_CALLS_FILE" should include "build-number/1"
    The contents of file "$GH_DELETE_CALLS_FILE" should include "build-number/2"
    The contents of file "$GH_DELETE_CALLS_FILE" should include "build-number/3"
    The contents of file "$GH_DELETE_CALLS_FILE" should include "build-number/5"
  End

  It 'should warn but still succeed when a superseded build-number ref fails to delete'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo 'refs/build-number/5'
      elif [[ "$*" == *"--method DELETE"* && "$*" == *"build-number/5"* ]]; then
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Claimed build number 6"
    The stderr should include "::warning title=Stale build number ref not deleted::Failed to delete refs/build-number/5"
    The contents of file "$BUILD_NUMBER_FILE" should equal "6"
  End

  It 'should fail immediately if the candidate build-number ref unexpectedly already exists while holding the lock'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number/1"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "refs/build-number/1 already exists, which should be impossible while holding refs/build-number-lock"
  End

  It 'should fail immediately on an unexpected API error while claiming, not treat it as a collision'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number/"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Build number claim failed::"
    The stderr should include "Internal Server Error"
  End

  It 'should call out the contents:write permission requirement when the API denies access'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number/"* ]]; then
        echo '{"message":"Resource not accessible by integration"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "Resource not accessible by integration"
    The stderr should include "requires 'contents: write'"
  End

  It 'should fail if recording the run marker fails, since other jobs/reruns may be waiting on it'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-runs/"* ]]; then
        exit 1
      elif [[ "$*" == *"ref=refs/build-number/"* ]]; then
        echo "gh $*"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "Claimed build number 1"
    The stderr should include "::error title=Build number claim failed::Failed to record"
    The path "$BUILD_NUMBER_FILE" should not be file
  End

  It 'should release the lock even when the claim ultimately fails'
    export GH_UNLOCK_CALLS_FILE="${TEMP_DIR}/gh_unlock_calls_failure.txt"
    rm -f "$GH_UNLOCK_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number/"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      elif [[ "$*" == *"--method DELETE"* && "$*" == *"build-number-lock"* ]]; then
        echo "1" >>"$GH_UNLOCK_CALLS_FILE"
        echo "gh $*"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Build number claim failed::"
    The path "$GH_UNLOCK_CALLS_FILE" should be file
  End

  It 'should wait for the lock holder to publish a marker, then reuse it'
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls_poll.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" >"$GH_MARKER_CALLS_FILE"
        if [[ "$count" -lt 3 ]]; then
          echo ''
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/9"
        fi
      elif [[ "$*" == *"ref=refs/build-number-lock"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Reusing build number 9"
    The contents of file "$BUILD_NUMBER_FILE" should equal "9"
  End

  It 'should silently absorb a single transient error checking the marker via its internal retry'
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls_transient.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" >"$GH_MARKER_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo '{"message":"Internal Server Error"}' >&2
          exit 1
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/11"
        fi
      elif [[ "$*" == *"ref=refs/build-number-lock"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Reusing build number 11"
    The stderr should not include "Marker check inconclusive"
    The contents of file "$BUILD_NUMBER_FILE" should equal "11"
  End

  It 'should warn once its internal retry is exhausted, then succeed reusing the marker found on the next poll'
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls_inconclusive.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" >"$GH_MARKER_CALLS_FILE"
        if [[ "$count" -le 2 ]]; then
          echo '{"message":"Internal Server Error"}' >&2
          exit 1
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/12"
        fi
      elif [[ "$*" == *"ref=refs/build-number-lock"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Reusing build number 12"
    The stderr should include "::warning title=Marker check inconclusive::"
    The contents of file "$BUILD_NUMBER_FILE" should equal "12"
  End

  It 'should fail after exhausting the wait if the lock holder never publishes a marker'
    export LOCK_WAIT_MAX_ATTEMPTS=3
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number-lock"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Build number claim timed out::Waited 3 attempts"
  End

  It 'should fail immediately on an unexpected error acquiring the lock, not treat it as a collision'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo ''
      elif [[ "$*" == *"ref=refs/build-number-lock"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Build number claim failed::"
    The stderr should include "Internal Server Error"
  End

  It 'should reuse the marker if it appears between winning the lock and scanning build-number refs'
    export GH_MARKER_CALLS_FILE="${TEMP_DIR}/gh_marker_calls_race.txt"
    rm -f "$GH_MARKER_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        count=$(($(cat "$GH_MARKER_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" >"$GH_MARKER_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo ''
        else
          echo "refs/build-runs/${GITHUB_RUN_ID}/13"
        fi
      elif [[ "$*" == *"matching-refs/build-number/"* ]]; then
        echo "::error title=test-bug::build-number should never be scanned in this scenario" >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Reusing build number 13"
    The contents of file "$BUILD_NUMBER_FILE" should equal "13"
  End

  It 'should fail if a marker ref has an unexpected format'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/${GITHUB_RUN_ID}/notanumber"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Get build number"
    The stderr should include "::error title=Build number claim failed::Unexpected ref format"
  End
End
