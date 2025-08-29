#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock java
  echo "java $*"
End
Mock gradle
  if [[ "$*" == "properties --no-scan" ]]; then
    echo "version: 1.2.3-SNAPSHOT"
  else
    echo "gradle $*"
  fi
End
Mock git
  echo "git $*"
End
Mock jq
  if [[ "$*" == "--raw-output .number"* ]]; then
    echo "123"
  elif [[ "$*" == "--raw-output .pull_request.base.sha"* ]]; then
    echo "base123"
  else
    echo "jq $*"
  fi
End
Mock sed
  echo "sed $*"
End

# Environment setup
export ARTIFACTORY_URL="https://dummy.repox/artifactory"
export DEFAULT_BRANCH="master"
export PULL_REQUEST=""
export PULL_REQUEST_SHA=""
export GITHUB_REF_NAME="master"
export BUILD_NUMBER="42"
export GITHUB_RUN_ID="123456"
export GITHUB_SHA="abc123def456"
export GITHUB_REPOSITORY="my-org/my-repo"
export ARTIFACTORY_ACCESS_TOKEN="artifactory-access-token"
export ARTIFACTORY_DEPLOY_REPO="deploy-repo"
export ARTIFACTORY_DEPLOY_USERNAME="deploy-user"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="deploy-access-token"
export SONAR_PLATFORM="next"
export RUN_SHADOW_SCANS="false"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarcloud.io"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
export ORG_GRADLE_PROJECT_signingKey="signing-key"
export ORG_GRADLE_PROJECT_signingPassword="signing-pass"
export ORG_GRADLE_PROJECT_signingKeyId="signing-id"
export DEPLOY_PULL_REQUEST="false"
export SKIP_TESTS="false"
export GRADLE_ARGS=""
export GITHUB_EVENT_NAME="push"
export GITHUB_OUTPUT=/dev/null
# Required SonarQube platform variables
export SONAR_PLATFORM="next"
export RUN_SHADOW_SCANS="false"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarcloud.io"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
echo '{}' > "$GITHUB_EVENT_PATH"
export GRADLE_CMD="gradle"

Describe 'build-gradle/build.sh'
  It 'does not run main when sourced'
    When run source build-gradle/build.sh
    The status should be success
    The output should equal ""
  End
End

Include build-gradle/build.sh

Describe 'command_exists'
  It 'reports missing tool'
    When call command_exists nonexistent_tool
    The status should be failure
    The error should equal "nonexistent_tool is not installed."
  End

  It 'executes existing command'
    When call command_exists echo "test"
    The status should be success
    The line 2 should equal "test"
  End
End

Describe 'set_build_env'
  It 'sets project and default values'
    export PULL_REQUEST=""
    export PULL_REQUEST_SHA=""
    When call set_build_env
    The output should include "PROJECT: my-repo"
    The variable PROJECT should equal "my-repo"
  End

  It 'handles pull request'
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST="123"
    export PULL_REQUEST_SHA="base123"
    echo '{"number": 123, "pull_request": {"base": {"sha": "base123"}}}' > "$GITHUB_EVENT_PATH"

    When call set_build_env
    The output should include "PROJECT: my-repo"
    The output should include "Fetching commit history for SonarQube analysis..."
  End

  It 'fetches base branch when GITHUB_BASE_REF is set'
    export GITHUB_BASE_REF="main"
    When call set_build_env
    The output should include "Fetching base branch: main"
  End
End

Describe 'set_project_version'
  It 'processes version correctly'
    echo "version=1.0-SNAPSHOT" > gradle.properties
    When call set_project_version
    The output should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
    The variable PROJECT_VERSION should equal "1.2.3.42"
    rm -f gradle.properties gradle.properties.bak
  End

  It 'adds .0 to two-digit version'
    echo "version=1.2-SNAPSHOT" > gradle.properties
    Mock gradle
      echo "version: 1.2-SNAPSHOT"
    End
    When call set_project_version
    The output should include "Replacing version 1.2-SNAPSHOT with 1.2.0.42"
    The variable CURRENT_VERSION should equal "1.2-SNAPSHOT"
    The variable PROJECT_VERSION should equal "1.2.0.42"
    rm -f gradle.properties gradle.properties.bak
  End
End

