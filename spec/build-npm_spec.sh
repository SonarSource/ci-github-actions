#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock jq
  if [[ "$*" == "--version" ]]; then
    echo "jq-1.8.1"
  elif [[ "$*" == "-r .version package.json" ]]; then
    if [[ "${MOCK_VERSION:-}" ]]; then
      echo "${MOCK_VERSION}"
    else
      echo "1.2.3-SNAPSHOT"
    fi
  elif [[ "$*" == "-r '.buildInfoUiUrl // empty'" ]]; then
    echo "https://repox.jfrog.io/ui/builds/test-project/42/123456/published"
  else
    echo "jq $*"
  fi
End

Mock jf
  if [[ "$*" == "--version" ]]; then
    echo "jf version 2.77.0"
  elif [[ "$*" == "rt build-publish test-project 42" ]]; then
    echo '{"buildInfoUiUrl": "https://repox.jfrog.io/ui/builds/test-project/42/123456/published"}'
  else
    echo "jf $*"
  fi
End

Mock npm
  if [[ "$*" == "--version" ]]; then
    echo "10.2.4"
  elif [[ "$*" == "ci" ]]; then
    echo "npm ci completed"
  elif [[ "$*" == "test" ]]; then
    echo "npm test completed"
  elif [[ "$*" == "run build" ]]; then
    echo "npm run build completed"
  elif [[ "$*" =~ ^version ]]; then
    echo "npm version completed"
  else
    echo "npm $*"
  fi
End

Mock npx
  if [[ "$*" =~ sonarqube-scanner ]]; then
    echo "SonarQube scanner completed"
  else
    echo "npx $*"
  fi
End

Mock git
  echo "git $*"
End

# Set up environment variables
export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_REF_NAME="main"
export GITHUB_EVENT_NAME="push"
export BUILD_NUMBER="42"
export GITHUB_RUN_ID="12345"
export GITHUB_SHA="abc123"
export GITHUB_OUTPUT=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_ACCESS_TOKEN="reader-token"
export ARTIFACTORY_DEPLOY_REPO="test-repo"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="deploy-token"
export SONAR_HOST_URL="https://sonar.example.com"
export SONAR_TOKEN="sonar-token"
export DEPLOY_PULL_REQUEST="false"
export SKIP_TESTS="false"
export DEFAULT_BRANCH="main"
export PULL_REQUEST="false"
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
echo '{}' > "$GITHUB_EVENT_PATH"

# Create mock package.json
echo '{"version": "1.2.3-SNAPSHOT", "name": "test-project"}' > package.json

