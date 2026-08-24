#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
export GITHUB_SHA="deadbeefcafef00dfeed"
export GITHUB_RUN_ID="123456789"
TEMP_DIR="${SHELLSPEC_TMPBASE:-/tmp}"
export BUILD_NUMBER_FILE="${TEMP_DIR}/build_number.txt"

Mock gh
    echo "gh $*"
End

Describe 'get_build_number.sh'
  It 'should claim build number 1 when there are no locks and no legacy build_number property'
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo ''
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The output should include "Claimed build number 1"
    The path "$BUILD_NUMBER_FILE" should be file
    The contents of file "$BUILD_NUMBER_FILE" should equal "1"
  End

  It 'should seed the starting candidate (with a safety gap) from the legacy property when no locks exist yet'
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The output should include "Seeding from legacy build_number property: 42"
    The output should include "Claimed build number 1043"
    The contents of file "$BUILD_NUMBER_FILE" should equal "1043"
  End

  It 'should claim the next number after the highest existing lock, ignoring gaps, without consulting the legacy property'
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        printf 'refs/build-locks/1\nrefs/build-locks/2\nrefs/build-locks/3\nrefs/build-locks/5\n'
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '999'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The output should include "Claimed build number 6"
    The contents of file "$BUILD_NUMBER_FILE" should equal "6"
  End

  It 'should return an error if the legacy build number property is invalid'
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo 'notANumber'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "::group::Claim build number"
    The stderr should include "::error title=Invalid build number::Legacy build_number property 'notANumber'"
  End

  It 'should retry when a concurrent run already claimed the next number, then succeed'
    export GH_REFS_CALLS_FILE="${TEMP_DIR}/gh_refs_calls_retry.txt"
    rm -f "$GH_REFS_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      elif [[ "$*" == *"ref=refs/build-locks/"* ]]; then
        count=$(($(cat "$GH_REFS_CALLS_FILE" 2>/dev/null || echo 0) + 1))
        echo "$count" > "$GH_REFS_CALLS_FILE"
        if [[ "$count" -eq 1 ]]; then
          echo '{"message":"Reference already exists"}' >&2
          exit 1
        else
          echo "gh $*"
        fi
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The output should include "Build number 1043 already claimed; trying 1044"
    The output should include "Claimed build number 1044"
    The path "$BUILD_NUMBER_FILE" should be file
    The contents of file "$BUILD_NUMBER_FILE" should equal "1044"
  End

  It 'should fail after exhausting retries under permanent contention'
    export MAX_ATTEMPTS=3
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      elif [[ "$*" == *"ref=refs/build-locks/"* ]]; then
        echo '{"message":"Reference already exists"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "already claimed"
    The stderr should include "::error title=Build number race::Could not claim a build number after 3 attempts"
  End

  It 'should fail immediately on an unexpected API error, not treat it as a collision'
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      elif [[ "$*" == *"ref=refs/build-locks/"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "Seeding from legacy build_number property: 42"
    The stderr should include "::error title=Build number claim failed::"
    The stderr should include "Internal Server Error"
  End

  It 'should fail if recording the run marker fails, since other jobs/reruns may be waiting on it'
    rm -f "$BUILD_NUMBER_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-locks/"* ]]; then
        echo ''
      elif [[ "$*" == *"properties/values"* ]]; then
        echo '42'
      elif [[ "$*" == *"ref=refs/build-runs/"* ]]; then
        exit 1
      elif [[ "$*" == *"ref=refs/build-locks/"* ]]; then
        echo "gh $*"
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The output should include "Claimed build number 1043"
    The stderr should include "::error title=Build number run-marker not recorded::"
    The path "$BUILD_NUMBER_FILE" should not be file
  End
End
