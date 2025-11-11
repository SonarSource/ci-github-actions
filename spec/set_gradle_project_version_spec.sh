#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Set required environment variables for script inclusion
export BUILD_NUMBER="1"
export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null

Mock gradle
  if [[ "$*" == "properties --no-scan --no-daemon --console plain" ]]; then
    echo "version: 1.2.3-SNAPSHOT"
  else
    echo "gradle $*"
  fi
End

Describe 'config-gradle/set_gradle_project_version.sh'
  It 'does not run main when sourced'
    When run source config-gradle/set_gradle_project_version.sh
    The status should be success
    The output should equal ""
  End
End

Include config-gradle/set_gradle_project_version.sh

Describe 'set_gradle_cmd()'
  It 'uses gradlew when available'
    touch ./gradlew

    When call set_gradle_cmd
    The status should be success
    The lines of output should equal 0
    The variable GRADLE_CMD should equal "./gradlew"

    rm -f ./gradlew
  End

  It 'uses gradle when gradlew not found'
    Mock check_tool
      [[ "$1" == "gradle" ]] && true
    End
    When call set_gradle_cmd
    The status should be success
    The lines of output should equal 0
    The variable GRADLE_CMD should equal "gradle"
  End

  It 'fails when neither gradle nor gradlew are available'
    Mock check_tool
      [[ "$1" == "gradle" ]] && false
    End
    When run set_gradle_cmd
    The status should be failure
    The lines of output should equal 0
    The lines of error should equal 1
    The line 1 of error should equal "Neither ./gradlew nor gradle command found!"
  End
End

Describe 'set_project_version()'
  # shellcheck disable=SC2329,SC2317  # Function invoked indirectly by BeforeEach
  common_setup() {
    BUILD_NUMBER="42"
    GITHUB_OUTPUT=$(mktemp)
    GITHUB_ENV=$(mktemp)
    # shellcheck disable=SC2034  # Used by set_project_version() function
    GRADLE_CMD="gradle"
    echo "version=1.0-SNAPSHOT" > gradle.properties
    return 0
  }
  # shellcheck disable=SC2329,SC2317  # Function invoked indirectly by AfterEach
  common_cleanup() {
    [[ -f "$GITHUB_OUTPUT" ]] && rm "$GITHUB_OUTPUT"
    [[ -f "$GITHUB_ENV" ]] && rm "$GITHUB_ENV"
    rm -f gradle.properties gradle.properties.bak
    return 0
  }

  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'processes version correctly'
    Mock gradle
      echo "version: 1.2.3-SNAPSHOT"
    End
    When call set_project_version
    The status should be success
    The lines of output should equal 3
    The line 1 should equal "CURRENT_VERSION=1.2.3-SNAPSHOT"
    The line 2 should equal "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
    The line 3 should equal "PROJECT_VERSION=1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
    The variable PROJECT_VERSION should equal "1.2.3.42"
    The lines of contents of file "$GITHUB_OUTPUT" should equal 1
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.3.42"
    The lines of contents of file "$GITHUB_ENV" should equal 2
    The line 1 of contents of file "$GITHUB_ENV" should equal "CURRENT_VERSION=1.2.3-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_ENV" should equal "PROJECT_VERSION=1.2.3.42"
  End

  It 'adds .0 to two-digit version'
    Mock gradle
      echo "version: 1.2-SNAPSHOT"
    End
    When call set_project_version
    The status should be success
    The lines of output should equal 3
    The line 1 should equal "CURRENT_VERSION=1.2-SNAPSHOT"
    The line 2 should equal "Replacing version 1.2-SNAPSHOT with 1.2.0.42"
    The line 3 should equal "PROJECT_VERSION=1.2.0.42"
    The variable CURRENT_VERSION should equal "1.2-SNAPSHOT"
    The variable PROJECT_VERSION should equal "1.2.0.42"
    The lines of contents of file "$GITHUB_OUTPUT" should equal 1
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.0.42"
    The lines of contents of file "$GITHUB_ENV" should equal 2
    The line 1 of contents of file "$GITHUB_ENV" should equal "CURRENT_VERSION=1.2-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_ENV" should equal "PROJECT_VERSION=1.2.0.42"
  End

  It 'fails when version is empty'
    Mock gradle
      echo "version:"
    End
    When run set_project_version
    The status should be failure
    The lines of output should equal 0
    The lines of error should equal 1
    The line 1 of error should equal "ERROR: Could not get valid version from Gradle properties. Got: ''"
  End

  It 'fails when version is unspecified'
    Mock gradle
      echo "version: unspecified"
    End
    When run set_project_version
    The status should be failure
    The lines of output should equal 0
    The lines of error should equal 1
    The line 1 of error should equal "ERROR: Could not get valid version from Gradle properties. Got: 'unspecified'"
  End
End

Describe 'main()'
  common_setup() {
    BUILD_NUMBER="42"
    GITHUB_OUTPUT=$(mktemp)
    GITHUB_ENV=$(mktemp)
    echo "version=1.0-SNAPSHOT" > gradle.properties
    return 0
  }

  common_cleanup() {
    rm -f "$GITHUB_OUTPUT" "$GITHUB_ENV" gradle.properties gradle.properties.bak
    return 0
  }

  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  # Mock gradle to prove set_gradle_cmd and set_project_version were called
  Mock gradle
    # Output from set_project_version
    echo "version: 1.2.4-SNAPSHOT"
  End

  It 'runs tool checks and calls set_project_version'
    When run script config-gradle/set_gradle_project_version.sh
    The status should be success
    The lines of output should equal 5
    The line 1 should include "gradle"
    The line 2 should equal "version: 1.2.4-SNAPSHOT"
    The line 3 should equal "CURRENT_VERSION=1.2.4-SNAPSHOT"
    The line 4 should equal "Replacing version 1.2.4-SNAPSHOT with 1.2.4.42"
    The line 5 should equal "PROJECT_VERSION=1.2.4.42"
  End

  It 'uses provided CURRENT_VERSION and PROJECT_VERSION without changes'
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3.42"

    When run script config-gradle/set_gradle_project_version.sh
    The status should be success
    The lines of output should equal 1
    The line 1 should equal "Using provided CURRENT_VERSION 1.2.3-SNAPSHOT and PROJECT_VERSION 1.2.3.42 without changes."
    The lines of contents of file "$GITHUB_OUTPUT" should equal 2
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "current-version=1.2.3-SNAPSHOT"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "project-version=1.2.3.42"
  End

  It 'proceeds normally when only CURRENT_VERSION is provided'
    export CURRENT_VERSION="1.2.3-SNAPSHOT"

    When run script config-gradle/set_gradle_project_version.sh
    The status should be success
    The lines of output should equal 5
  End

  It 'proceeds normally when only PROJECT_VERSION is provided'
    export PROJECT_VERSION="1.2.3.42"

    When run script config-gradle/set_gradle_project_version.sh
    The status should be success
    The lines of output should equal 5
  End
End
