#!/bin/bash
# Config script for SonarSource NPM projects.
#
# Required environment variables (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
#
# GitHub Actions auto-provided:
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_ENV: Path to GitHub Actions environment file
#
# Optional user customization:
# - CURRENT_VERSION and PROJECT_VERSION: If both are set, they will be used as-is and no version update will be performed.

set -euo pipefail

PACKAGE_JSON="package.json"

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${BUILD_NUMBER:?}"
: "${GITHUB_OUTPUT:?}" "${GITHUB_ENV:?}"

check_version_format() {
  local version="$1"
  # Check if version follows semantic versioning pattern (X.Y.Z or X.Y.Z-something)
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "WARN: Version '${version}' does not match semantic versioning format (e.g., '1.2.3' or '1.2.3-beta.1')." >&2
  fi
  return 0
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
  if [[ -z "${current_version}" ]] || [[ "${current_version}" == "null" ]]; then
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
      if [[ "${digit_count}" -lt 3 ]]; then
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
  echo "PROJECT_VERSION=$release_version"
  export PROJECT_VERSION="$release_version"
}

main() {
  echo "::group::Set project version"
  check_tool npm --version
  set_project_version
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
