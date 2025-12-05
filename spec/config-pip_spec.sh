#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Set up environment variables
export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="test-token"

Describe 'config-pip/config.sh'
  It 'does not run main when sourced'
    When run source config-pip/config.sh
    The status should be success
    The output should equal ""
  End
End

Include config-pip/config.sh

common_setup() {
  TEST_PIP_DIR=$(mktemp -d)
  export HOME="$TEST_PIP_DIR"

  return 0
}

common_cleanup() {
  [[ -d "$TEST_PIP_DIR" ]] && rm -rf "$TEST_PIP_DIR"

  return 0
}

Describe 'configure_pip()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'creates pip config directory and file'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When call configure_pip
    The status should equal 0
    The line 1 should equal "Configuring pip to use Artifactory..."
    The line 2 should equal "Repox host: repox.jfrog.io"
    The line 3 should equal "✓ pip configuration completed successfully"
    The line 4 should equal "  Configuration file: ${HOME}/.pip/pip.conf"
    The path "${HOME}/.pip" should be directory
    The path "${HOME}/.pip/pip.conf" should be file
  End

  It 'creates correct pip.conf content with /artifactory suffix'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When call configure_pip
    The status should equal 0
    The output should include "Configuring pip to use Artifactory..."
    The output should include "✓ pip configuration completed successfully"
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://test-user:test-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
  End

  It 'creates correct pip.conf content without /artifactory suffix'
    export ARTIFACTORY_URL="https://repox.jfrog.io"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When call configure_pip
    The status should equal 0
    The output should include "Configuring pip to use Artifactory..."
    The output should include "✓ pip configuration completed successfully"
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://test-user:test-token@repox.jfrog.io/api/pypi/sonarsource-pypi/simple"
  End

  It 'strips http:// protocol from URL'
    export ARTIFACTORY_URL="http://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When call configure_pip
    The status should equal 0
    The line 2 should equal "Repox host: repox.jfrog.io"
    The contents of file "${HOME}/.pip/pip.conf" should include "https://test-user:test-token@repox.jfrog.io/api/pypi/sonarsource-pypi/simple"
  End

  It 'handles URL with custom port'
    export ARTIFACTORY_URL="https://repox.jfrog.io:8080/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When call configure_pip
    The status should equal 0
    The line 2 should equal "Repox host: repox.jfrog.io:8080/artifactory"
    The contents of file "${HOME}/.pip/pip.conf" should include "https://test-user:test-token@repox.jfrog.io:8080/artifactory/api/pypi/sonarsource-pypi/simple"
  End
End

Describe 'Environment variable validation'
  It 'fails when ARTIFACTORY_URL is not set'
    unset ARTIFACTORY_URL
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When run script config-pip/config.sh
    The status should be failure
    The stderr should include "ERROR: ARTIFACTORY_URL is required"
  End

  It 'fails when ARTIFACTORY_USERNAME is not set'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    unset ARTIFACTORY_USERNAME
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When run script config-pip/config.sh
    The status should be failure
    The stderr should include "ERROR: ARTIFACTORY_USERNAME is required"
  End

  It 'fails when ARTIFACTORY_ACCESS_TOKEN is not set'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    unset ARTIFACTORY_ACCESS_TOKEN
    When run script config-pip/config.sh
    The status should be failure
    The stderr should include "ERROR: ARTIFACTORY_ACCESS_TOKEN is required"
  End
End

Describe 'main()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'runs configure_pip within a GitHub Actions group'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="test-user"
    export ARTIFACTORY_ACCESS_TOKEN="test-token"
    When run script config-pip/config.sh
    The status should equal 0
    The line 1 should equal "::group::Configure pip"
    The line 2 should equal "Configuring pip to use Artifactory..."
    The line 3 should equal "Repox host: repox.jfrog.io"
    The line 4 should equal "✓ pip configuration completed successfully"
    The line 5 should equal "  Configuration file: ${HOME}/.pip/pip.conf"
    The line 6 should equal "::endgroup::"
  End

  It 'creates valid pip.conf file when executed'
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export ARTIFACTORY_USERNAME="my-user"
    export ARTIFACTORY_ACCESS_TOKEN="my-secret-token"
    When run script config-pip/config.sh
    The status should equal 0
    The output should include "Configure pip"
    The output should include "✓ pip configuration completed successfully"
    The path "${HOME}/.pip/pip.conf" should be file
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://my-user:my-secret-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
  End
End
