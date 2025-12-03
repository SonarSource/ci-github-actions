#!/bin/bash
# Config script for pip to use SonarSource Artifactory.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_USERNAME: Username for Artifactory authentication
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
#
# GitHub Actions auto-provided:
# - GITHUB_REPOSITORY: Repository name in format "owner/repo"

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"

configure_pip() {
  echo "Configuring pip to use Artifactory..."

  # Extract the host from ARTIFACTORY_URL
  local repox_host="${ARTIFACTORY_URL#https://}"
  repox_host="${repox_host#http://}"
  echo "Repox host: $repox_host"

  mkdir -p "$HOME/.pip"
  cat > "${HOME}/.pip/pip.conf" <<EOF
[global]
index-url = https://${ARTIFACTORY_USERNAME}:${ARTIFACTORY_ACCESS_TOKEN}@$repox_host/api/pypi/sonarsource-pypi/simple
EOF
  echo "Configuration file: ${HOME}/.pip/pip.conf"
  return 0
}

main() {
  echo "::group::Configure pip"
  configure_pip
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
