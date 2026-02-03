#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock java
  echo "java $*"
End
Mock gradle
  if [[ "$*" == "properties --no-scan --no-daemon --console plain" ]]; then
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

readonly GITHUB_EVENT_NAME_PR="pull_request"
readonly GITHUB_REF_NAME_PR="123/merge"

# Environment setup
export ARTIFACTORY_URL="https://dummy.repox/artifactory"
export DEFAULT_BRANCH="master"
export PULL_REQUEST=""
export PULL_REQUEST_SHA=""
export GITHUB_EVENT_NAME="push"
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
export DEPLOY="true"
export DEPLOY_PULL_REQUEST="false"
export SKIP_TESTS="false"
export GRADLE_ARGS=""
export GITHUB_OUTPUT=/dev/null
export CURRENT_VERSION="1.2.3-SNAPSHOT"
# Duplicate environment variables removed
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

common_setup() {
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

Include build-gradle/build.sh

Describe 'set_build_env'
  It 'sets project and default values'
    export PULL_REQUEST=""
    export PULL_REQUEST_SHA=""
    When call set_build_env
    The output should include "PROJECT: my-repo"
    The variable PROJECT should equal "my-repo"
  End

  It 'handles pull request'
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
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

  It 'skips git fetch when sonar platform is none'
    export SONAR_PLATFORM="none"
    When call set_build_env
    The output should include "PROJECT: my-repo"
    The output should include "Skipping git fetch (Sonar analysis disabled)"
    The output should not include "Fetching commit history for SonarQube analysis..."
  End
End

Describe 'should_deploy'
  It 'does not deploy when deployment is disabled'
    export DEPLOY="false"
    When call should_deploy
    The status should be failure
  End

  It 'deploys for master branch'
    When call should_deploy
    The status should be success
  End

  It 'deploys for maintenance branch'
    export GITHUB_REF_NAME="branch-1.0"
    When call should_deploy
    The status should be success
  End

  It 'does not deploy for feature branch'
    export GITHUB_REF_NAME="feature/test"
    When call should_deploy
    The status should be failure
  End

  It 'does not deploy for PR by default'
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
    export DEPLOY_PULL_REQUEST="false"
    When call should_deploy
    The status should be failure
  End

  It 'deploys for PR when enabled'
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
    export DEPLOY_PULL_REQUEST="true"
    When call should_deploy
    The status should be success
  End

  It 'does not deploy when deployment is disabled and pr is enabled'
    export DEPLOY="false"
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
    export DEPLOY_PULL_REQUEST="true"
    When call should_deploy
    The status should be failure
  End

  It 'does not deploy when shadow scans enabled'
    export RUN_SHADOW_SCANS="true"
    When call should_deploy
    The status should be failure
    The lines of stderr should equal 1
    The line 1 of stderr should equal "Shadow scans enabled - disabling deployment"
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
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.projectVersion=1.0.0-SNAPSHOT"
    The output should include "-Dsonar.scm.revision=abc123def456"
  End

  It 'includes sonar args for maintenance branch'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="branch-1.0"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.branch.name=branch-1.0"
  End

  It 'includes sonar args for PR'
    export GRADLE_ARGS=""
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
    export PULL_REQUEST="123"
    export PULL_REQUEST_SHA="base123"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.scm.revision=base123"
    The output should include "-Dsonar.analysis.prNumber=123"
  End

  It 'includes sonar args for long-lived feature branch'
    export GRADLE_ARGS=""
    export GITHUB_REF_NAME="feature/long/my-feature"
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="sonar-token"
    When call build_gradle_args
    The output should include "-Dsonar.branch.name=feature/long/my-feature"
    The output should include "-Dsonar.scm.revision=abc123def456"
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
    When call get_build_type
    The output should equal "default branch"
  End

  It 'returns maintenance branch'
    export GITHUB_REF_NAME="branch-1.0"
    When call get_build_type
    The output should equal "maintenance branch"
  End

  It 'returns pull request'
    export GITHUB_EVENT_NAME="$GITHUB_EVENT_NAME_PR"
    export GITHUB_REF_NAME="$GITHUB_REF_NAME_PR"
    When call get_build_type
    The output should equal "pull request"
  End

  It 'returns dogfood branch'
    export GITHUB_REF_NAME="dogfood-on-main"
    When call get_build_type
    The output should equal "dogfood branch"
  End

  It 'returns long-lived feature branch'
    export GITHUB_REF_NAME="feature/long/my-feature"
    When call get_build_type
    The output should equal "long-lived feature branch"
  End

  It 'returns regular build for other branches'
    export GITHUB_REF_NAME="feature/test"
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

  It 'calls gradle_build_and_analyze directly when sonar platform is none'
    export SONAR_PLATFORM="none"
    export GRADLE_ARGS=""

    # Create minimal gradle.properties and mock gradle command
    echo "version=1.0-SNAPSHOT" > gradle.properties
    echo '#!/bin/bash' > gradle-mock
    echo 'echo "Gradle executed with: $*"' >> gradle-mock
    chmod +x gradle-mock
    export GRADLE_CMD="./gradle-mock"

    Mock get_build_type
      echo "regular build"
    End

    When call gradle_build
    The output should include "Starting regular build build"
    The output should include "Sonar Platform: none"
    The output should include "Gradle command:"
    The output should include "Gradle executed with:"
    The output should not include "=== ORCHESTRATOR:"


    rm -f gradle-mock gradle.properties
  End
End

Describe 'sonar_scanner_implementation()'
  It 'runs gradle with sonar for current platform'
    export GRADLE_ARGS=""
    export SONAR_HOST_URL="https://next.sonarqube.com"
    export DEPLOY="false"
    Mock build_gradle_args
      echo "--no-daemon build sonar"
    End

    When call sonar_scanner_implementation
    The line 2 should include "gradle --no-daemon build sonar"
    The lines of stdout should equal 2
  End
End


Describe 'export_built_artifacts()'
  It 'skips silently on non-deployable branch'
    export GITHUB_REF_NAME="feature/test"
    mkdir -p build/libs
    touch build/libs/app-1.0.jar

    When call export_built_artifacts
    The status should be success
    The output should be blank


    rm -rf build
  End

  It 'captures artifacts on deployable branch and writes to GITHUB_OUTPUT'
    export GITHUB_REF_NAME="master"
    export DEPLOY="true"
    mkdir -p build/libs build/distributions build/reports
    touch build/libs/app-1.0.jar
    touch build/distributions/app-1.0.zip
    touch build/reports/dependency-check.json

    When call export_built_artifacts
    The status should be success
    The lines of stdout should equal 6
    The line 1 should equal "::group::Capturing built artifacts for attestation"
    The line 2 should equal "Found artifacts for attestation:"
    The line 3 should equal "./build/distributions/app-1.0.zip"
    The line 4 should equal "./build/libs/app-1.0.jar"
    The line 5 should equal "./build/reports/dependency-check.json"
    The line 6 should equal "::endgroup::"
    The contents of file "$GITHUB_OUTPUT" should include "artifact-paths<<EOF"
    The contents of file "$GITHUB_OUTPUT" should include "build/libs/app-1.0.jar"
    The contents of file "$GITHUB_OUTPUT" should include "build/distributions/app-1.0.zip"


    rm -rf build
  End
End


Describe 'set_gradle_cmd()'
  It 'uses gradlew when available'
    unset GRADLE_CMD
    Mock check_tool
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
    Mock check_tool
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

    # Mock check_tool to fail for gradle
    Mock check_tool
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
    export DEPLOY="false"
    Mock check_tool
      case "$1" in
        java) echo "java ok" ;;
        gradle) echo "gradle ok" ;;
      esac
    End
    Mock set_build_env
      echo "env set"
    End
    Mock gradle_build
      echo "build done"
    End

    When call main
    The status should be success
    The line 1 should equal "java ok"
    The line 2 should equal "gradle ok"
    The line 3 should equal "env set"
    The line 4 should equal "build done"
  End
End

Describe 'script execution'
  It 'executes main when build.sh is run directly'
    When run script build-gradle/build.sh
    The status should be success
    The output should include "PROJECT: my-repo"
  End
End
