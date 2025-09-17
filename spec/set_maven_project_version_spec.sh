#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Set required environment variables for script inclusion
export BUILD_NUMBER="1"
export GITHUB_ENV=/dev/null
export GITHUB_OUTPUT=/dev/null

# Include the script to test
Include config-maven/set_maven_project_version.sh

# Common setup function for all tests
common_setup() {
  export BUILD_NUMBER="999"
  GITHUB_OUTPUT=$(mktemp)
  export GITHUB_OUTPUT
  GITHUB_ENV=$(mktemp)
  export GITHUB_ENV
}

# Common cleanup function for all tests
common_cleanup() {
  [[ -f "$GITHUB_OUTPUT" ]] && rm "$GITHUB_OUTPUT"
  [[ -f "$GITHUB_ENV" ]] && rm "$GITHUB_ENV"
}

Describe 'check_tool()'
  It 'reports not installed tool'
    When call check_tool some_nonexistent_tool
    The status should be failure
    The error should include "some_nonexistent_tool is not installed."
  End

  It 'executes tool when available'
    When call check_tool echo "test"
    The status should be success
    The output should equal "test"
  End
End

Describe 'get_current_version()'
  It 'evaluates Maven expression successfully'
    Mock mvn
      case "$*" in
        *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
          echo "1.2.3-SNAPSHOT"
          ;;
        *)
          echo "mvn $*"
          ;;
      esac
    End
    When call get_current_version
    The status should be success
    The output should equal "1.2.3-SNAPSHOT"
  End

  It 'handles Maven expression failure'
    Mock mvn
      case "$*" in
        *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
          echo "Failed to evaluate Maven expression 'project.version'" >&2
          return 1
          ;;
        *)
          echo "mvn $*"
          ;;
      esac
    End
    When call get_current_version
    The status should be failure
    The error should include "Failed to evaluate Maven expression 'project.version'"
    The output should include "mvn -X -Dexec.executable=echo"
  End
End

Describe 'set_project_version()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  Describe 'SNAPSHOT versions'
    It 'handles 1.2.3-SNAPSHOT version'
      Mock mvn
        case "$*" in
          *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
            echo "1.2.3-SNAPSHOT"
            ;;
          *)
            echo "mvn $*"
            ;;
        esac
      End
      When call set_project_version
      The status should be success
      The contents of file "$GITHUB_OUTPUT" should include "snapshot-version=1.2.3-SNAPSHOT"
      The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.3.999"
      The contents of file "$GITHUB_ENV" should include "SNAPSHOT_VERSION=1.2.3-SNAPSHOT"
      The contents of file "$GITHUB_ENV" should include "PROJECT_VERSION=1.2.3.999"
      The output should include "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.2.3.999"
    End

    It 'handles 1.2-SNAPSHOT version (adds .0)'
      Mock mvn
        case "$*" in
          *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
            echo "1.2-SNAPSHOT"
            ;;
          *)
            echo "mvn $*"
            ;;
        esac
      End
      When call set_project_version
      The status should be success
      The contents of file "$GITHUB_OUTPUT" should include "snapshot-version=1.2-SNAPSHOT"
      The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.0.999"
      The contents of file "$GITHUB_ENV" should include "SNAPSHOT_VERSION=1.2-SNAPSHOT"
      The contents of file "$GITHUB_ENV" should include "PROJECT_VERSION=1.2.0.999"
      The output should include "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.2.0.999"
    End

    It 'handles 1-SNAPSHOT version (adds .0.0)'
      Mock mvn
        case "$*" in
          *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
            echo "1-SNAPSHOT"
            ;;
          *)
            echo "mvn $*"
            ;;
        esac
      End
      When call set_project_version
      The status should be success
      The contents of file "$GITHUB_OUTPUT" should include "snapshot-version=1-SNAPSHOT"
      The contents of file "$GITHUB_OUTPUT" should include "project-version=1.0.0.999"
      The contents of file "$GITHUB_ENV" should include "SNAPSHOT_VERSION=1-SNAPSHOT"
      The contents of file "$GITHUB_ENV" should include "PROJECT_VERSION=1.0.0.999"
      The output should include "mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion=1.0.0.999"
    End

    It 'rejects version with too many digits'
      Mock mvn
        case "$*" in
          *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
            echo "1.2.3.4-SNAPSHOT"
            ;;
          *)
            echo "mvn $*"
            ;;
        esac
      End
      When call set_project_version
      The status should be failure
      The output should include "Unsupported version '1.2.3.4-SNAPSHOT' with 4 digits."
    End
  End

  Describe 'Maven expression failure'
    It 'handles Maven expression failure gracefully'
      Mock mvn
        case "$*" in
          *"-q -Dexec.executable=echo -Dexec.args=\${project.version}"*)
            echo "Maven error occurred" >&2
            return 1
            ;;
          *)
            echo "mvn $*"
            ;;
        esac
      End
      When call set_project_version
      The status should be failure
      The output should include "Could not get 'project.version' from Maven project"
    End

  End

End
