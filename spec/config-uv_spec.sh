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
export UV_INDEX_NAME="repox"

MESSAGE_CONFIGURING_UV="Configuring uv to use Artifactory via JFrog CLI..."

Describe 'config-uv/uv_config.sh'
  It 'does not run main when sourced'
    When run source config-uv/uv_config.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
  End
End

Include config-uv/uv_config.sh

Describe 'configure_uv_repox()'
  It 'configures JFrog CLI and uv index authentication'
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
    When call configure_uv_repox
    The status should be success
    The line 1 should equal "$MESSAGE_CONFIGURING_UV"
    The line 2 should include "jf config add repox"
    The line 3 should include "jf config use repox"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_REPOX_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_REPOX_PASSWORD=test-token"
    The contents of file "$GITHUB_ENV" should include "UV_KEYRING_PROVIDER=disabled"
  End

  It 'sets UV_CACHE_DIR when provided'
    GITHUB_ENV=$(mktemp)
    UV_CACHE_DIR=$(mktemp -d)
    export GITHUB_ENV UV_CACHE_DIR
    When call configure_uv_repox
    The status should be success
    The line 1 should equal "$MESSAGE_CONFIGURING_UV"
    The contents of file "$GITHUB_ENV" should include "UV_CACHE_DIR=$UV_CACHE_DIR"
    The path "$UV_CACHE_DIR" should be directory
  End

  It 'uppercases custom index names for environment variables'
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
    export UV_INDEX_NAME="pypi-virtual"
    When call configure_uv_repox
    The status should be success
    The line 1 should equal "$MESSAGE_CONFIGURING_UV"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_PYPI_VIRTUAL_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_PYPI_VIRTUAL_PASSWORD=test-token"
  End
End

Describe 'main()'
  It 'runs configure_uv_repox within a GitHub Actions group'
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
    When run script config-uv/uv_config.sh
    The status should be success
    The line 1 should equal "::group::Configure uv"
    The line 2 should equal "$MESSAGE_CONFIGURING_UV"
    The line 3 should include "jf config add repox"
    The line 4 should include "jf config use repox"
    The line 5 should equal "::endgroup::"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_REPOX_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "UV_INDEX_REPOX_PASSWORD=test-token"
    The contents of file "$GITHUB_ENV" should include "UV_KEYRING_PROVIDER=disabled"
  End
End