Describe 'build-npm/build.sh'
  It 'does not run build_npm() if the script is sourced'
    When run source build-npm/build.sh
    The status should be success
    The output should equal ""
  End

  It 'runs main() when executed directly'
    When run script build-npm/build.sh
    The status should be success
    The output should include "=== NPM Build, Deploy, and Analyze ==="
    The output should include "Branch: main"
    The output should include "Pull Request: false"
    The stderr should include "WARN: Version '1.2.3-42' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
  End

  Describe 'Git utility functions'
    BeforeEach 'source build-npm/build.sh'

    It 'detects main branch correctly'
      export GITHUB_REF_NAME="main"
      export DEFAULT_BRANCH="main"
      When call is_default_branch
      The status should be success
    End

    It 'detects master branch correctly'
      export GITHUB_REF_NAME="master"
      export DEFAULT_BRANCH="master"
      When call is_default_branch
      The status should be success
    End

    It 'detects pull request correctly'
      export GITHUB_EVENT_NAME="pull_request"
      When call is_pull_request
      The status should be success
    End

    It 'detects dogfood branch correctly'
      export GITHUB_REF_NAME="dogfood-on-feature"
      When call is_dogfood_branch
      The status should be success
    End

    It 'detects long-lived feature branch correctly'
      export GITHUB_REF_NAME="feature/long/test-feature"
      When call is_long_lived_feature_branch
      The status should be success
    End

    It 'detects merge queue branch correctly'
      export GITHUB_REF_NAME="gh-readonly-queue/main/pr-123-abc"
      When call is_merge_queue_branch
      The status should be success
    End
  End

  Describe 'Version utility functions'
    BeforeEach 'source build-npm/build.sh'

    It 'sets project version with build ID for non-maintenance branches'
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      export GITHUB_REF_NAME="main"
      When call set_project_version
      The status should be success
      The output should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3-42"
      The variable PROJECT_VERSION should equal "1.2.3-42"
      The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
    End

    It 'keeps original version for maintenance branches initially'
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      export GITHUB_REF_NAME="branch-1.2"
      export GITHUB_EVENT_NAME="push"
      When call set_project_version
      The status should be success
      The variable PROJECT_VERSION should equal "1.2.3-SNAPSHOT"
      The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
    End

    It 'validates version format correctly'
      When call check_version_format "1.2.3.4"
      The status should be success
      The output should equal ""
    End

    It 'warns about invalid version format'
      When call check_version_format "1.2.3-42"
      The status should be success
      The stderr should include "WARN: Version '1.2.3-42' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
    End
  End

  Describe 'Build pipeline functions'
    BeforeEach 'source build-npm/build.sh'

    It 'runs standard pipeline with sonar and deploy'
      export SKIP_TESTS="false"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call run_standard_pipeline true true -Dsonar.projectVersion="1.0.0"
      The status should be success
      The output should include "Installing npm dependencies..."
      The output should include "Running tests..."
      The output should include "SonarQube scanner completed"
      The output should include "Building project..."
    End

    It 'runs standard pipeline without sonar'
      export SKIP_TESTS="false"
      When call run_standard_pipeline false false
      The status should be success
      The output should include "Installing npm dependencies..."
      The output should include "Running tests..."
      The output should include "Building project..."
      The output should not include "SonarQube scanner"
    End

    It 'skips tests when SKIP_TESTS is true'
      export SKIP_TESTS="true"
      When call run_standard_pipeline false false
      The status should be success
      The output should include "Skipping tests (SKIP_TESTS=true)"
      The output should not include "Running tests..."
    End
  End

  Describe 'SonarQube scanner'
    BeforeEach 'source build-npm/build.sh'

    It 'runs sonar scanner with correct parameters'
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call run_sonar_scanner -Dsonar.projectVersion="1.0.0"
      The status should be success
      The output should include "SonarQube scanner completed"
      The output should include "SonarQube scanner finished"
    End
  End

  Describe 'JFrog deployment'
    BeforeEach 'source build-npm/build.sh'

    It 'runs jfrog publish with correct configuration'
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call jfrog_npm_publish
      The status should be success
      The output should include "DEBUG: Removing existing JFrog config..."
      The output should include "DEBUG: Adding JFrog config..."
      The output should include "DEBUG: Configuring NPM repositories..."
      The output should include "DEBUG: Publishing NPM package..."
      The output should include "DEBUG: Publishing build info..."
      The output should include "DEBUG: JFrog operations completed successfully"
    End

    It 'fails when missing ARTIFACTORY_URL'
      unset ARTIFACTORY_URL
      When run jfrog_npm_publish
      The status should be failure
      The stderr should include "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
    End

    It 'fails when missing ARTIFACTORY_DEPLOY_ACCESS_TOKEN'
      unset ARTIFACTORY_DEPLOY_ACCESS_TOKEN
      When run jfrog_npm_publish
      The status should be failure
      The stderr should include "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
    End
  End

  Describe 'Build scenarios'
    BeforeEach 'source build-npm/build.sh'

    It 'builds main branch correctly'
      export GITHUB_REF_NAME="main"
      export DEFAULT_BRANCH="main"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Building main branch ======="
      The output should include "Current version: 1.2.3-SNAPSHOT"
      The output should include "Installing npm dependencies..."
      The output should include "SonarQube scanner completed"
      The output should include "Building project..."
      The stderr should include "WARN: Version '1.2.3-42' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
    End

    It 'builds maintenance branch with SNAPSHOT version'
      export GITHUB_REF_NAME="branch-1.2"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Building maintenance branch ======="
      The output should include "======= Found SNAPSHOT version ======="
      The output should include "Set npm version with build ID: 42."
      The stderr should include "WARN: Version '1.2.3-SNAPSHOT' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
    End

    It 'builds pull request without deploy'
      export GITHUB_REF_NAME="feature/test"
      export GITHUB_EVENT_NAME="pull_request"
      export DEPLOY_PULL_REQUEST="false"
      export PULL_REQUEST="123"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Building pull request ======="
      The output should include "======= no deploy ======="
      The output should include "Installing npm dependencies..."
      The output should include "SonarQube scanner completed"
      The output should not include "DEBUG: JFrog operations"
    End

    It 'builds pull request with deploy when enabled'
      export GITHUB_REF_NAME="feature/test"
      export GITHUB_EVENT_NAME="pull_request"
      export DEPLOY_PULL_REQUEST="true"
      export PULL_REQUEST="123"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Building pull request ======="
      The output should include "======= with deploy ======="
      The output should include "DEBUG: JFrog operations completed successfully"
      The stderr should include "WARN: Version '1.2.3-42' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
    End

    It 'builds dogfood branch without sonar'
      export GITHUB_REF_NAME="dogfood-on-feature"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Build dogfood branch ======="
      The output should include "Installing npm dependencies..."
      The output should not include "SonarQube scanner"
      The output should include "DEBUG: JFrog operations completed successfully"
      The stderr should include "WARN: Version '1.2.3-42' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'"
    End

    It 'builds long-lived feature branch without deploy'
      export GITHUB_REF_NAME="feature/long/test-feature"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Build long-lived feature branch ======="
      The output should include "Installing npm dependencies..."
      The output should include "SonarQube scanner completed"
      The output should not include "DEBUG: JFrog operations"
    End

    It 'builds other branches without sonar or deploy'
      export GITHUB_REF_NAME="feature/test"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Build other branch ======="
      The output should include "Installing npm dependencies..."
      The output should not include "SonarQube scanner"
      The output should not include "DEBUG: JFrog operations"
    End
  End

  Describe 'Tool checking'
    BeforeEach 'source build-npm/build.sh'

    It 'checks required tools are available'
      When call check_tool jq --version
      The status should be success
      The output should include "jq-1.8.1"
    End

    It 'fails when tool is not available'
      When run check_tool nonexistent-tool --version
      The status should be failure
      The stderr should include "nonexistent-tool is not installed."
    End
  End

  Describe 'Environment setup'
    BeforeEach 'source build-npm/build.sh'

    It 'sets up build environment correctly'
      export GITHUB_REPOSITORY="my-org/test-project"
      When call set_build_env
      The status should be success
      The output should include "PROJECT: test-project"
      The output should include "Fetching commit history for SonarQube analysis..."
      The variable PROJECT should equal "test-project"
    End
  End

  Describe 'Git fetch functionality'
    BeforeEach 'source build-npm/build.sh'

    It 'calls git fetch unshallow'
      When call git_fetch_unshallow
      The status should be success
      The output should include "git"
    End
  End
End
