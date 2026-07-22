#!/bin/bash
# Set Poetry project version using BUILD_NUMBER.
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

: "${BUILD_NUMBER:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_ENV:?}"

set_project_version() {
  local current_version release_version digit_count

  if [[ -n "${CURRENT_VERSION:-}" && -n "${PROJECT_VERSION:-}" ]]; then
    echo "Using provided CURRENT_VERSION $CURRENT_VERSION and PROJECT_VERSION $PROJECT_VERSION without changes."
    echo "current-version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "project-version=$PROJECT_VERSION" >> "$GITHUB_OUTPUT"
    return 0
  fi

  if ! current_version=$(poetry version -s); then
    echo "::error title=Invalid project version::Could not get version from Poetry project ('poetry version -s')" >&2
    echo "$current_version" >&2
    return 1
  fi
  echo "current-version=$current_version" >> "$GITHUB_OUTPUT"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"
  export CURRENT_VERSION=$current_version

  release_version=${current_version%".dev"*}
  digit_count=$(echo "${release_version//./ }" | wc -w)
  if [[ "$digit_count" -lt 3 ]]; then
    release_version="$release_version.0"
  fi
  if [[ "$digit_count" -gt 3 && $release_version =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    release_version="${BASH_REMATCH[0]}"
    echo "::warning title=Version truncated::Version was truncated to $release_version because it had more than 3 digits" >&2
  fi
  release_version="$release_version.${BUILD_NUMBER}"

  echo "Replacing version $current_version with $release_version"
  poetry version "$release_version"
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
  echo "PROJECT_VERSION=$release_version"
  export PROJECT_VERSION=$release_version
}

main() {
  echo "::group::Set project version"
  set_project_version
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
