#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Set required environment variables for script inclusion
export BUILD_NUMBER="1"
export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null

Mock mvn
  echo "mvn $*"
End

Describe 'config-maven/set_maven_project_version.sh'
  It 'does not run main when sourced'
    When run source config-maven/set_maven_project_version.sh
    The status should be success
    The output should equal ""
  End
End

Include config-maven/set_maven_project_version.sh

Describe 'get_current_version()'
  It 'calls Maven expression successfully'
    When call get_current_version
    The status should be success
    The lines of output should equal 1
    The line 1 of output should start with "mvn --quiet --non-recursive org.codehaus.mojo:exec-maven-plugin"
  End

  It 'handles Maven expression failure'
    Mock mvn
      false
    End
    When call get_current_version
    The status should be failure
    The lines of error should equal 1
    The line 1 of error should equal "Failed to evaluate Maven expression 'project.version'"
  End
End

Describe 'set_project_version()'
  # shellcheck disable=SC2329,SC2317  # Function invoked indirectly by BeforeEach
  common_setup() {
    BUILD_NUMBER="999"
    GITHUB_OUTPUT=$(mktemp)
    GITHUB_ENV=$(mktemp)
    return 0
  }
  # shellcheck disable=SC2329,SC2317  # Function invoked indirectly by AfterEach
  common_cleanup() {
    [[ -f "$GITHUB_OUTPUT" ]] && rm "$GITHUB_OUTPUT"
    [[ -f "$GITHUB_ENV" ]] && rm "$GITHUB_ENV"
    return 0
  }

  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'handles 1.2.3-SNAPSHOT version'
    Mock get_current_version
      echo "1.2.3-SNAPSHOT"
    End
    When call set_project_version
    The status should be success
    The lines of contents of file "$GITHUB_OUTPUT" should equal 2
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "current-version=1.2.3-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.3.999"
    The lines of contents of file "$GITHUB_ENV" should equal 2
    The line 1 of contents of file "$GITHUB_ENV" should equal "CURRENT_VERSION=1.2.3-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_ENV" should equal "PROJECT_VERSION=1.2.3.999"
    The lines of output should equal 5
    The line 1 should equal "CURRENT_VERSION=1.2.3-SNAPSHOT (from pom.xml)"
    The line 2 should equal "Replacing version 1.2.3-SNAPSHOT with 1.2.3.999"
    The line 3 should start with "Maven command: mvn"
    The line 4 should start with "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.2.3.999"
    The line 5 should equal "PROJECT_VERSION=1.2.3.999"
  End

  It 'handles 1.2-SNAPSHOT version (adds .0)'
    Mock get_current_version
      echo "1.2-SNAPSHOT"
    End
    When call set_project_version
    The status should be success
    The lines of contents of file "$GITHUB_OUTPUT" should equal 2
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "current-version=1.2-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.0.999"
    The lines of contents of file "$GITHUB_ENV" should equal 2
    The line 1 of contents of file "$GITHUB_ENV" should equal "CURRENT_VERSION=1.2-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_ENV" should equal "PROJECT_VERSION=1.2.0.999"
    The lines of output should equal 5
    The line 1 should equal "CURRENT_VERSION=1.2-SNAPSHOT (from pom.xml)"
    The line 2 should equal "Replacing version 1.2-SNAPSHOT with 1.2.0.999"
    The line 3 should start with "Maven command: mvn"
    The line 4 should start with "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.2.0.999"
    The line 5 should equal "PROJECT_VERSION=1.2.0.999"
  End

  It 'handles 1-SNAPSHOT version (adds .0.0)'
    Mock get_current_version
      echo "1-SNAPSHOT"
    End
    When call set_project_version
    The status should be success
    The lines of contents of file "$GITHUB_OUTPUT" should equal 2
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "current-version=1-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.0.0.999"
    The lines of contents of file "$GITHUB_ENV" should equal 2
    The line 1 of contents of file "$GITHUB_ENV" should equal "CURRENT_VERSION=1-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_ENV" should equal "PROJECT_VERSION=1.0.0.999"
    The lines of output should equal 5
    The line 1 should equal "CURRENT_VERSION=1-SNAPSHOT (from pom.xml)"
    The line 2 should equal "Replacing version 1-SNAPSHOT with 1.0.0.999"
    The line 3 should start with "Maven command: mvn"
    The line 4 should start with "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.0.0.999"
    The line 5 should equal "PROJECT_VERSION=1.0.0.999"
  End

  It 'rejects version with too many digits'
    Mock get_current_version
      echo "1.2.3.4-SNAPSHOT"
    End
    When call set_project_version
    The status should be failure
    The lines of output should equal 2
    The line 1 should equal "CURRENT_VERSION=1.2.3.4-SNAPSHOT (from pom.xml)"
    The line 2 should include "Unsupported version '1.2.3.4-SNAPSHOT' with 4 digits."
  End

  It 'handles Maven expression failure gracefully'
    Mock get_current_version
      false
    End
    When call set_project_version
    The status should be failure
    The lines of output should equal 2
    The line 1 of output should include "Could not get 'project.version' from Maven project"
    The line 2 of output should start with "ERROR:"
  End
End

Describe 'main()'
  common_setup() {
    BUILD_NUMBER="1"
    GITHUB_OUTPUT=$(mktemp)
    GITHUB_ENV=$(mktemp)
    return 0
  }

  common_cleanup() {
    rm -f "$GITHUB_OUTPUT" "$GITHUB_ENV"
    return 0
  }

  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  Mock mvn
    if [[ "$*" == "--version" ]]; then
      echo "mvn --version"
    elif [[ "$*" == *"exec-maven-plugin"* ]]; then
      echo "1.2.3-SNAPSHOT"
    elif [[ "$*" == *"versions-maven-plugin"* ]]; then
      echo "mvn versions"
    fi
  End

  It 'runs tool checks and calls set_project_version'
    When run script config-maven/set_maven_project_version.sh
    The status should be success
    The lines of output should equal 7
    The line 1 should include "mvn"
    The line 2 should equal "mvn --version"
    The line 3 should equal "CURRENT_VERSION=1.2.3-SNAPSHOT (from pom.xml)"
    The line 4 should equal "Replacing version 1.2.3-SNAPSHOT with 1.2.3.1"
    The line 5 should start with "Maven command:"
    The line 6 should equal "mvn versions"
    The line 7 should equal "PROJECT_VERSION=1.2.3.1"
  End

  It 'uses provided CURRENT_VERSION and PROJECT_VERSION without changes'
    export BUILD_NUMBER="999"
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3.999"

    When run script config-maven/set_maven_project_version.sh
    The status should be success
    The lines of output should equal 1
    The line 1 should equal "Using provided CURRENT_VERSION 1.2.3-SNAPSHOT and PROJECT_VERSION 1.2.3.999 without changes."
    The lines of contents of file "$GITHUB_OUTPUT" should equal 2
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "current-version=1.2.3-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.3.999"
  End

  It 'proceeds normally when only CURRENT_VERSION is provided'
    export BUILD_NUMBER="999"
    export CURRENT_VERSION="1.2.3-SNAPSHOT"

    When run script config-maven/set_maven_project_version.sh
    The status should be success
    The lines of output should equal 7
  End

  It 'proceeds normally when only PROJECT_VERSION is provided'
    export BUILD_NUMBER="999"
    export PROJECT_VERSION="1.2.3.999"

    When run script config-maven/set_maven_project_version.sh
    The status should be success
    The lines of output should equal 7
  End
End
