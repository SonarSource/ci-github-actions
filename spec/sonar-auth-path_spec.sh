#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Describe 'SonarQube authentication action path'
  # Execute the real YAML shell blocks: child config actions may remove shared links.
  action_run_block() {
    awk -v step="$2" '
      $0 == "    - name: " step { found = 1; next }
      found && /^      run: \|/ { body = 1; next }
      body && /^        / { print substr($0, 9); next }
      body && /^$/ { print; next }
      body { exit }
    ' "$1"
  }

  auth_action_survives_config_cleanup() (
    local build_action="$1" config_action="$2" repo_root workspace auth_path
    repo_root="$PWD"
    workspace=$(mktemp -d)
    trap 'rm -rf "$workspace"' EXIT
    cd "$workspace" || return 1
    export GITHUB_ACTION_PATH="$repo_root/$build_action"
    export GITHUB_ENV="$workspace/github-env" GITHUB_OUTPUT="$workspace/github-output"
    # Git Bash can materialize directory links as directories on Windows.
    mkdir -p .actions/sonar-auth

    action_run_block "$repo_root/$build_action/action.yml" 'Set local action paths' |
      sed "s|\${{ github.action_path }}|$GITHUB_ACTION_PATH|g" |
      bash -e > /dev/null || return 1
    if [[ "$config_action" != none ]]; then
      action_run_block "$repo_root/$config_action/action.yml" 'Clean up local action symlinks' |
        bash -e || return 1
    fi

    auth_path=$(awk '/- uses: .*sonar-auth/ { print $3; exit }' "$repo_root/$build_action/action.yml")
    [[ -n "$auth_path" && -f "$auth_path/action.yml" ]] || return 1

    case "$build_action" in
      build-npm|build-poetry|build-yarn)
        rm -f .actions/sonar-auth
        mkdir .actions/sonar-auth
        action_run_block "$repo_root/$build_action/action.yml" 'Clean up local action symlinks' |
          bash -e || return 1
        [[ ! -e .actions/sonar-auth ]]
        ;;
    esac
  )

  Parameters
    build-gradle config-gradle
    build-maven config-maven
    build-npm config-npm
    build-poetry config-poetry
    build-yarn none
  End

  It "keeps authentication loadable after $2 cleanup in $1"
    When call auth_action_survives_config_cleanup "$1" "$2"
    The status should be success
  End
End
