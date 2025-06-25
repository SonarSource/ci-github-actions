#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
CACHE_FILE="build_number.txt"

Mock gh
    echo "gh $*"
End

Describe 'get_build_number.sh'
  It 'should increment and return the build number'
    Mock gh
      if [[ "$*" =~ "api --method PATCH" ]]; then
        echo "gh $*"
      elif [[ "$*" =~ "properties/values" ]]; then
        echo '42'
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/get_build_number.sh
    The line 1 should include "Fetching build number"
    The line 2 should equal "Current build number from repo: 42"
    The line 3 should include "43"
    The path "$CACHE_FILE" should be file
    The contents of file "$CACHE_FILE" should equal "43"
  End

  It 'should return an error if BUILD_NUMBER is invalid'
    Mock gh
        echo 'notANumber'
    End
    When run script get-build-number/get_build_number.sh
    The status should be failure
    The line 2 should equal "Current build number from repo: notANumber"
    The output should include "Error: Build number 'notANumber'"
  End

  It 'should handle empty build number'
    Mock gh
        echo ''
    End
    When run script get-build-number/get_build_number.sh
    The status should be success
    The line 2 should equal "Current build number from repo: 0"
    # Ignore empty line from second call to gh
    The line 4 should include "1"
  End
End
