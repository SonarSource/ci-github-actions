#!/bin/bash
# Run self-hosted Renovate on the current repository.
#
# Renovate is installed with npm from the selected Repox, and the commands it runs (lockfile updates, post-upgrade tasks)
# get the selected Repox reader through customEnvVariables.
#
# Required environment variables (must be explicitly provided):
# - RENOVATE_VERSION: Version of the renovate npm package
# - NODE_VERSION: Node.js version used to run Renovate
# - ARTIFACTORY_URL: URL to the selected Artifactory
# - ARTIFACTORY_USERNAME: Reader username for the selected Artifactory
# - ARTIFACTORY_ACCESS_TOKEN: Reader access token for the selected Artifactory
# - REPOX_TOKEN: SaaS Repox reader access token, exposed as the REPOX_TOKEN Renovate secret
# - RENOVATE_TOKEN: GitHub token used by Renovate
#
# Optional environment variables:
# - RENOVATE_SECRETS, RENOVATE_CUSTOM_ENV_VARIABLES: JSON objects merged with the values set by this script
# - Any other RENOVATE_* variable or LOG_LEVEL is passed to Renovate unchanged
#
# GitHub Actions auto-provided:
# - GITHUB_REPOSITORY: Repository processed when RENOVATE_REPOSITORIES is not set
# - RUNNER_TEMP: Directory where Renovate is installed

set -euo pipefail

: "${RENOVATE_VERSION:?}" "${NODE_VERSION:?}" "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"
: "${REPOX_TOKEN:?}" "${RENOVATE_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"

install_renovate() {
  local registry="${ARTIFACTORY_URL}/api/npm/npm/"
  RENOVATE_PREFIX="$RUNNER_TEMP/renovate"
  NPM_CONFIG_USERCONFIG="$RUNNER_TEMP/renovate.npmrc"
  export NPM_CONFIG_USERCONFIG
  {
    echo "registry=$registry"
    echo "//${registry#https://}:_authToken=$ARTIFACTORY_ACCESS_TOKEN"
  } > "$NPM_CONFIG_USERCONFIG"
  echo "Installing renovate@$RENOVATE_VERSION from $registry"
  mise exec "node@$NODE_VERSION" -- npm install --prefix "$RENOVATE_PREFIX" --no-audit --no-fund "renovate@$RENOVATE_VERSION"
  return 0
}

export_renovate_config() {
  local registry="${ARTIFACTORY_URL}/api/npm/npm/"
  export RENOVATE_REPOSITORIES="${RENOVATE_REPOSITORIES:-$GITHUB_REPOSITORY}"
  export RENOVATE_ONBOARDING="${RENOVATE_ONBOARDING:-false}"
  export RENOVATE_BINARY_SOURCE="${RENOVATE_BINARY_SOURCE:-global}"
  RENOVATE_SECRETS=$(jq -cn --arg token "$REPOX_TOKEN" --argjson extra "${RENOVATE_SECRETS:-"{}"}" \
    '{REPOX_TOKEN: $token} + $extra')
  RENOVATE_CUSTOM_ENV_VARIABLES=$(jq -cn --arg url "$ARTIFACTORY_URL" --arg registry "$registry" \
    --arg username "$ARTIFACTORY_USERNAME" --arg token "$ARTIFACTORY_ACCESS_TOKEN" \
    --argjson extra "${RENOVATE_CUSTOM_ENV_VARIABLES:-"{}"}" \
    '{ARTIFACTORY_URL: $url, ARTIFACTORY_USERNAME: $username, ARTIFACTORY_ACCESS_TOKEN: $token,
      BUN_CONFIG_REGISTRY: $registry, BUN_CONFIG_TOKEN: $token} + $extra')
  export RENOVATE_SECRETS RENOVATE_CUSTOM_ENV_VARIABLES
  echo "Renovate repositories: $RENOVATE_REPOSITORIES"
  echo "Dependency registry for Renovate commands: $registry"
  return 0
}

main() {
  echo "::group::Install Renovate"
  install_renovate
  echo "::endgroup::"
  export_renovate_config
  mise exec "node@$NODE_VERSION" -- "$RENOVATE_PREFIX/node_modules/.bin/renovate"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
