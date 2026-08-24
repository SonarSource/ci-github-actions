#!/usr/bin/env bash

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${GITHUB_ENV:?}"

configure_mise_python_index() {
  local authenticated_index registry_url

  authenticated_index="${ARTIFACTORY_URL%/}/api/pypi/sonarsource-pypi/simple"
  authenticated_index="https://${ARTIFACTORY_USERNAME}:${ARTIFACTORY_ACCESS_TOKEN}@${authenticated_index#https://}"
  registry_url="${authenticated_index%/}/{}/"

  echo "::add-mask::${authenticated_index}"
  echo "::add-mask::${registry_url}"
  {
    echo "PIP_INDEX_URL=${authenticated_index}"
    echo "UV_DEFAULT_INDEX=${authenticated_index}"
    echo "MISE_PIPX_REGISTRY_URL=${registry_url}"
  } >> "$GITHUB_ENV"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  configure_mise_python_index
fi
