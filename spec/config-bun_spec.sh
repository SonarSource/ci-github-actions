#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null
export ARTIFACTORY_URL="https://repox.sonar.build/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="test-token"

EDGE_REGISTRY="https://repox.sonar.build/artifactory/api/npm/npm/"

Describe 'config-bun/bun_config.sh'
  It 'does not run main when sourced'
    When run source config-bun/bun_config.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
  End
End

Include config-bun/bun_config.sh

Describe 'configure_bun_registry()'
  It 'exports the selected registry and its reader token'
    GITHUB_ENV=$(mktemp)
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_ENV GITHUB_OUTPUT
    When call configure_bun_registry
    The status should be success
    The output should equal "Dependency registry: $EDGE_REGISTRY"
    The contents of file "$GITHUB_ENV" should include "BUN_CONFIG_REGISTRY=$EDGE_REGISTRY"
    The contents of file "$GITHUB_ENV" should include "BUN_CONFIG_TOKEN=test-token"
    The contents of file "$GITHUB_ENV" should not include "NPM_CONFIG_REGISTRY"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_USERNAME=test-user"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_ACCESS_TOKEN=test-token"
    The contents of file "$GITHUB_OUTPUT" should equal "registry=$EDGE_REGISTRY"
  End
End

Describe 'main()'
  It 'configures the registry within a GitHub Actions group'
    GITHUB_ENV=$(mktemp)
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_ENV GITHUB_OUTPUT
    When run script config-bun/bun_config.sh
    The status should be success
    The line 1 should equal "::group::Configure Bun"
    The line 2 should equal "Dependency registry: $EDGE_REGISTRY"
    The line 3 should equal "::endgroup::"
  End

  It 'fails without a reader token'
    export ARTIFACTORY_ACCESS_TOKEN=""
    When run script config-bun/bun_config.sh
    The status should be failure
    The error should include "ARTIFACTORY_ACCESS_TOKEN"
  End
End
