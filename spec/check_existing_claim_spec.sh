#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
export GITHUB_RUN_ID="123456789"
TEMP_DIR="${SHELLSPEC_TMPBASE:-/tmp}"
export BUILD_NUMBER_FILE="${TEMP_DIR}/build_number_existing_claim.txt"

Mock gh
    echo "gh $*"
End

Describe 'check_existing_claim.sh'
  BeforeEach 'rm -f "$BUILD_NUMBER_FILE"'

  It 'should not skip when no existing claim is found for this run'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_none.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      echo ''
    End
    When run script get-build-number/check_existing_claim.sh
    The status should be success
    The output should include "No existing claim found for this workflow run"
    The path "$BUILD_NUMBER_FILE" should not be file
    The contents of file "$GITHUB_OUTPUT" should not include "skip=true"
  End

  It 'should reuse the build number already claimed by this run and set skip=true'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_found.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      echo "refs/build-runs/${GITHUB_RUN_ID}/7"
    End
    When run script get-build-number/check_existing_claim.sh
    The status should be success
    The output should include "Reusing build number 7"
    The path "$BUILD_NUMBER_FILE" should be file
    The contents of file "$BUILD_NUMBER_FILE" should equal "7"
    The contents of file "$GITHUB_OUTPUT" should include "skip=true"
  End

  It 'should deterministically pick the lowest number when multiple entries exist for this run'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_multi.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      printf 'refs/build-runs/%s/9\nrefs/build-runs/%s/8\n' "$GITHUB_RUN_ID" "$GITHUB_RUN_ID"
    End
    When run script get-build-number/check_existing_claim.sh
    The status should be success
    The output should include "Reusing build number 8"
    The contents of file "$BUILD_NUMBER_FILE" should equal "8"
  End

  It 'should fail on an API error while listing existing claims'
    GITHUB_OUTPUT="${TEMP_DIR}/github_output_error.txt"
    export GITHUB_OUTPUT
    : > "$GITHUB_OUTPUT"
    Mock gh
      echo '{"message":"Internal Server Error"}' >&2
      exit 1
    End
    When run script get-build-number/check_existing_claim.sh
    The status should be failure
  End
End
