#!/bin/bash
# Config script for Poetry to use SonarSource Artifactory via JFrog CLI.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_USERNAME: Username for Artifactory authentication
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - ARTIFACTORY_PYPI_REPO: PyPI virtual repository to resolve dependencies from
#
# GitHub Actions auto-provided:
# - GITHUB_ENV: Path to GitHub Actions environment file

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_PYPI_REPO:?}" "${GITHUB_ENV:?}"

configure_poetry_repox() {
  echo "Configuring Poetry to use Artifactory..."

  jf config remove repox > /dev/null 2>&1 || true # Ignore inexistent configuration
  jf config add repox --url "${ARTIFACTORY_URL%/artifactory*}" --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox
  jf poetry-config --server-id-resolve repox --repo-resolve "$ARTIFACTORY_PYPI_REPO"

  {
    echo "POETRY_HTTP_BASIC_REPOX_USERNAME=$ARTIFACTORY_USERNAME"
    echo "POETRY_HTTP_BASIC_REPOX_PASSWORD=$ARTIFACTORY_ACCESS_TOKEN"
  } >> "$GITHUB_ENV"

  return 0
}

main() {
  echo "::group::Configure Poetry"
  configure_poetry_repox
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
