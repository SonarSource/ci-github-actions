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

get_current_version() {
  local expression="project.version"
  if ! command mvn --quiet --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec 2>/dev/null \
      -Dexec.executable="echo" -Dexec.args="\${$expression}"; then
    echo "Failed to evaluate Maven expression '$expression'" >&2
    command mvn --debug --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec \
      -Dexec.executable="echo" -Dexec.args="\${$expression}"
    return 1
  fi
}

# Set the project version as <MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>
# Update current_version variable with the current project version.
# Then remove the -SNAPSHOT suffix if present, complete with '.0' if needed, and append the build number at the end.
set_project_version() {
  local current_version
  if ! current_version=$(get_current_version 2>&1); then
    echo -e "::error file=pom.xml,title=Maven project version::Could not get 'project.version' from Maven project\nERROR: $current_version"
    return 1
  fi

  # Saving the snapshot version to the output and environment variables
  # This is used by the sonar-scanner to set the value of sonar.projectVersion without the build number
  echo "current-version=$current_version" >> "$GITHUB_OUTPUT"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"
  echo "CURRENT_VERSION=$current_version (from pom.xml)"
  export CURRENT_VERSION="$current_version"

  local release_version="${current_version%"-SNAPSHOT"}"
  local dots="${release_version//[^.]/}"
  local dots_count="${#dots}"

  if [[ "$dots_count" -eq 0 ]]; then
    release_version="${release_version}.0.0"
  elif [[ "$dots_count" -eq 1 ]]; then
    release_version="${release_version}.0"
  elif [[ "$dots_count" -ne 2 ]]; then
    echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((dots_count + 1)) digits."
    return 1
  fi
  release_version="${release_version}.${BUILD_NUMBER}"
  echo "Replacing version $current_version with $release_version"
  echo "Maven command: mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=$release_version" \
    "-DgenerateBackupPoms=false --batch-mode --no-transfer-progress --errors"
  mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion="$release_version" \
    -DgenerateBackupPoms=false --batch-mode --no-transfer-progress --errors
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
    check_tool mvn --version
    echo "::endgroup::"
    echo "::group::Set project version"
    set_project_version
    echo "::endgroup::"
  fi
fi
