#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Describe 'SonarQube authentication input'
  validate_secretless() {
    local script
    script=$(awk '
      /- name: Validate secretless input/ { found = 1; next }
      found && /^      run: \|/ { body = 1; next }
      body && /^        / { print substr($0, 9); next }
      body { exit }
    ' shared/sonar-auth/action.yml)
    [[ -n "$script" ]] || { echo 'Missing input validation' >&2; return 1; }
    SECRETLESS="$1" bash -e -c "$script"
  }

  Describe 'boolean values'
    Parameters
      true
      false
    End

    It "accepts the boolean string $1"
      When call validate_secretless "$1"
      The status should be success
    End
  End

  Describe 'invalid values'
    Parameters
      # ShellSpec parameter, not a command.
      # shellcheck disable=SC2286
      ''
      yes
      FALSE
    End

    It "rejects '$1' before authentication"
      When call validate_secretless "$1"
      The status should be failure
      The stderr should include 'secretless must be true or false'
    End
  End
End
