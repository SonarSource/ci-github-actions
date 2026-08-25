#!/bin/bash
eval "$(shellspec - -c) exit 1"

export GITHUB_REPOSITORY="my org/my-repo"

Describe 'prune_build_run_markers.sh'
  It 'should tolerate a transient failure listing markers, warn, and exit successfully'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo '{"message":"Internal Server Error"}' >&2
        exit 1
      else
        echo "gh $*"
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "::group::Prune obsolete build-runs markers"
    The output should include "::endgroup::"
    The stderr should include "::warning title=Marker pruning skipped::Could not list refs/build-runs/*"
  End

  It 'should report nothing pruned when there are no build-runs markers'
    Mock gh
      echo ''
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 0"
  End

  It 'should keep a marker whose run still exists'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/111/5"
      elif [[ "$*" == *"actions/runs/111"* ]]; then
        echo '{"id":111}'
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 1"
  End

  It 'should delete a marker whose run no longer exists (confirmed 404)'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/111/5"
      elif [[ "$*" == *"actions/runs/111"* ]]; then
        echo "gh: Not Found (HTTP 404)" >&2
        exit 1
      elif [[ "$*" == *"--method DELETE"* ]]; then
        echo "deleted $*" >>"${SHELLSPEC_TMPBASE:-/tmp}/delete_calls.txt"
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    rm -f "${SHELLSPEC_TMPBASE:-/tmp}/delete_calls.txt"
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "Deleted refs/build-runs/111/5"
    The output should include "Pruned 1 obsolete build-runs marker(s); kept 0"
    The path "${SHELLSPEC_TMPBASE:-/tmp}/delete_calls.txt" should be file
  End

  It 'should not delete a marker when the run-status check fails for a reason other than 404'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/111/5"
      elif [[ "$*" == *"actions/runs/111"* ]]; then
        echo "gh: This service is currently unavailable (HTTP 503)" >&2
        exit 1
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The stderr should include "::warning title=Run status check inconclusive::"
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 1"
  End

  It 'should warn but not fail when a confirmed-deletable marker fails to delete'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/111/5"
      elif [[ "$*" == *"actions/runs/111"* ]]; then
        echo "gh: Not Found (HTTP 404)" >&2
        exit 1
      elif [[ "$*" == *"--method DELETE"* ]]; then
        exit 1
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The stderr should include "::warning title=Marker not deleted::"
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 0"
  End

  It 'should ignore refs that do not match the build-runs/<run_id>/<number> shape'
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        echo "refs/build-runs/malformed"
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 0"
  End

  It 'should check only PRUNE_MAX_CHECKS distinct run_ids per invocation, oldest first, and flag the rest as pending'
    export PRUNE_MAX_CHECKS=1
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        printf 'refs/build-runs/200/9\nrefs/build-runs/100/5\n'
      elif [[ "$*" == *"actions/runs/100"* ]]; then
        echo '{"id":100}'
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "kept 1 whose run still exists on GitHub; skipped 1 not checked this invocation"
    The output should include "checked 1 distinct run(s), capped at 1"
    The stderr should include "::notice title=Marker pruning incomplete::1 marker(s) exceeded the 1-per-invocation cap"
    unset PRUNE_MAX_CHECKS
  End

  It 'should check a run_id only once even when it has multiple markers'
    export CHECK_CALLS_FILE="${SHELLSPEC_TMPBASE:-/tmp}/check_calls.txt"
    rm -f "$CHECK_CALLS_FILE"
    Mock gh
      if [[ "$*" == *"matching-refs/build-runs/"* ]]; then
        printf 'refs/build-runs/100/5\nrefs/build-runs/100/6\n'
      elif [[ "$*" == *"actions/runs/100"* ]]; then
        echo "1" >>"$CHECK_CALLS_FILE"
        echo '{"id":100}'
      else
        echo "gh $*" >&2
        exit 1
      fi
    End
    When run script get-build-number/prune_build_run_markers.sh
    The status should be success
    The output should include "Pruned 0 obsolete build-runs marker(s); kept 2"
    The contents of file "$CHECK_CALLS_FILE" should equal "1"
    unset CHECK_CALLS_FILE
  End
End
