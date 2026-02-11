#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"
export GH_TOKEN="test-token"
export CACHE_REF="refs/pull/123/merge"
export GITHUB_HEAD_REF="fix/me/BUILD-1234-my-branch"

Describe "cleanup.sh"
  It "successfully cleans up pull request resources"
    CACHE_KEY_TO_DELETE=$(mktemp)
    export CACHE_KEY_TO_DELETE
    echo "123456789" > "$CACHE_KEY_TO_DELETE"
    ARTIFACT_TO_DELETE=$(mktemp)
    export ARTIFACT_TO_DELETE
    echo "123456789" > "$ARTIFACT_TO_DELETE"
    Mock gh
      if [[ "$*" =~ "cache list" ]]; then
        cat "$CACHE_KEY_TO_DELETE"
      elif [[ "$*" =~ "cache delete" ]]; then
        echo "" > "$CACHE_KEY_TO_DELETE"
      elif [[ "$*" =~ "api".*/repos/.*actions/artifacts.*--paginate ]]; then
        cat "$ARTIFACT_TO_DELETE"
      elif [[ "$*" =~ "api -X DELETE" ]]; then
        echo "" > "$ARTIFACT_TO_DELETE"
      else
        echo "gh $*"
      fi
    End
    When run script pr_cleanup/cleanup.sh
    The status should be success
    The line 1 should equal "::group::Cache Cleanup"
    The line 2 should equal "Fetching list of cache keys on my org/my-repo for refs/pull/123/merge"
    The line 3 should equal "123456789"
    The line 5 should equal "Deleting caches..."
    The line 6 should equal "Deleting cache key: 123456789"
    The line 8 should equal "Fetching list of cache keys after deletion"
    The line 9 should equal ""
    The line 11 should equal "::endgroup::"
    The line 12 should equal "::group::Artifact Cleanup"
    The line 13 should equal "Fetching list of artifacts on my org/my-repo for fix/me/BUILD-1234-my-branch"
    The line 14 should equal "123456789"
    The line 16 should equal "Deleting artifacts..."
    The line 17 should equal "Deleting artifact: 123456789"
    The line 19 should equal "Fetching list of artifacts after deletion"
    The line 20 should equal ""
    The line 21 should equal "::endgroup::"
  End
End
