#!/bin/bash
# Config script for uv to use SonarSource Artifactory via JFrog CLI.
#
# There is no `jf uv-config` command. Configure `jf config` and declare
# `[[tool.uv.index]]` entries in pyproject.toml, then run `jf uv` subcommands.
# See https://docs.jfrog.com/artifactory/docs/jf-uv
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_USERNAME: Username for Artifactory authentication
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - UV_INDEX_NAME: Name of the uv index in pyproject.toml (e.g. repox)
#
# Optional environment variables:
# - UV_CACHE_DIR: Path to the uv cache directory
#
# GitHub Actions auto-provided:
# - GITHUB_ENV: Path to GitHub Actions environment file

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${UV_INDEX_NAME:?}" "${GITHUB_ENV:?}"

uv_index_env_suffix() {
  local index_name_upper

  index_name_upper=$(echo "$UV_INDEX_NAME" | tr '[:lower:]' '[:upper:]')
  index_name_upper=$(echo "$index_name_upper" | tr -c 'A-Za-z0-9' '_' | sed 's/_*$//')
  echo "$index_name_upper"
}

configure_uv_repox() {
  local index_name_upper

  echo "Configuring uv to use Artifactory via JFrog CLI..."

  jf config remove repox > /dev/null 2>&1 || true # Ignore nonexistent configuration
  jf config add repox --url "${ARTIFACTORY_URL%/artifactory*}" --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox

  index_name_upper=$(uv_index_env_suffix)

  # Native uv variables for named indexes. Also set explicitly so plain `uv` works;
  # `jf uv` injects the same variables when they are unset.
  {
    echo "UV_INDEX_${index_name_upper}_USERNAME=$ARTIFACTORY_USERNAME"
    echo "UV_INDEX_${index_name_upper}_PASSWORD=$ARTIFACTORY_ACCESS_TOKEN"
    echo "UV_KEYRING_PROVIDER=disabled"
  } >> "$GITHUB_ENV"

  if [[ -n "${UV_CACHE_DIR:-}" ]]; then
    echo "UV_CACHE_DIR=$UV_CACHE_DIR" >> "$GITHUB_ENV"
    mkdir -p "$UV_CACHE_DIR"
  fi

  return 0
}

main() {
  echo "::group::Configure uv"
  configure_uv_repox
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
