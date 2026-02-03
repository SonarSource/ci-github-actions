#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock jq
  if [[ "$*" == "--version" ]]; then
    echo "jq-1.8.1"
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
    echo "npx $*"
  else
    echo "npx $*"
  fi
End

Mock git
  if [[ "$*" == "rev-parse --is-shallow-repository --quiet" ]]; then
    if [[ "${GITHUB_BASE_REF:-}" ]]; then
      return 1  # Not shallow, will trigger base ref fetch
    else
      return 0  # Is shallow, will trigger unshallow
    fi
  else
    echo "git $*"
  fi
End

# Minimal environment variables
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="deploy-token"
export ARTIFACTORY_DEPLOY_REPO="test-repo"
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export BUILD_NAME="dummy-project"
export BUILD_NUMBER="42"
export PROJECT_VERSION="1.2.3-42"
export CURRENT_VERSION="1.2.3-SNAPSHOT"
export DEFAULT_BRANCH="main"
export DEPLOY_PULL_REQUEST="false"
export GITHUB_EVENT_NAME="push"
export GITHUB_OUTPUT=/dev/null
export GITHUB_REF_NAME="main"
export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_RUN_ID="12345"
export GITHUB_SHA="abc123"
export NEXT_TOKEN="next-token"
export NEXT_URL="https://next.sonarqube.com"
export PULL_REQUEST="false"
export RUN_SHADOW_SCANS="false"
export SKIP_TESTS="false"
export SONAR_PLATFORM="next"
export SQC_EU_TOKEN="sqc-eu-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_US_TOKEN="sqc-us-token"
export SQC_US_URL="https://sonarqube-us.example.com"
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
echo '{}' > "$GITHUB_EVENT_PATH"

# Create mock package.json
echo '{"version": "1.2.3-SNAPSHOT", "name": "test-project"}' > package.json

Describe 'build-npm/build.sh'
  It 'does not run main when sourced'
    When run source build-npm/build.sh
    The status should be success
    The output should equal ""
  End
  It 'runs main function when executed directly'
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    When run script build-npm/build.sh
    The status should be success
    The output should include "=== NPM Build, Deploy, and Analyze ==="
  End
End

Include build-npm/build.sh

Describe 'git_fetch_unshallow()'
  It 'fetches unshallow when repository is shallow'
    unset GITHUB_BASE_REF
    # Override the main git mock temporarily
    git() {
      case "$*" in
        "rev-parse --is-shallow-repository --quiet") return 0;;
        *) echo "git $*" ;;
      esac
    }
    When call git_fetch_unshallow
    The lines of stdout should equal 2
    The line 1 should equal "Fetch Git references for SonarQube analysis..."
    The line 2 should equal "git fetch --unshallow"
  End

  It 'fallbacks and fetches base branch for pull request'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export GITHUB_BASE_REF="def_main"
    Mock git
      case "$*" in
        *"rev-parse --is-shallow-repository"*) return 1;;
        *) echo "git $*" ;;
      esac
    End
    When call git_fetch_unshallow
    The lines of stdout should equal 2
    The line 1 should start with "Fetch def_main"
    The line 2 should equal "git fetch origin def_main"
  End

  It 'skips git fetch when sonar platform is none'
    export SONAR_PLATFORM="none"
    When call git_fetch_unshallow
    The status should be success
    The lines of stdout should equal 1
    The line 1 should equal "Skipping git fetch (Sonar analysis disabled)"
  End
End

Describe 'export_built_artifacts()'
  It 'captures artifacts when should-deploy=true and writes to GITHUB_OUTPUT'
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    rm -rf .attestation-artifacts
    mkdir -p .attestation-artifacts
    touch .attestation-artifacts/test-1.2.3.tgz
    echo "deployed=true" >> "$GITHUB_OUTPUT"

    When call export_built_artifacts
    The status should be success
    The lines of stdout should equal 4
    The line 1 should equal "::group::Capturing built artifacts for attestation"
    The line 2 should equal "Found artifact(s) for attestation:"
    The line 3 should equal ".attestation-artifacts/test-1.2.3.tgz"
    The line 4 should equal "::endgroup::"
    The contents of file "$GITHUB_OUTPUT" should include "artifact-paths<<EOF"
    The contents of file "$GITHUB_OUTPUT" should include ".attestation-artifacts/test-1.2.3.tgz"
  End

  It 'skips silently when should-deploy=false'
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    mkdir -p .attestation-artifacts
    touch .attestation-artifacts/ignored-1.0.0.tgz
    echo "deployed=false" >> "$GITHUB_OUTPUT"

    When call export_built_artifacts
    The status should be success
    The output should be blank
    rm -rf .attestation-artifacts
  End
End