Describe 'should_deploy'
  It 'deploys for master branch'
    export GITHUB_REF_NAME="master"
    export GITHUB_EVENT_NAME="push"
    When call should_deploy
    The status should be success
  End

  It 'deploys for maintenance branch'
    export GITHUB_REF_NAME="branch-1.0"
    export GITHUB_EVENT_NAME="push"
    When call should_deploy
    The status should be success
  End

  It 'does not deploy for feature branch'
    export GITHUB_REF_NAME="feature/test"
    export GITHUB_EVENT_NAME="push"
    When call should_deploy
    The status should be failure
  End

  It 'does not deploy for PR by default'
    export GITHUB_EVENT_NAME="pull_request"
    export DEPLOY_PULL_REQUEST="false"
    When call should_deploy
    The status should be failure
  End

  It 'deploys for PR when enabled'
    export GITHUB_EVENT_NAME="pull_request"
    export DEPLOY_PULL_REQUEST="true"
    When call should_deploy
    The status should be success
  End

  It 'does not deploy when shadow scans enabled'
    export RUN_SHADOW_SCANS="true"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_REF_NAME="master"
    When call should_deploy
    The status should be failure
  End
End

Describe 'build_gradle_args'
  export CURRENT_VERSION="1.0.0-SNAPSHOT"

  It 'includes base arguments'
    export GRADLE_ARGS=""
    When call build_gradle_args
    The output should include "--no-daemon"
    The output should include "build"
  End

  It 'includes sonar when configured'
    export GRADLE_ARGS=""
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "sonar"
    The output should include "-Dsonar.host.url=https://sonar.example.com"
  End

  It 'includes deployment for master'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="master"
    export GITHUB_EVENT_NAME="push"
    When call build_gradle_args
    The output should include "artifactoryPublish"
  End

  It 'skips tests when SKIP_TESTS is true'
    export GRADLE_ARGS=""
    export SKIP_TESTS="true"
    When call build_gradle_args
    The output should include "-x test"
  End

  It 'includes sonar args for master branch'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="master"
    export GITHUB_EVENT_NAME="push"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.projectVersion=1.0.0-SNAPSHOT"
    The output should include "-Dsonar.analysis.sha1=abc123def456"
  End

  It 'includes sonar args for maintenance branch'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="branch-1.0"
    export GITHUB_EVENT_NAME="push"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.branch.name=branch-1.0"
  End

  It 'includes sonar args for PR'
    export GRADLE_ARGS=""
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST="123"
    export PULL_REQUEST_SHA="base123"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.analysis.prNumber=123"
  End

  It 'includes sonar args for long-lived feature branch'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="feature/long/my-feature"
    export GITHUB_EVENT_NAME="push"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.branch.name=feature/long/my-feature"
    The output should include "-Dsonar.analysis.sha1=abc123def456"
  End

  It 'includes additional gradle args'
    export GRADLE_ARGS="--parallel --max-workers=4"
    When call build_gradle_args
    The output should include "--parallel"
    The output should include "--max-workers=4"
  End
End

Describe 'get_build_type'
  It 'returns default branch for master'
    export GITHUB_REF_NAME="master"
    export GITHUB_EVENT_NAME="push"
    When call get_build_type
    The output should equal "default branch"
  End

  It 'returns maintenance branch'
    export GITHUB_REF_NAME="branch-1.0"
    export GITHUB_EVENT_NAME="push"
    When call get_build_type
    The output should equal "maintenance branch"
  End

  It 'returns pull request'
    export GITHUB_EVENT_NAME="pull_request"
    When call get_build_type
    The output should equal "pull request"
  End

  It 'returns dogfood branch'
    export GITHUB_REF_NAME="dogfood-on-main"
    export GITHUB_EVENT_NAME="push"
    When call get_build_type
    The output should equal "dogfood branch"
  End

  It 'returns long-lived feature branch'
    export GITHUB_REF_NAME="feature/long/my-feature"
    export GITHUB_EVENT_NAME="push"
    When call get_build_type
    The output should equal "long-lived feature branch"
  End

  It 'returns regular build for other branches'
    export GITHUB_REF_NAME="feature/test"
    export GITHUB_EVENT_NAME="push"
    When call get_build_type
    The output should equal "regular build"
  End
End


Describe 'gradle_build'
  It 'executes gradle build successfully'
    export GRADLE_ARGS=""
    Mock orchestrate_sonar_platforms
      echo "orchestrator executed"
    End
    Mock get_build_type
      echo "default branch"
    End

    When call gradle_build
    The output should include "Starting default branch build"
    The output should include "Sonar Platform: next"
    The output should include "Run Shadow Scans: false"
    The output should include "orchestrator executed"
  End
