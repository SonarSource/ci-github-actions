#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

Mock mise
  echo "mise $*"
End

export RENOVATE_VERSION="43.257.5"
export NODE_VERSION="24.11.0"
export ARTIFACTORY_URL="https://repox-internal.sonar.build/artifactory"
export ARTIFACTORY_USERNAME="test-user"
export ARTIFACTORY_ACCESS_TOKEN="edge-token"
export REPOX_TOKEN="saas-token"
export RENOVATE_TOKEN="github-token"
export GITHUB_REPOSITORY="my-org/my-repo"
RUNNER_TEMP=$(mktemp -d)
export RUNNER_TEMP

EDGE_REGISTRY="https://repox-internal.sonar.build/artifactory/api/npm/npm/"

Describe 'renovate/renovate.sh'
  It 'does not run main when sourced'
    When run source renovate/renovate.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
  End
End

Include renovate/renovate.sh

Describe 'install_renovate()'
  It 'installs the pinned Renovate version from the selected Repox'
    When call install_renovate
    The status should be success
    The line 1 should equal "Installing renovate@43.257.5 from $EDGE_REGISTRY"
    The line 2 should equal \
      "mise exec node@24.11.0 -- npm install --prefix $RUNNER_TEMP/renovate --no-audit --no-fund renovate@43.257.5"
    The contents of file "$RUNNER_TEMP/renovate.npmrc" should include "registry=$EDGE_REGISTRY"
    The contents of file "$RUNNER_TEMP/renovate.npmrc" should include \
      "//repox-internal.sonar.build/artifactory/api/npm/npm/:_authToken=edge-token"
  End
End

Describe 'export_renovate_config()'
  It 'sets the defaults, the REPOX_TOKEN secret and the reader for Renovate commands'
    When call export_renovate_config
    The status should be success
    The line 1 should equal "Renovate repositories: my-org/my-repo"
    The line 2 should equal "Dependency registry for Renovate commands: $EDGE_REGISTRY"
    The variable RENOVATE_REPOSITORIES should equal "my-org/my-repo"
    The variable RENOVATE_ONBOARDING should equal "false"
    The variable RENOVATE_BINARY_SOURCE should equal "global"
    The variable RENOVATE_SECRETS should equal '{"REPOX_TOKEN":"saas-token"}'
    The variable RENOVATE_CUSTOM_ENV_VARIABLES should include "\"BUN_CONFIG_REGISTRY\":\"$EDGE_REGISTRY\""
    The variable RENOVATE_CUSTOM_ENV_VARIABLES should include '"BUN_CONFIG_TOKEN":"edge-token"'
    The variable RENOVATE_CUSTOM_ENV_VARIABLES should include '"ARTIFACTORY_ACCESS_TOKEN":"edge-token"'
    The variable RENOVATE_CUSTOM_ENV_VARIABLES should include '"ARTIFACTORY_USERNAME":"test-user"'
  End

  It 'keeps values set by the caller'
    export RENOVATE_REPOSITORIES="my-org/other-repo"
    export RENOVATE_ONBOARDING="true"
    export RENOVATE_SECRETS='{"OTHER":"value"}'
    export RENOVATE_CUSTOM_ENV_VARIABLES='{"BUN_CONFIG_TOKEN":"override"}'
    When call export_renovate_config
    The status should be success
    The output should include "Renovate repositories: my-org/other-repo"
    The variable RENOVATE_ONBOARDING should equal "true"
    The variable RENOVATE_SECRETS should equal '{"REPOX_TOKEN":"saas-token","OTHER":"value"}'
    The variable RENOVATE_CUSTOM_ENV_VARIABLES should include '"BUN_CONFIG_TOKEN":"override"'
  End
End

Describe 'main()'
  It 'installs and runs Renovate'
    When run script renovate/renovate.sh
    The status should be success
    The line 1 should equal "::group::Install Renovate"
    The output should include "::endgroup::"
    The output should include "mise exec node@24.11.0 -- $RUNNER_TEMP/renovate/node_modules/.bin/renovate"
  End

  It 'fails without a GitHub token'
    export RENOVATE_TOKEN=""
    When run script renovate/renovate.sh
    The status should be failure
    The error should include "RENOVATE_TOKEN"
  End
End
