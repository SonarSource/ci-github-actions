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
: "${GITHUB_OUTPUT:?}" "${GITHUB_ENV:?}"

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

set_gradle_cmd() {
  if [[ -f "./gradlew" ]]; then
    export GRADLE_CMD="./gradlew"
  elif check_tool gradle; then
    export GRADLE_CMD="gradle"
  else
    echo "Neither ./gradlew nor gradle command found!" >&2
    exit 1
  fi
}

set_project_version() {
  local current_version
  current_version=$($GRADLE_CMD properties --no-scan --no-daemon --console plain | grep 'version:' | tr -d "[:space:]" | cut -d ":" -f 2)
  if [[ -z "$current_version" || "$current_version" == "unspecified" ]]; then
    echo "ERROR: Could not get valid version from Gradle properties. Got: '$current_version'" >&2
    return 1
  fi

  # Saving the snapshot version to the output and environment variables
  # This is used by the sonar-scanner to set the value of sonar.projectVersion without the build number
  echo "CURRENT_VERSION=$current_version"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"
  export CURRENT_VERSION=$current_version

  release_version="${current_version/-SNAPSHOT/}"
  if [[ "${release_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    release_version="${release_version}.0"
  fi
  release_version="${release_version}.${BUILD_NUMBER}"
  echo "Replacing version $current_version with $release_version"
  sed -i.bak "s/$current_version/$release_version/g" gradle.properties
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
  echo "PROJECT_VERSION=$release_version"
  export PROJECT_VERSION=$release_version
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -n "${CURRENT_VERSION:-}" && -n "${PROJECT_VERSION:-}" ]]; then
    echo "Using provided CURRENT_VERSION $CURRENT_VERSION and PROJECT_VERSION $PROJECT_VERSION without changes."
    echo "current-version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "project-version=$PROJECT_VERSION" >> "$GITHUB_OUTPUT"
  else
    set_gradle_cmd
    set_project_version
  fi
fi
