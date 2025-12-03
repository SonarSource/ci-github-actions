#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Set up environment variables
export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="test-token"

# Expected output messages
MESSAGE_CONFIGURING_PIP="Configuring pip to use Artifactory..."
MESSAGE_REPOX_HOST="Repox host: repox.jfrog.io/artifactory"

Describe 'config-pip/config.sh'
  It 'does not run main when sourced'
    When run source config-pip/config.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
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

  It 'creates pip config directory, file and correct content'
    When call configure_pip
    The status should be success
    The lines of output should equal 3
    The lines of error should equal 0
    The line 1 should equal "$MESSAGE_CONFIGURING_PIP"
    The line 2 should equal "$MESSAGE_REPOX_HOST"
    The line 3 should start with "Configuration file: "
    The line 3 should end with "/.pip/pip.conf"
    The path "${HOME}/.pip" should be directory
    The path "${HOME}/.pip/pip.conf" should be file
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://test-user:test-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
  End

  It 'handles URL with custom port'
    export ARTIFACTORY_URL="https://repox.jfrog.io:8080/artifactory"
    When call configure_pip
    The status should be success
    The lines of output should equal 3
    The lines of error should equal 0
    The line 1 should equal "$MESSAGE_CONFIGURING_PIP"
    The line 2 should equal "Repox host: repox.jfrog.io:8080/artifactory"
    The line 3 should start with "Configuration file: "
    The line 3 should end with "/.pip/pip.conf"
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://test-user:test-token@repox.jfrog.io:8080/artifactory/api/pypi/sonarsource-pypi/simple"
  End
End

Describe 'main()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'runs configure_pip within a GitHub Actions group and creates valid pip.conf'
    export ARTIFACTORY_USERNAME="my-user"
    export ARTIFACTORY_ACCESS_TOKEN="my-secret-token"
    When run script config-pip/config.sh
    The status should be success
    The lines of output should equal 5
    The lines of error should equal 0
    The line 1 should equal "::group::Configure pip"
    The line 2 should equal "$MESSAGE_CONFIGURING_PIP"
    The line 3 should equal "$MESSAGE_REPOX_HOST"
    The line 4 should start with "Configuration file: "
    The line 4 should end with "/.pip/pip.conf"
    The line 5 should equal "::endgroup::"
    The path "${HOME}/.pip/pip.conf" should be file
    The contents of file "${HOME}/.pip/pip.conf" should equal "[global]
index-url = https://my-user:my-secret-token@repox.jfrog.io/artifactory/api/pypi/sonarsource-pypi/simple"
  End
End
