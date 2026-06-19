#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Mock jf
  echo "jf $*"
End

export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="test-token"
export ARTIFACTORY_PYPI_REPO="sonarsource-pypi"

MESSAGE_CONFIGURING_POETRY="Configuring Poetry to use Artifactory..."

Describe 'config-poetry/poetry_config.sh'
  It 'does not run main when sourced'
    When run source config-poetry/poetry_config.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
  End
End

Include config-poetry/poetry_config.sh

Describe 'configure_poetry_repox()'
  It 'configures JFrog CLI and Poetry authentication'
    When call configure_poetry_repox
    The status should be success
    The line 1 should equal "$MESSAGE_CONFIGURING_POETRY"
    The line 2 should include "jf config add repox"
    The line 3 should include "jf config use repox"
    The line 4 should include "jf poetry-config --global --server-id-resolve repox --repo-resolve sonarsource-pypi"
  End
End

Describe 'main()'
  It 'runs configure_poetry_repox within a GitHub Actions group'
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
    When run script config-poetry/poetry_config.sh
    The status should be success
    The line 1 should equal "::group::Configure Poetry"
    The line 2 should equal "$MESSAGE_CONFIGURING_POETRY"
    The line 3 should include "jf config add repox"
    The line 4 should include "jf config use repox"
    The line 5 should include "jf poetry-config --global"
    The line 6 should equal "::endgroup::"
    The contents of file "$GITHUB_ENV" should include "POETRY_HTTP_BASIC_REPOX_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "POETRY_HTTP_BASIC_REPOX_PASSWORD=test-token"
  End
End

Mock poetry
  echo "poetry $*"
End

export BUILD_NUMBER="42"
export GITHUB_OUTPUT=/dev/null

Include config-poetry/poetry_set_project_version.sh

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
    The variable CURRENT_VERSION should equal "1.2"
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
    The variable CURRENT_VERSION should equal "1.2.3"
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
    The variable CURRENT_VERSION should equal "1.2.3.dev"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'replaces 41 with BUILD_NUMBER given version is 1.2.3.41'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3.41"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 of error should equal "::warning title=Version truncated::Version was truncated to 1.2.3 because it had more than 3 digits"
    The line 1 should equal "Replacing version 1.2.3.41 with 1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3.41"
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
    The line 1 of error should equal "::error title=Invalid project version::Could not get version from Poetry project ('poetry version -s')"
    The line 2 of error should equal "Failed to get version"
    The variable CURRENT_VERSION should be undefined
    The variable PROJECT_VERSION should be undefined
    The status should be failure
  End
End
