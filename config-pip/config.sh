#!/bin/bash
# Config script for pip to use SonarSource Artifactory.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_USERNAME: Username for Artifactory authentication
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
#
# GitHub Actions auto-provided:
# - GITHUB_ENV: Path to GitHub Actions environment file

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${GITHUB_ENV:?}"

configure_pip() {
  echo "Configuring pip to use Artifactory..."

  local repox_host pip_conf_file authenticated_index registry_url

  repox_host="${ARTIFACTORY_URL#https://}"
  repox_host="${repox_host#http://}"
  echo "Repox host: $repox_host"

  pip_conf_file="${HOME}/.pip/pip.conf"
  authenticated_index="https://${ARTIFACTORY_USERNAME}:${ARTIFACTORY_ACCESS_TOKEN}@${repox_host}/api/pypi/sonarsource-pypi/simple"
  registry_url="${authenticated_index}/{}/"

  mkdir -p "${HOME}/.pip"
  cat > "$pip_conf_file" <<EOF
[global]
index-url = ${authenticated_index}
EOF
  echo "Configuration file: ${pip_conf_file}"

  echo "::add-mask::${authenticated_index}"
  echo "::add-mask::${registry_url}"
  {
    echo "PIP_INDEX_URL=${authenticated_index}"
    echo "UV_DEFAULT_INDEX=${authenticated_index}"
    echo "MISE_PIPX_REGISTRY_URL=${registry_url}"
    echo "PIP_CONFIG_FILE=${pip_conf_file}"
  } >> "$GITHUB_ENV"

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
