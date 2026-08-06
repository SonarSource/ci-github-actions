#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
TEMP_DIR="${SHELLSPEC_TMPBASE:-/tmp}"
export BUILD_NUMBER_FILE="${TEMP_DIR}/build_number.txt"

Mock gh
    echo "gh $*"
End

Describe 'get_build_number.sh'
  It 'should increment and return the build number'
    export GH_GET_CALLS_FILE="${TEMP_DIR}/gh_get_calls_1.txt"
    rm -f "$GH_GET_CALLS_FILE"
    Mock gh
      if [[ "$*" =~ "api --method PATCH" ]]; then
        echo "gh $*"
      elif [[ "$*" =~ "properties/values" ]]; then
        count=$(($(cat "$GH_GET_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_GET_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo '42'
        else
          echo '43'
        fi
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The line 1 should include "Fetching build number"
    The line 2 should equal "Current build number from repo: 42"
    The line 3 should include "43"
    The path "$BUILD_NUMBER_FILE" should be file
    The contents of file "$BUILD_NUMBER_FILE" should equal "43"
  End

  It 'should return an error if BUILD_NUMBER is invalid'
    Mock gh
        echo 'notANumber'
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The line 2 should equal "Current build number from repo: notANumber"
    The stderr should include "::error title=Invalid build number::Build number 'notANumber'"
  End

  It 'should handle empty build number'
    export GH_GET_CALLS_FILE="${TEMP_DIR}/gh_get_calls_3.txt"
    rm -f "$GH_GET_CALLS_FILE"
    Mock gh
      if [[ "$*" =~ "api --method PATCH" ]]; then
        echo "gh $*"
      elif [[ "$*" =~ "properties/values" ]]; then
        count=$(($(cat "$GH_GET_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_GET_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo ''
        else
          echo '1'
        fi
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The line 2 should equal "Current build number from repo: 0"
    # Ignore empty line from second call to gh
    The line 4 should include "1"
  End

  It 'should retry when a concurrent run wins the race, then succeed'
    export GH_GET_CALLS_FILE="${TEMP_DIR}/gh_get_calls_4.txt"
    rm -f "$GH_GET_CALLS_FILE"
    Mock gh
      if [[ "$*" =~ "api --method PATCH" ]]; then
        echo "gh $*"
      elif [[ "$*" =~ "properties/values" ]]; then
        count=$(($(cat "$GH_GET_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_GET_CALLS_FILE"
        case "$count" in
          1) echo '42' ;;  # our initial read
          2) echo '99' ;;  # a concurrent run raced ahead of our write
          3) echo '99' ;;  # our retry read picks up their value
          *) echo '100' ;; # our second write is now confirmed
        esac
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Concurrent update detected (expected 43, found 99)"
    The output should include "Incremented 'build_number' repository property to 100"
    The path "$BUILD_NUMBER_FILE" should be file
    The contents of file "$BUILD_NUMBER_FILE" should equal "100"
  End

  It 'should fail after exhausting retries if the race never resolves'
    export MAX_ATTEMPTS=3
    export GH_GET_CALLS_FILE="${TEMP_DIR}/gh_get_calls_5.txt"
    rm -f "$GH_GET_CALLS_FILE"
    Mock gh
      if [[ "$*" =~ "api --method PATCH" ]]; then
        echo "gh $*"
      elif [[ "$*" =~ "properties/values" ]]; then
        # Every read disagrees with what we just wrote, simulating permanent contention.
        count=$(($(cat "$GH_GET_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_GET_CALLS_FILE"
        echo "$((count * 100))"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "Concurrent update detected"
    The stderr should include "::error title=Build number race::Could not obtain a unique build number after 3 attempts"
  End
End