Describe 'build_npm()'
  export PROJECT="test-project"

  It 'builds main branch correctly'
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Building main branch ======="
    The output should include "Installing npm dependencies..."
    The output should include "npx -- @sonar/scan"
    The output should include "Building project..."
  End

  It 'builds maintenance branch with SNAPSHOT version'
    export GITHUB_REF_NAME="branch-1.2"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The line 8 should equal "======= Building maintenance branch ======="
    The line 16 should include "-Dsonar.projectVersion=1.2.3-SNAPSHOT"
  End

  It 'builds maintenance branch with RELEASE version'
    export CURRENT_VERSION="1.2.3"
    export PROJECT_VERSION="1.2.3" # No SNAPSHOT suffix, valid semantic version
    export GITHUB_REF_NAME="branch-1.2"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The line 8 should equal "======= Building maintenance branch ======="
    The line 16 should include "-Dsonar.projectVersion=1.2.3"
  End

  It 'builds pull request without deploy'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export DEPLOY_PULL_REQUEST="false"
    export PULL_REQUEST="123"
    export PULL_REQUEST_SHA="pr-base-sha-123"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Building pull request ======="
    The output should include "======= no deploy ======="
    The output should include "Installing npm dependencies..."
    The output should include "npx -- @sonar/scan"
    The output should not include "DEBUG: JFrog operations"
  End

  It 'builds pull request with deploy when enabled'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export DEPLOY_PULL_REQUEST="true"
    export PULL_REQUEST="123"
    export PULL_REQUEST_SHA="pr-base-sha-123"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Building pull request ======="
    The output should include "======= with deploy ======="
  End

  It 'builds dogfood branch without sonar'
    export GITHUB_REF_NAME="dogfood-on-feature"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Build dogfood branch ======="
    The output should include "Installing npm dependencies..."
    The output should not include "SonarQube scanner"
  End

  It 'builds long-lived feature branch without deploy'
    export GITHUB_REF_NAME="feature/long/test-feature"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Build long-lived feature branch ======="
    The output should include "Installing npm dependencies..."
    The output should include "npx -- @sonar/scan"
    The output should not include "DEBUG: JFrog operations"
  End

  It 'builds other branches without sonar or deploy'
    export GITHUB_REF_NAME="feature/test"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "======= Build other branch ======="
    The output should include "Installing npm dependencies..."
    The output should not include "SonarQube scanner"
    The output should not include "DEBUG: JFrog operations"
  End

  It 'skips tests when SKIP_TESTS is true'
    export SKIP_TESTS="true"
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export GITHUB_EVENT_NAME="push"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "Skipping tests (SKIP_TESTS=true)"
    The output should not include "Running tests..."
  End
End


Describe 'sonar_scanner_implementation()'
  It 'runs sonar scanner with base parameters'
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="test-token"
    export BUILD_NUMBER="42"
    export GITHUB_RUN_ID="12345"
    export GITHUB_SHA="abc123"
    export GITHUB_REPOSITORY="test/repo"
    When call sonar_scanner_implementation
    The status should be success
    The output should include "npx -- @sonar/scan"
    The output should include "-Dsonar.host.url=https://sonar.example.com"
    The output should include "-Dsonar.token=test-token"
    The output should include "-Dsonar.analysis.buildNumber=42"
    The output should include "-Dsonar.analysis.pipeline=12345"
    The output should include "-Dsonar.analysis.repository=test/repo"
    The output should include "-Dsonar.projectVersion=1.2.3"
  End

  It 'runs sonar scanner with region parameter for sqc-us'
    export SONAR_HOST_URL="https://sonarqube-us.example.com"
    export SONAR_TOKEN="us-token"
    export SONAR_REGION="us"
    export BUILD_NUMBER="42"
    export GITHUB_RUN_ID="12345"
    export GITHUB_SHA="abc123"
    export GITHUB_REPOSITORY="test/repo"
    When call sonar_scanner_implementation
    The status should be success
    The output should include "-Dsonar.region=us"
  End

  It 'runs sonar scanner with additional parameters'
    export SONAR_HOST_URL="https://sonar.example.com"
    export SONAR_TOKEN="test-token"
    export BUILD_NUMBER="42"
    export GITHUB_RUN_ID="12345"
    export GITHUB_SHA="abc123"
    export GITHUB_REPOSITORY="test/repo"
    When call sonar_scanner_implementation "-Dsonar.pullrequest.key=123" "-Dsonar.branch.name=feature"
    The status should be success
    The output should include "-Dsonar.pullrequest.key=123"
    The output should include "-Dsonar.branch.name=feature"
  End

End

Describe 'get_build_config()'
  It 'disables deployment when shadow scans enabled on main branch'
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export GITHUB_EVENT_NAME="push"
    export RUN_SHADOW_SCANS="true"
    export BUILD_NUMBER="42"
    When call get_build_config
    The status should be success
    The output should include "======= Shadow scans enabled - disabling deployment to prevent duplicate artifacts ======="
    The variable BUILD_ENABLE_DEPLOY should equal "false"
    The variable BUILD_ENABLE_SONAR should equal "true"
  End

  It 'allows deployment when shadow scans disabled on main branch'
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export GITHUB_EVENT_NAME="push"
    export RUN_SHADOW_SCANS="false"
    export BUILD_NUMBER="42"
    When call get_build_config
    The status should be success
    The output should not include "shadow scans enabled"
    The variable BUILD_ENABLE_DEPLOY should equal "true"
    The variable BUILD_ENABLE_SONAR should equal "true"
  End
End

Describe 'build_npm()'
  It 'Performs full build with shadow scans'
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export GITHUB_EVENT_NAME="push"
    export RUN_SHADOW_SCANS="true"
    export SONAR_PLATFORM="next"
    export PROJECT="test-project"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "Run Shadow Scans: true"
    The output should include "Sonar Platform: next"
    The output should include "shadow scan enabled"
    The output should not include "DEBUG: JFrog operations"
  End
End
