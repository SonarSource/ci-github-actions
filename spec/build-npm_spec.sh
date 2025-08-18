#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock jq
  if [[ "$*" == "--version" ]]; then
    echo "jq-1.8.1"
  elif [[ "$*" == "-r .version package.json" ]]; then
    if [[ "${MOCK_VERSION+set}" ]]; then
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
export SONAR_PLATFORM="next"
export RUN_SHADOW_SCANS="false"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube-us.example.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
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
  Include build-npm/build.sh

  Describe 'Tool checking'
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
    It 'fetches base ref for pull requests when GITHUB_BASE_REF is set'
      export GITHUB_BASE_REF="main"
      When call git_fetch_unshallow
      The status should be success
      The output should include "Fetch main for SonarQube analysis..."
      The output should include "git fetch --filter=blob:none origin main"
    End
  End


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
    The line 2 should equal "git fetch --unshallow --filter=blob:none"
  End

  It 'fallbacks and fetches base branch for pull request'
    export GITHUB_EVENT_NAME="pull_request"
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
    The line 2 should equal "git fetch --filter=blob:none origin def_main"
  End
End

Describe 'Branch detection functions'
  It 'detects merge queue branch'
    export GITHUB_REF_NAME="gh-readonly-queue/main/pr-123-abc123"
    When call is_merge_queue_branch
    The status should be success
  End

  It 'does not detect non-merge queue branch as merge queue'
    export GITHUB_REF_NAME="feature/test"
    When call is_merge_queue_branch
    The status should be failure
  End
End

Describe 'Version format checking'
  It 'warns about invalid version format'
    When call check_version_format "invalid-version"
    The status should be success
    The stderr should include "WARN: Version 'invalid-version' does not match semantic versioning format"
  End

  It 'accepts valid semantic version without warning'
    When call check_version_format "1.2.3-beta.1"
    The status should be success
    The stderr should be blank
  End
End

Describe 'Maintenance branch 2-digit version handling'
  It 'handles 2-digit version in maintenance branch SNAPSHOT'
    export MOCK_VERSION="1.2-SNAPSHOT"
    export GITHUB_REF_NAME="branch-1.2"
    export GITHUB_EVENT_NAME="push"
    export PROJECT="test-project"
    export BUILD_NUMBER="42"
    When call build_npm
    The status should be success
    The output should include "Replacing version 1.2-SNAPSHOT with 1.2.0-42"
  End
