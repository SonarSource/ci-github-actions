#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock python
  echo "python $*"
End
Mock poetry
  echo "poetry $*"
End
Mock jf
  echo "jf $*"
End
Mock gh
  echo "gh $*"
End

# Minimal environment variables
export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://dummy.repox"
export ARTIFACTORY_PYPI_REPO="<repox pypi repo>"
export ARTIFACTORY_ACCESS_TOKEN="dummy access token"
export ARTIFACTORY_DEPLOY_REPO="<deploy repo>"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="<deploy token>"
export GITHUB_REPOSITORY="my-org/my-repo"
export DEFAULT_BRANCH="main"
export GITHUB_REF_NAME="any-branch"
export GITHUB_EVENT_NAME="push"
export BUILD_NUMBER="42"
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
#GITHUB_OUTPUT=$(mktemp)
#export GITHUB_OUTPUT

Describe 'build-poetry/build.sh'
  It 'does not run build_poetry() if the script is sourced'
    When run source build-poetry/build.sh
    The status should be success
    The output should equal ""
  End

  It 'runs build_poetry()'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2"
      else
        echo "poetry $*"
      fi
    End
    When run script build-poetry/build.sh
      The status should be success
      The lines of stdout should equal 16
      The line 1 should include "jq"
      The line 2 should include "jq"
      The line 3 should include "python"
      The line 4 should include "python"
      The line 5 should include "poetry"
      The line 6 should include "poetry"
      The line 7 should include "jf"
      The line 8 should include "jf"
      The line 9 should equal "PROJECT: my-repo"
      The line 10 should equal "PULL_REQUEST: false"
      The line 11 should equal "Replacing version 1.2 with 1.2.0.42"
      The line 12 should equal "poetry version 1.2.0.42"
      The line 13 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token dummy access token"
      The line 14 should equal "jf poetry-config --server-id-resolve repox --repo-resolve <repox pypi repo>"
      The line 15 should equal "jf poetry install --build-name=my-repo --build-number=42"
      The line 16 should equal "poetry build"
    End
End

Include build-poetry/build.sh

Describe 'check_tool()'
  It 'reports not installed tool'
    When call check_tool some_tool
    The status should be failure
    The line 1 of error should equal "some_tool is not installed."
  End
End

Describe 'set_build_env()'
  It 'sets the default branch and project name'
    When call set_build_env
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "PULL_REQUEST: false"
    The variable DEFAULT_BRANCH should equal "main"
    The variable PROJECT should equal "my-repo"
    The variable PULL_REQUEST should equal "false"
    The variable PULL_REQUEST_SHA should be undefined
  End

  It 'sets PULL_REQUEST and PULL_REQUEST_SHA for pull requests'
    export GITHUB_EVENT_NAME="pull_request"
    echo '{"number": 123, "pull_request": {"base": {"sha": "abc123"}}}' > "$GITHUB_EVENT_PATH"

    When call set_build_env
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "PULL_REQUEST: 123"
    The variable PULL_REQUEST should equal "123"
    The variable PULL_REQUEST_SHA should equal "abc123"
  End
End

Describe 'set_project_version()'
  It 'appends .0 given version is 1.2 and append BUILD_NUMBER'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2 with 1.2.0.42"
    The variable PROJECT_VERSION should equal "1.2.0.42"
  End

  It 'appends BUILD_NUMBER given version is 1.2.3'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2.3 with 1.2.3.42"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'replaces dev with BUILD_NUMBER given version is 1.2.3.dev'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3.dev"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2.3.dev with 1.2.3.42"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'replaces 41 with BUILD_NUMBER given version is 1.2.3.dev'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3.41"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "WARN: version was truncated to 1.2.3 because it had more than 3 digits"
    The line 2 should equal "Replacing version 1.2.3.41 with 1.2.3.42"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'returns error message if version cannot be retrieved'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "Failed to get version"
        exit 1
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 of error should equal "Could not get version from Poetry project ('poetry version -s')"
    The line 2 of error should equal "Failed to get version"
    The variable PROJECT_VERSION should be undefined
    The status should be failure
  End
End

Describe 'jfrog_poetry_install()'
  export PROJECT="my-repo"
  It 'installs Poetry dependencies using JFrog CLI'
    When call jfrog_poetry_install
    The line 1 should include "jf config add repox"
    The line 2 should include "jf poetry-config"
    The line 3 should include "jf poetry install"
  End
End

Describe 'build_poetry()'
  setup() {
    mkdir -p dist
  }

  cleanup() {
    rm -rf dist
  }
  Before 'setup'
  After 'cleanup'

  Mock check_tool
  End
  Mock set_build_env
  End
  Mock set_project_version
  End
  export PROJECT_VERSION="1.0.0.$BUILD_NUMBER"
  export PROJECT="my-repo"
  Mock jfrog_poetry_install
  End

  It 'builds and publishes when on the default branch (main) and not a PR'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="main"

    When call build_poetry
    The line 1 should equal 'poetry build'
    The line 2 should equal "jf config remove repox"
    The line 3 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token <deploy token>"
    The line 4 should include "/dist"
    The line 5 should equal "jf rt upload ./ <deploy repo>/poetry/1.0.0.42/ --module=poetry:1.0.0.42 --build-name=my-repo --build-number=42"
    # ignore line 6 with popd output
    The line 7 should equal "jf rt build-collect-env my-repo 42"
    The line 8 should include "jf rt build-publish my-repo 42"
    The line 9 should be undefined
    The status should be success
  End

  It 'skips when on a PR and DEPLOY_PULL_REQUEST is not true'
    export PULL_REQUEST="123"
    export GITHUB_REF_NAME="123/merge"

    When call build_poetry
    The output should equal 'poetry build'
    The status should be success
  End

  It 'builds and publishes when on a PR and DEPLOY_PULL_REQUEST is true'
    export PULL_REQUEST="123"
    export GITHUB_REF_NAME="123/merge"
    export DEPLOY_PULL_REQUEST="true"

    When call build_poetry
    The line 1 should equal 'poetry build'
    The line 2 should equal "jf config remove repox"
    The line 3 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token <deploy token>"
    The line 4 should include "/dist"
    The line 5 should equal "jf rt upload ./ <deploy repo>/poetry/1.0.0.42/ --module=poetry:1.0.0.42 --build-name=my-repo --build-number=42"
    # ignore line 6 with popd output
    The line 7 should equal "jf rt build-collect-env my-repo 42"
    The line 8 should include "jf rt build-publish my-repo 42"
    The line 9 should be undefined
    The status should be success
  End
End
