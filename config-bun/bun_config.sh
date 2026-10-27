#!/bin/bash
# Config script for Bun to resolve npm packages from SonarSource Artifactory.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_USERNAME: Username for Artifactory authentication
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
#
# GitHub Actions auto-provided:
# - GITHUB_ENV: Path to GitHub Actions environment file
# - GITHUB_OUTPUT: Path to GitHub Actions output file

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${GITHUB_ENV:?}" "${GITHUB_OUTPUT:?}"

configure_bun_registry() {
  local registry="${ARTIFACTORY_URL}/api/npm/npm/"

  {
    echo "BUN_CONFIG_REGISTRY=$registry"
    echo "BUN_CONFIG_TOKEN=$ARTIFACTORY_ACCESS_TOKEN"
    echo "ARTIFACTORY_USERNAME=$ARTIFACTORY_USERNAME"
    echo "ARTIFACTORY_ACCESS_TOKEN=$ARTIFACTORY_ACCESS_TOKEN"
  } >> "$GITHUB_ENV"
  echo "registry=$registry" >> "$GITHUB_OUTPUT"
  echo "Dependency registry: $registry"
  return 0
}

main() {
  echo "::group::Configure Bun"
  configure_bun_registry
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
