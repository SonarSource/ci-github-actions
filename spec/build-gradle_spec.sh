#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock java
  echo "java $*"
End
Mock gradle
  echo "gradle $*"
End
Mock jq
  echo "jq $*"
End
Mock git
  echo "git $*"
End
Mock chmod
  echo "chmod $*"
End

# Set up environment variables
export GITHUB_REPOSITORY="my-org/my-repo"
export GITHUB_REF_NAME="master"
export GITHUB_EVENT_NAME="push"
export BUILD_NUMBER="42"
export GITHUB_RUN_ID="12345"
export GITHUB_SHA="abc123"
export GITHUB_OUTPUT=/dev/null
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
echo '{}' > "$GITHUB_EVENT_PATH"

Describe 'build.sh'
  It 'should not run the main function if the script is sourced'
    When run source build-gradle/build.sh
    The status should be success
    The output should equal ""
  End
End

Include build-gradle/build.sh

Describe 'command_exists'
  It 'should report a tool as not installed'
    When call command_exists a_tool_that_does_not_exist
    The status should be failure
    The error should equal "a_tool_that_does_not_exist is not installed."
  End

  It 'should run a tool with arguments when it exists'
    When call command_exists echo "hello world"
    The status should be success
    The line 2 should equal "hello world"
  End
End

Describe 'set_build_env'
  It 'should set the default branch and project name'
    When call set_build_env
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "PULL_REQUEST: false"
    The line 3 should equal "Fetching commit history for SonarQube analysis..."
    The variable PROJECT should equal "my-repo"
    The variable PULL_REQUEST should equal "false"
    The variable PULL_REQUEST_SHA should be undefined
    The variable DEPLOY_PULL_REQUEST should equal "false"
    The variable SKIP_TESTS should equal "false"
    The variable GRADLE_ARGS should equal ""
  End

  It 'should set PULL_REQUEST and PULL_REQUEST_SHA for pull requests'
    export GITHUB_EVENT_NAME="pull_request"
    echo '{"number": 123, "pull_request": {"base": {"sha": "abc123"}}}' > "$GITHUB_EVENT_PATH"

    Mock jq
      if [[ "$*" == "--raw-output .number $GITHUB_EVENT_PATH" ]]; then
        echo "123"
      elif [[ "$*" == "--raw-output .pull_request.base.sha $GITHUB_EVENT_PATH" ]]; then
        echo "abc123"
      else
        echo "jq $*"
      fi
    End

    When call set_build_env
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "PULL_REQUEST: 123"
    The line 3 should equal "Fetching commit history for SonarQube analysis..."
    The variable PULL_REQUEST should equal "123"
    The variable PULL_REQUEST_SHA should equal "abc123"
  End
End

Describe 'set_project_version'
  It 'should retrieve version from gradle.properties when it exists'
    # Create a temporary gradle.properties file
    echo "version=1.2.3" > gradle.properties

    When call set_project_version
    The line 1 should equal "Retrieved INITIAL_VERSION=1.2.3 from gradle.properties"
    The variable INITIAL_VERSION should equal "1.2.3"

    # Clean up
    rm -f gradle.properties
  End

  It 'should handle missing gradle.properties file'
    # Ensure no gradle.properties exists
    rm -f gradle.properties

    When call set_project_version
    The line 1 should equal "gradle.properties not found, version information may be unavailable"
    The variable INITIAL_VERSION should be undefined
  End
End

Describe 'should_deploy'
  It 'should deploy for master branch'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="master"

    When call should_deploy
    The status should be success
  End

  It 'should deploy for maintenance branch'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="branch-1.2"

    When call should_deploy
    The status should be success
  End

  It 'should deploy for dogfood branch'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="dogfood-on-next"

    When call should_deploy
    The status should be success
  End

  It 'should deploy for long-lived feature branch'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="feature/long/my-feature"

    When call should_deploy
    The status should be success
  End

  It 'should not deploy for regular feature branch'
    unset PULL_REQUEST
    export GITHUB_REF_NAME="feature/my-feature"

    When call should_deploy
    The status should be failure
  End

  It 'should not deploy for pull request by default'
    export PULL_REQUEST="123"
    export DEPLOY_PULL_REQUEST="false"

    When call should_deploy
    The status should be failure
  End

  It 'should deploy for pull request when DEPLOY_PULL_REQUEST is true'
    export PULL_REQUEST="123"
    export DEPLOY_PULL_REQUEST="true"

    When call should_deploy
    The status should be success
  End