End

Describe 'sonar_scanner_implementation()'
  It 'runs gradle with sonar for current platform'
    export GRADLE_ARGS=""
    export SONAR_HOST_URL="https://next.sonarqube.com"
    Mock build_gradle_args
      echo "--no-daemon build sonar"
    End

    When call sonar_scanner_implementation
    The line 2 should include "gradle --no-daemon build sonar"
    The lines of stdout should equal 2
  End
End

Describe 'orchestrate_sonar_platforms integration()'
  It 'runs analysis on single platform when shadow scans disabled'
    export RUN_SHADOW_SCANS="false"
    export SONAR_PLATFORM="next"
    export GRADLE_ARGS=""
    Mock build_gradle_args
      echo "--no-daemon build sonar"
    End

    When call orchestrate_sonar_platforms
    The line 1 should include "=== ORCHESTRATOR: Running Sonar analysis on selected platform: next ==="
    The line 2 should equal "Using Sonar platform: next (URL: next.sonarqube.com, Region: none)"
    The line 4 should equal "gradle --no-daemon build sonar"
    The lines of stdout should equal 4
  End

  It 'runs analysis on all platforms when shadow scans enabled'
    export RUN_SHADOW_SCANS="true"
    export SONAR_PLATFORM="next"
    export GRADLE_ARGS=""
    Mock build_gradle_args
      echo "--no-daemon build sonar"
    End

    When call orchestrate_sonar_platforms
    The output should include "=== ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled) ==="
    The output should include "--- ORCHESTRATOR: Analyzing with platform: next ---"
    The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-us ---"
    The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-eu ---"
    The output should include "=== ORCHESTRATOR: Completed Sonar analysis on all platforms ==="
  End
End

Describe 'set_gradle_cmd()'
  It 'uses gradlew when available'
    unset GRADLE_CMD
    Mock command_exists
      # For ./gradlew -version call
      if [[ "$1" == "./gradlew" && "$2" == "-version" ]]; then
        echo "Gradle 7.0"
      fi
    End
    touch ./gradlew
    chmod +x ./gradlew

    When call set_gradle_cmd
    The status should be success
    The variable GRADLE_CMD should equal "./gradlew"

    rm -f ./gradlew
  End

  It 'uses gradle when gradlew not found'
    unset GRADLE_CMD
    Mock command_exists
      if [[ "$1" == "gradle" && $# -eq 1 ]]; then
        # This is the availability check - return success silently
        true
      elif [[ "$1" == "gradle" && "$2" == "-version" ]]; then
        # This is the version check - output version
        echo "Gradle 7.0"
      fi
    End
    # Ensure no gradlew exists
    rm -f ./gradlew

    When call set_gradle_cmd
    The status should be success
    The variable GRADLE_CMD should equal "gradle"

    # Clean up just in case
    rm -f ./gradlew
  End

  It 'fails when neither gradle nor gradlew are available'
    unset GRADLE_CMD
    rm -f ./gradlew

    # Mock command_exists to fail for gradle
    Mock command_exists
      if [[ "$1" == "gradle" ]]; then
        echo "gradle is not installed." >&2
        false
      else
        echo "$1 is not installed." >&2
        false
      fi
    End

    When run set_gradle_cmd
    The status should be failure
    The stderr should include "Neither ./gradlew nor gradle command found!"

    rm -f ./gradlew
  End
End

Describe 'main function'
  It 'executes full sequence'
    unset GRADLE_CMD
    Mock command_exists
      case "$1" in
        java) echo "java ok" ;;
        gradle) echo "gradle ok" ;;
      esac
    End
    Mock set_build_env
      echo "env set"
    End
    Mock set_project_version
      echo "version set"
    End
    Mock gradle_build
      echo "build done"
    End

    When call main
    The status should be success
    The line 1 should equal "java ok"
    The line 2 should equal "gradle ok"
    The line 3 should equal "env set"
    The line 4 should equal "version set"
    The line 5 should equal "build done"
  End
End

Describe 'script execution'
  It 'executes main when build.sh is run directly'
    When run script build-gradle/build.sh
    The status should be success
    The output should include "PROJECT: my-repo"
  End
End
