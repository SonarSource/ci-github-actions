#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="test-token"
export GITHUB_ENV=/dev/null

Describe '.github/scripts/configure-mise-python-index.sh'
  It 'does not configure the environment when sourced'
    When run source .github/scripts/configure-mise-python-index.sh
    The status should be success
    The lines of output should equal 0
  End
End

Include .github/scripts/configure-mise-python-index.sh

Describe 'configure_mise_python_index()'
  It 'configures mise, uv, and pip to use the authenticated Repox index'
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
    When call configure_mise_python_index
    The status should be success
    The lines of output should equal 2
    The contents of file "$GITHUB_ENV" should include \
      "PIP_INDEX_URL=https://test-user:test-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
    The contents of file "$GITHUB_ENV" should include \
      "UV_DEFAULT_INDEX=https://test-user:test-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
    The contents of file "$GITHUB_ENV" should include \
      "MISE_PIPX_REGISTRY_URL=https://test-user:test-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple/{}/"
  End
End