End

  Describe 'Version error handling'
    It 'exits with error when version cannot be read from package.json'
      export MOCK_VERSION="null"
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      export GITHUB_REF_NAME="main"
      When run set_project_version
      The status should be failure
      The stderr should include "Could not get version from package.json"
    End

    It 'exits with error when version is empty'
      export MOCK_VERSION=""
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      export GITHUB_REF_NAME="main"
      When run set_project_version
      The status should be failure
      The stderr should include "Could not get version from package.json"
    End

    It 'adds .0 to 2-digit version numbers'
      export MOCK_VERSION="1.2-SNAPSHOT"
      export BUILD_NUMBER="42"
      export GITHUB_OUTPUT=/dev/null
      export GITHUB_REF_NAME="main"
      When call set_project_version
      The status should be success
      The output should include "Replacing version 1.2-SNAPSHOT with 1.2.0-42"
      The variable PROJECT_VERSION should equal "1.2.0-42"
    End
  End

  Describe 'Build scenarios'
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
      The output should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3-42"
    End

    It 'builds maintenance branch with RELEASE version'
      export MOCK_VERSION="1.2.3"  # No SNAPSHOT suffix, valid semantic version
      export GITHUB_REF_NAME="branch-1.2"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "======= Building maintenance branch ======="
      The output should include "======= Found RELEASE version ======="
      The output should include "======= Deploy 1.2.3 ======="
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

    It 'skips tests when SKIP_TESTS is true'
      export SKIP_TESTS="true"
      export GITHUB_REF_NAME="main"
      export DEFAULT_BRANCH="main"
      export GITHUB_EVENT_NAME="push"
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When call build_npm
      The status should be success
      The output should include "Skipping tests (SKIP_TESTS=true)"
      The output should not include "Running tests..."
    End
  End

  Describe 'JFrog deployment error scenarios'
    It 'fails when missing ARTIFACTORY_URL'
      unset ARTIFACTORY_URL
      export PROJECT="test-project"
      export BUILD_NUMBER="42"
      When run jfrog_npm_publish
      The status should be failure
      The stderr should include "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
    End

  End

  Describe 'Sonar platform configuration'
    It 'sets sonar variables for next platform'
      When call set_sonar_platform_vars "next"
      The status should be success
      The output should include "Using Sonar platform: next (URL: https://next.sonarqube.com)"
      The variable SONAR_HOST_URL should equal "https://next.sonarqube.com"
      The variable SONAR_TOKEN should equal "next-token"
    End

    It 'sets sonar variables for sqc-us platform'
      When call set_sonar_platform_vars "sqc-us"
      The status should be success
      The output should include "Using Sonar platform: sqc-us (URL: https://sonarqube-us.example.com)"
      The variable SONAR_HOST_URL should equal "https://sonarqube-us.example.com"
      The variable SONAR_TOKEN should equal "sqc-us-token"
    End

    It 'sets sonar variables for sqc-eu platform'
      When call set_sonar_platform_vars "sqc-eu"
      The status should be success
      The output should include "Using Sonar platform: sqc-eu (URL: https://sonarcloud.io)"
      The variable SONAR_HOST_URL should equal "https://sonarcloud.io"
      The variable SONAR_TOKEN should equal "sqc-eu-token"
    End

    It 'fails with invalid platform'
      When run set_sonar_platform_vars "invalid"
      The status should be failure
      The stderr should include "ERROR: Invalid Sonar platform 'invalid'. Must be one of: next, sqc-us, sqc-eu"
    End
  End

  Describe 'Sonar analysis functionality'
    It 'runs single platform analysis when shadow scans disabled'
      export RUN_SHADOW_SCANS="false"
      export SONAR_PLATFORM="next"
      export PROJECT_VERSION="1.2.3-42"
      When call run_sonar_analysis "-Dsonar.test=value"
      The status should be success
      The output should include "=== Running Sonar analysis on selected platform: next ==="
      The output should include "Using Sonar platform: next"
      The output should include "SonarQube scanner finished for platform: next.sonarqube.com"
      The output should not include "shadow scan enabled"
    End

    It 'runs multi-platform analysis when shadow scans enabled'
      export RUN_SHADOW_SCANS="true"
      export SONAR_PLATFORM="next"
      export PROJECT_VERSION="1.2.3-42"
      When call run_sonar_analysis "-Dsonar.test=value"
      The status should be success
      The output should include "=== Running Sonar analysis on all platforms (shadow scan enabled) ==="
      The output should include "--- Analyzing with platform: next ---"
      The output should include "--- Analyzing with platform: sqc-us ---"
      The output should include "--- Analyzing with platform: sqc-eu ---"
      The output should include "=== Completed Sonar analysis on all platforms ==="
    End
  End

  Describe 'Shadow scans deployment prevention'
    It 'disables deployment when shadow scans enabled on main branch'
      export GITHUB_REF_NAME="main"
      export DEFAULT_BRANCH="main"
      export GITHUB_EVENT_NAME="push"
      export RUN_SHADOW_SCANS="true"
      export CURRENT_VERSION="1.2.3-SNAPSHOT"
      export PROJECT_VERSION="1.2.3-42"
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
      export CURRENT_VERSION="1.2.3-SNAPSHOT"
      export PROJECT_VERSION="1.2.3-42"
      export BUILD_NUMBER="42"
      When call get_build_config
      The status should be success
      The output should not include "shadow scans enabled"
      The variable BUILD_ENABLE_DEPLOY should equal "true"
      The variable BUILD_ENABLE_SONAR should equal "true"
    End
  End

  Describe 'Full build with shadow scans'
    It 'displays shadow scan information in build output'
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

  Describe 'Main function execution'
    It 'runs main function when executed directly'
      When run script build-npm/build.sh
      The status should be success
      The output should include "=== NPM Build, Deploy, and Analyze ==="
    End
  End
End
