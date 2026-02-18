#!/bin/bash
# Config script for SonarSource Maven projects.
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

: "${BUILD_NUMBER:?}"
: "${GITHUB_OUTPUT:?}" "${GITHUB_ENV:?}" "${SKIP:=false}"

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

set_gradle_cmd() {
  if [[ -f "./gradlew" ]]; then
    check_tool ./gradlew --version
    export GRADLE_CMD="./gradlew"
  elif check_tool gradle --version; then
    export GRADLE_CMD="gradle"
  else
    echo "Neither ./gradlew nor gradle command found!" >&2
    exit 1
  fi
}

set_project_version() {
  local current_version
  GRADLE_CMD_PARAMS=("properties" "--no-scan" "--no-daemon" "--console" "plain")
  if ! current_version=$($GRADLE_CMD "${GRADLE_CMD_PARAMS[@]}" |grep 'version:' | cut -d ":" -f 2 | tr -d "[:space:]") || \
      [[ -z "$current_version" || "$current_version" == "unspecified" ]]; then
    current_version=$($GRADLE_CMD properties --no-scan --no-daemon --console plain 2>&1 || true)
    echo -e "::error title=Gradle project version::Could not get valid version from Gradle properties\nERROR: $current_version"
    return 1
  fi

  # Saving the snapshot version to the output and environment variables
  # This is used by the sonar-scanner to set the value of sonar.projectVersion without the build number
  echo "current-version=$current_version" >> "$GITHUB_OUTPUT"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"
  echo "CURRENT_VERSION=$current_version"
  export CURRENT_VERSION="$current_version"

  release_version="${current_version/-SNAPSHOT/}"
  if [[ "${release_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    release_version="${release_version}.0"
  fi
  release_version="${release_version}.${BUILD_NUMBER}"
  echo "Replacing version $current_version with $release_version"
  sed -i.bak "s/$current_version/$release_version/g" gradle.properties
  rm -f gradle.properties.bak
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
  echo "PROJECT_VERSION=$release_version"
  export PROJECT_VERSION="$release_version"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -n "${CURRENT_VERSION:-}" && -n "${PROJECT_VERSION:-}" || "$SKIP" == "true" ]]; then
    echo "Using provided CURRENT_VERSION $CURRENT_VERSION and PROJECT_VERSION $PROJECT_VERSION without changes."
    echo "current-version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "project-version=$PROJECT_VERSION" >> "$GITHUB_OUTPUT"
  else
    echo "::group::Check tools"
    set_gradle_cmd
    echo "::endgroup::"
    echo "::group::Set project version"
    set_project_version
    echo "::endgroup::"
  fi
fi