End

Describe 'build_gradle_args'
  It 'should build basic gradle arguments without deployment'
    export SKIP_TESTS="false"
    unset SONAR_HOST_URL
    unset SONAR_TOKEN
    export GRADLE_ARGS=""
    export PULL_REQUEST="false"
    export GITHUB_REF_NAME="feature/test"

    When call build_gradle_args
    The line 1 should include "--no-daemon"
    The line 1 should include "--info"
    The line 1 should include "--stacktrace"
    The line 1 should include "--console"
    The line 1 should include "plain"
    The line 1 should include "build"
    The line 1 should include "-DbuildNumber=42"
    The line 1 should not include "artifactoryPublish"
  End

  It 'should skip tests when SKIP_TESTS is true'
    export SKIP_TESTS="true"
    unset SONAR_HOST_URL
    unset SONAR_TOKEN
    export GRADLE_ARGS=""
    export PULL_REQUEST="false"
    export GITHUB_REF_NAME="feature/test"

    When call build_gradle_args
    The line 2 should include "-x"
    The line 2 should include "test"
    The line 1 should equal "Skipping tests as requested"
  End

  It 'should add sonar arguments when SONAR_HOST_URL and SONAR_TOKEN are set'
    export SKIP_TESTS="false"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    export GRADLE_ARGS=""
    export PULL_REQUEST="false"
    export GITHUB_REF_NAME="feature/test"

    When call build_gradle_args
    The line 1 should include "sonar"
    The line 1 should include "-Dsonar.host.url=https://sonar.example.com"
    The line 1 should include "-Dsonar.token=sonar-token"
    The line 1 should include "-Dsonar.analysis.buildNumber=42"
    The line 1 should include "-Dsonar.analysis.pipeline=12345"
    The line 1 should include "-Dsonar.analysis.repository=my-org/my-repo"
  End

  It 'should add artifactory publish for master branch'
    export SKIP_TESTS="false"
    unset SONAR_HOST_URL
    unset SONAR_TOKEN
    export GRADLE_ARGS=""
    export PULL_REQUEST="false"
    export GITHUB_REF_NAME="master"

    When call build_gradle_args
    The line 1 should include "artifactoryPublish"
  End

  It 'should add additional gradle arguments when GRADLE_ARGS is set'
    export SKIP_TESTS="false"
    unset SONAR_HOST_URL
    unset SONAR_TOKEN
    export GRADLE_ARGS="--parallel --build-cache"
    export PULL_REQUEST="false"
    export GITHUB_REF_NAME="feature/test"

    When call build_gradle_args
    The line 1 should include "--parallel"
    The line 1 should include "--build-cache"
  End
End

Describe 'main'
  It 'should call all required functions in order'
    Mock command_exists
      if [[ "$1" == "java" ]]; then
        echo "java version \"1.8.0_281\""
      elif [[ "$1" == "gradle" ]]; then
        echo "gradle"
        echo "Gradle 7.4.2"
      else
        echo "$1 is not installed." >&2
      fi
    End

    Mock set_build_env
      echo "PROJECT: my-repo"
      echo "PULL_REQUEST: false"
      echo "Fetching commit history for SonarQube analysis..."
    End

    Mock set_project_version
      echo "Retrieved INITIAL_VERSION=1.0.0 from gradle.properties"
    End

    Mock gradle_build
      echo "Starting regular build build..."
      echo "Build completed successfully"
    End

    When call main
    The line 1 should equal "java version \"1.8.0_281\""
    The line 2 should equal "gradle"
    The line 3 should equal "Gradle 7.4.2"
    The line 4 should equal "gradle"
    The line 5 should equal "Gradle 7.4.2"
    The line 6 should equal "PROJECT: my-repo"
    The line 7 should equal "PULL_REQUEST: false"
    The line 8 should equal "Fetching commit history for SonarQube analysis..."
    The line 9 should equal "Retrieved INITIAL_VERSION=1.0.0 from gradle.properties"
    The line 10 should equal "Starting regular build build..."
    The line 11 should equal "Build completed successfully"
    The status should be success
  End
End
