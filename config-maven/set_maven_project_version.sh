#!/bin/bash

set -euo pipefail

: "${BUILD_NUMBER:?}"
: "${GITHUB_OUTPUT:?}"
: "${GITHUB_ENV:?}"

# Check if a command is available and runs it, typically: 'some_tool --version'
check_tool() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

get_current_version() {
  local expression="project.version"
  if ! mvn -q -Dexec.executable="echo" -Dexec.args="\${$expression}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec; then
    echo "Failed to evaluate Maven expression '$expression'" >&2
    mvn -X -Dexec.executable="echo" -Dexec.args="\${$expression}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec
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

  mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion="$release_version" -DgenerateBackupPoms=false -B -e
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_tool mvn --version
  set_project_version "$@"
fi
