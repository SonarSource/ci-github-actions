#!/bin/bash
# Config script for SonarSource NPM projects.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - BUILD_NUMBER: Build number for versioning
#
# GitHub Actions auto-provided:
# - GITHUB_REPOSITORY: Repository name in format "owner/repo"
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_ENV: Path to GitHub Actions environment file
#
# Optional user customization:
# - CURRENT_VERSION and PROJECT_VERSION: If both are set, they will be used as-is and no version update will be performed.

set -euo pipefail

PACKAGE_JSON="package.json"

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"
: "${BUILD_NUMBER:?}"
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_ENV:?}"

set_build_env() {
  echo "Configuring JFrog and NPM repositories..."
  npm config set registry "$ARTIFACTORY_URL/api/npm/npm"
  npm config set "${ARTIFACTORY_URL//https:}/api/npm/:_authToken=$ARTIFACTORY_ACCESS_TOKEN"
  jf config remove repox > /dev/null 2>&1 || true # Ignore inexistent configuration
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox
  jf npm-config --repo-resolve "npm"
}

check_version_format() {
  local version="$1"
  # Check if version follows semantic versioning pattern (X.Y.Z or X.Y.Z-something)
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "WARN: Version '${version}' does not match semantic versioning format (e.g., '1.2.3' or '1.2.3-beta.1')." >&2
  fi
}

set_project_version() {
  echo "Setting project version..."
  if [[ -n "${CURRENT_VERSION:-}" && -n "${PROJECT_VERSION:-}" ]]; then
    echo "Using provided CURRENT_VERSION $CURRENT_VERSION and PROJECT_VERSION $PROJECT_VERSION without changes."
    echo "current-version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "project-version=$PROJECT_VERSION" >> "$GITHUB_OUTPUT"
    return 0
  fi

  local current_version release_version digit_count
  current_version=$(jq -r .version "$PACKAGE_JSON")
  if [ -z "${current_version}" ] || [ "${current_version}" == "null" ]; then
    echo "Could not get version from ${PACKAGE_JSON}" >&2
    exit 1
  fi
  echo "current-version=$current_version" >> "$GITHUB_OUTPUT"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"
  echo "CURRENT_VERSION=${current_version} (from ${PACKAGE_JSON})"
  export CURRENT_VERSION="$current_version"

  release_version="${current_version}"
  if ! is_pull_request; then
    if is_maintenance_branch && [[ ! ${current_version} =~ "-SNAPSHOT" ]]; then
      echo "Found RELEASE version on maintenance branch, skipping version update."
    else
      release_version="${current_version%"-SNAPSHOT"}"
      digit_count=$(echo "${release_version//./ }" | wc -w)
      if [ "${digit_count}" -lt 3 ]; then
          release_version="${release_version}.0"
      fi
      release_version="${release_version}-${BUILD_NUMBER}"
      echo "Replacing version ${current_version} with ${release_version}"
      npm version --no-git-tag-version --allow-same-version "${release_version}"
    fi
  fi
  check_version_format "${release_version}"
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
  echo "PROJECT_VERSION=${release_version}"
  export PROJECT_VERSION="$release_version"
}

main() {
  echo "::group::Check tools"
  check_tool jq --version
  check_tool jf --version
  check_tool npm --version
  echo "::endgroup::"
  echo "::group::Setup build environment"
  set_build_env
  echo "::endgroup::"
  echo "::group::Set project version"
  set_project_version
  echo "::endgroup::"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
