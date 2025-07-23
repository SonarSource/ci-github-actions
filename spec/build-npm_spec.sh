#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock jq
  if [[ "$*" == "--version" ]]; then
    echo "jq-1.8.1"
  elif [[ "$*" == "-r .version package.json" ]]; then
    echo "1.2.3-SNAPSHOT"
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
export ARTIFACTORY_DEPLOY_REPO="test-repo"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="test-token"
export SONAR_HOST_URL="https://sonar.example.com"
export SONAR_TOKEN="sonar-token"
export DEPLOY_PULL_REQUEST="false"
export SKIP_TESTS="false"
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
    The stderr should include "WARN: Version '1.2.3-42' does not match the expected format"
  End

  Describe 'Git utility functions'
    BeforeEach 'source build-npm/build.sh'

    It 'detects main branch correctly'
      export GITHUB_REF_NAME="main"
      When call is_main_branch
      The status should be success
    End

    It 'detects master branch correctly'
      export GITHUB_REF_NAME="master"
      When call is_main_branch
      The status should be success
    End

    It 'detects maintenance branch correctly'
      export GITHUB_REF_NAME="branch-1.2"
      When call is_maintenance_branch
      The status should be success
    End

    It 'detects pull request correctly'
      export PULL_REQUEST="123"
      When call is_pull_request
      The status should be success
    End
  End

  Describe 'Version utility functions'
    BeforeEach 'source build-npm/build.sh'

    It 'gets current version from package.json'
      When call get_current_version
      The status should be success
      The output should equal "1.2.3-SNAPSHOT"
    End

    It 'sets npm version with build ID'
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      When call set_npm_version_with_build_id "42"
      The status should be success
      The output should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3-42"
    End

    It 'validates version format correctly'
      When call check_version_format "1.2.3.4"
      The status should be success
      The output should equal ""
    End

    It 'warns about invalid version format'
      When call check_version_format "1.2.3-42"
      The status should be success
      The stderr should include "WARN: Version '1.2.3-42' does not match the expected format"
    End
  End

  Describe 'Build pipeline functions'
    BeforeEach 'source build-npm/build.sh'

    It 'runs npm install correctly'
      When call run_npm_install
      The status should be success
      The output should include "Installing npm dependencies..."
      The output should include "npm ci completed"
    End

    It 'runs npm tests when not skipped'
      export SKIP_TESTS="false"
      When call run_npm_tests
      The status should be success
      The output should include "Running tests..."
      The output should include "npm test completed"
    End

    It 'skips npm tests when requested'
      export SKIP_TESTS="true"
      When call run_npm_tests
      The status should be success
      The output should include "Skipping tests (SKIP_TESTS=true)"
    End

    It 'runs npm build correctly'
      When call run_npm_build
      The status should be success
      The output should include "Building project..."
      The output should include "npm run build completed"
    End

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
  End

  Describe 'JFrog deployment'
    BeforeEach 'source build-npm/build.sh'

    It 'fails when missing environment variables'
      unset ARTIFACTORY_URL
      unset ARTIFACTORY_DEPLOY_ACCESS_TOKEN
      When run jfrog_npm_publish
      The status should be failure
      The stderr should include "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
    End
  End
End
