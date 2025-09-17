#!/bin/bash

set -euo pipefail

: "${BUILD_NUMBER:?}"
: "${GITHUB_OUTPUT:?}"

check_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "::error title=Missing tool::$1 is not installed. Please see https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/4267245619/Preinstalling+Tools+with+Mise+and+Preinstalled+Tools+on+Runners+-+GitHub for installation instructions." >&2
    return 1
  fi
  "$@"
}

# Evaluate a Maven property/expression with org.codehaus.mojo:exec-maven-plugin
maven_expression() {
  local expression="$1"
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
  if ! current_version=$(maven_expression "project.version" 2>&1); then
    echo -e "::error file=pom.xml,title=Maven project version::Could not get 'project.version' from Maven project\nERROR: $current_version"
    return 1
  fi

  # Saving the current version to the output and environment variables
  # This is used by the sonar-scanner to to set the vaule of sonar.projectVersion without the build number
  echo "current-version=$current_version" >> "$GITHUB_OUTPUT"
  echo "CURRENT_VERSION=$current_version" >> "$GITHUB_ENV"

  local release_version="${current_version%"-SNAPSHOT"}"
  local digits="${release_version//[^.]/}"
  local digit_count="${#digits}"

  # Check if this is a maintenance branch with a release version
  if [[ "$GITHUB_REF_NAME" == branch-* ]] && [[ "$current_version" != *"-SNAPSHOT" ]]; then
    if [[ "$digit_count" -ne 3 ]]; then
      echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
      return 1
    fi
    echo "Found RELEASE version on maintenance branch: ${current_version}. Skipping version update."
    echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
    echo "PROJECT_VERSION=$release_version" >> "$GITHUB_ENV"
    return 0
  fi

  if [[ "$digit_count" -eq 0 ]]; then
    release_version="${release_version}.0.0"
  elif [[ "$digit_count" -eq 1 ]]; then
    release_version="${release_version}.0"
  elif [[ "$digit_count" -ne 2 ]]; then
    echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
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
