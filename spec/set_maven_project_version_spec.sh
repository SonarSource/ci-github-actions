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
  common_setup() {
    export BUILD_NUMBER="999"
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    GITHUB_ENV=$(mktemp)
    export GITHUB_ENV
  }
  common_cleanup() {
    [[ -f "$GITHUB_OUTPUT" ]] && rm "$GITHUB_OUTPUT"
    [[ -f "$GITHUB_ENV" ]] && rm "$GITHUB_ENV"
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

  It 'skips version update when already set in environment'
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3-42"
    export BUILD_NUMBER="42"
    When call set_project_version
    The status should be success
    The line 1 should equal "Using provided CURRENT_VERSION 1.2.3-SNAPSHOT and PROJECT_VERSION 1.2.3-42 without changes."
    The contents of file "$GITHUB_OUTPUT" should include "current-version=1.2.3-SNAPSHOT"
    The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.3-42"
  End
End

Describe 'main()'
  Mock get_current_version
    echo "1.2.3-SNAPSHOT"
  End
  It 'runs tool checks and calls set_project_version'
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3-42"
    When run script config-maven/set_maven_project_version.sh
    The status should be success
    The lines of stdout should equal 3
    The line 1 should include "mvn"
    The line 2 should equal "mvn --version"
    The line 3 should start with "Using provided CURRENT_VERSION 1.2.3-SNAPSHOT and PROJECT_VERSION 1.2.3-42 without changes."
  End
End
