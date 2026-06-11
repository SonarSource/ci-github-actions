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
    The line 4 should include "jf poetry-config --server-id-resolve repox --repo-resolve sonarsource-pypi"
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
    The line 5 should include "jf poetry-config"
    The line 6 should equal "::endgroup::"
    The contents of file "$GITHUB_ENV" should include "POETRY_HTTP_BASIC_REPOX_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "POETRY_HTTP_BASIC_REPOX_PASSWORD=test-token"
  End
End
