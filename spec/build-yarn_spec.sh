#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

# Mock external commands
Mock jq
  case "$*" in
    "--version") echo "jq-1.8.1" ;;
    "-r .version package.json") echo "${MOCK_VERSION:-1.2.3-SNAPSHOT}" ;;
    "-r '.buildInfoUiUrl // empty'") echo "https://repox.jfrog.io/ui/builds/test-project/42/123456/published" ;;
    *) echo "jq $*" ;;
  esac
End

Mock jf
  case "$*" in
    "--version") echo "jf version 2.77.0" ;;
    "rt build-publish test-project 42") echo '{"buildInfoUiUrl": "https://repox.jfrog.io/ui/builds/test-project/42/123456/published"}' ;;
    *) echo "jf $*" ;;
  esac
End

Mock yarn
  case "$*" in
    "--version") echo "4.0.2" ;;
    "install --immutable") echo "yarn install completed" ;;
    "test") echo "yarn test completed" ;;
    "build") echo "yarn build completed" ;;
    *) echo "yarn $*" ;;
  esac
End

Mock npm
  case "$*" in
    "--version") echo "10.2.4" ;;
    *) echo "npm $*" ;;
  esac
End

Mock npx
  if [[ "$*" =~ sonarqube-scanner ]]; then
    echo "npx $*"
  else
    echo "npx $*"
  fi
End

Mock git
  case "$*" in
    "rev-parse --is-shallow-repository --quiet") [[ -z "${GITHUB_BASE_REF:-}" ]] ;;
    *) echo "git $*" ;;
  esac
End

# Setup environment
export GITHUB_REPOSITORY="my-org/test-project" GITHUB_REF_NAME="main" GITHUB_EVENT_NAME="push"
export BUILD_NUMBER="42" GITHUB_RUN_ID="12345" GITHUB_SHA="abc123" GITHUB_OUTPUT=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory" ARTIFACTORY_ACCESS_TOKEN="reader-token"
export ARTIFACTORY_DEPLOY_REPO="test-repo" ARTIFACTORY_DEPLOY_ACCESS_TOKEN="deploy-token"
export SONAR_PLATFORM="next"
export RUN_SHADOW_SCANS="false"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube-us.example.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
export DEPLOY_PULL_REQUEST="false" SKIP_TESTS="false" DEFAULT_BRANCH="main" PULL_REQUEST=""

# Create mock files
setup() {
  echo '{"version": "1.2.3-SNAPSHOT", "name": "test-project"}' > package.json
  touch yarn.lock
}
Before "setup"

# Source shared functions before including build script
Include shared/common-functions.sh

Describe 'build-yarn/build.sh'
  Include build-yarn/build.sh

  Describe 'check_tool()'
    It 'succeeds when tool exists'
      When call check_tool jq --version
      The status should be success
      The output should include "jq-1.8.1"
    End

    It 'fails when tool missing'
      When call check_tool nonexistent --version
      The status should be failure
      The stderr should include "nonexistent is not installed."
    End
  End

  Describe 'set_build_env()'
    It 'sets PROJECT and validates files'
      When call set_build_env
      The status should be success
      The output should include "PROJECT: test-project"
      The variable PROJECT should equal "test-project"
    End

    It 'fails when package.json is missing'
      mv package.json package.json.backup
      When run set_build_env
      The status should be failure
      The stderr should include "ERROR: package.json file not found in current directory."
      The stdout should include "PROJECT: test-project"
      mv package.json.backup package.json
    End

    It 'fails when yarn.lock is missing'
      mv yarn.lock yarn.lock.backup
      When run set_build_env
      The status should be failure
      The stderr should include "ERROR: yarn.lock file not found. This is required for yarn --immutable installs."
      The stdout should include "PROJECT: test-project"
      mv yarn.lock.backup yarn.lock
    End

  End

  Describe 'git_fetch_unshallow()'
    It 'fetches unshallow when shallow'
      unset GITHUB_BASE_REF
      When call git_fetch_unshallow
      The output should include "Fetch Git references for SonarQube analysis..."
      The output should include "git fetch --unshallow"
    End

    It 'fetches base ref for PR'
      export GITHUB_BASE_REF="main"
      When call git_fetch_unshallow
      The output should include "Fetch main for SonarQube analysis..."
      The output should include "git fetch origin main"
    End
  End

  Describe 'Branch detection'
    Parameters
      "main" "is_default_branch" "success"
      "branch-1.2" "is_maintenance_branch" "success"
      "dogfood-on-feature" "is_dogfood_branch" "success"
      "feature/long/test" "is_long_lived_feature_branch" "success"
      "gh-readonly-queue/main" "is_merge_queue_branch" "success"
      "other" "is_default_branch" "failure"
    End

    It "detects $1 branch with $2"
      export GITHUB_REF_NAME="$1"
      When call "$2"
      The status should be "$3"
    End

    It 'detects pull request'
      export GITHUB_EVENT_NAME="pull_request"
      When call is_pull_request
      The status should be success
    End
  End

  Describe 'set_project_version()'
    It 'sets version with build number'
      When call set_project_version
      The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
      The variable PROJECT_VERSION should equal "1.2.3-42"
      The lines of output should equal 2
      The line 1 should equal "Replacing version 1.2.3-SNAPSHOT with 1.2.3-42"
      The line 2 should start with "npm version"
    End

    It 'handles 1-digit versions'
      export MOCK_VERSION="1-SNAPSHOT"
      When call set_project_version
      The variable CURRENT_VERSION should equal "1-SNAPSHOT"
      The variable PROJECT_VERSION should equal "1.0.0-42"
      The lines of output should equal 2
      The line 1 should equal "Replacing version 1-SNAPSHOT with 1.0.0-42"
      The line 2 should start with "npm version"
    End

    It 'handles 2-digit versions'
      export MOCK_VERSION="1.2-SNAPSHOT"
      When call set_project_version
      The variable CURRENT_VERSION should equal "1.2-SNAPSHOT"
      The variable PROJECT_VERSION should equal "1.2.0-42"
      The lines of output should equal 2
      The line 1 should equal "Replacing version 1.2-SNAPSHOT with 1.2.0-42"
      The line 2 should start with "npm version"
    End

    It 'fails on invalid version (null)'
      export MOCK_VERSION="null"
      When run set_project_version
      The status should be failure
      The stderr should include "Could not get version from package.json"
      The variable CURRENT_VERSION should be undefined
      The variable PROJECT_VERSION should be undefined
    End

    It 'fails on version with more than 3 digits'
      export MOCK_VERSION="1.2.3.4-SNAPSHOT"
      When call set_project_version
      The status should be failure
      The stderr should include "Unsupported version"
      The variable CURRENT_VERSION should equal "1.2.3.4-SNAPSHOT"
      The variable PROJECT_VERSION should be undefined
    End
  End

  Describe 'run_standard_pipeline()'
    It 'runs full pipeline'
      export PROJECT="test"
      export CURRENT_VERSION="1.2.3"
      export BUILD_ENABLE_SONAR="true" BUILD_ENABLE_DEPLOY="true" BUILD_SONAR_ARGS="-Dsonar.branch.name=main"
      When call run_standard_pipeline
      The output should include "Installing yarn dependencies..."
      The output should include "Running tests..."
      The output should include "npx sonarqube-scanner"
      The output should include "Building project..."
      The output should not include "::debug::JFrog operations completed successfully"
    End

    It 'skips tests when SKIP_TESTS=true'
      export SKIP_TESTS="true" PROJECT="test"
      export CURRENT_VERSION="1.2.3"
      export BUILD_ENABLE_SONAR="false" BUILD_ENABLE_DEPLOY="false" BUILD_SONAR_ARGS=""
      When call run_standard_pipeline
      The output should include "Skipping tests (SKIP_TESTS=true)"
      The output should not include "Running tests..."
    End
  End

  Describe 'jfrog_yarn_publish()'
    It 'publishes successfully'
      export PROJECT="test"
      When call jfrog_yarn_publish
      The output should include "::debug::Build info URL saved:"
    End

    It 'fails without ARTIFACTORY_URL'
      unset ARTIFACTORY_URL
      When run jfrog_yarn_publish
      The status should be failure
      The stderr should include "Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
    End
  End

  Describe 'build_yarn() scenarios'
    Parameters:matrix
      branch:main,branch-1.2,feature/test,dogfood-on-feature,feature/long/test,other
      event:push,pull_request
    End

    It "builds $1 branch on $2"
      export GITHUB_REF_NAME="$1" GITHUB_EVENT_NAME="$2" PROJECT="test"
      [[ "$2" == "pull_request" ]] && export PULL_REQUEST="123"
      When call build_yarn
      The status should be success
      The output should include "=== Yarn Build, Deploy, and Analyze ==="
    End
  End

  Describe 'Sonar platform configuration'
    It 'sets sonar variables for next platform'
      When call set_sonar_platform_vars "next"
      The status should be success
      The line 1 should equal "Using Sonar platform: next (URL: next.sonarqube.com, Region: none)"
      The variable SONAR_HOST_URL should equal "https://next.sonarqube.com"
      The variable SONAR_TOKEN should equal "next-token"
    End

    It 'sets sonar variables for sqc-us platform'
      When call set_sonar_platform_vars "sqc-us"
      The status should be success
      The line 1 should equal "Using Sonar platform: sqc-us (URL: sonarqube-us.example.com, Region: us)"
      The variable SONAR_HOST_URL should equal "https://sonarqube-us.example.com"
      The variable SONAR_TOKEN should equal "sqc-us-token"
    End

    It 'sets sonar variables for sqc-eu platform'
      When call set_sonar_platform_vars "sqc-eu"
      The status should be success
      The line 1 should equal "Using Sonar platform: sqc-eu (URL: sonarcloud.io, Region: none)"
      The variable SONAR_HOST_URL should equal "https://sonarcloud.io"
      The variable SONAR_TOKEN should equal "sqc-eu-token"
    End

    It 'fails with invalid platform'
      When call set_sonar_platform_vars "invalid"
      The status should be failure
      The stderr should include "ERROR: Invalid Sonar platform 'invalid'. Must be one of: next, sqc-us, sqc-eu"
    End
  End

  Describe 'Sonar scanner functionality'
    It 'runs sonar scanner with base parameters'
      export SONAR_HOST_URL="https://sonar.example.com"
      export SONAR_TOKEN="test-token"
      export BUILD_NUMBER="42"
      export GITHUB_RUN_ID="12345"
      export GITHUB_SHA="abc123"
      export GITHUB_REPOSITORY="test/repo"
      export CURRENT_VERSION="1.2.3"
      When call sonar_scanner_implementation
      The status should be success
      The output should include "npx sonarqube-scanner -X"
      The output should include "-Dsonar.host.url=https://sonar.example.com"
      The output should include "-Dsonar.token=test-token"
      The output should include "-Dsonar.analysis.buildNumber=42"
      The output should include "-Dsonar.analysis.pipeline=12345"
      The output should include "-Dsonar.analysis.sha1=abc123"
      The output should include "-Dsonar.analysis.repository=test/repo"
      The output should include "-Dsonar.projectVersion=1.2.3"
      The output should include "-Dsonar.scm.revision=abc123"
    End

    It 'runs sonar scanner with region parameter for sqc-us'
      export SONAR_HOST_URL="https://sonarqube-us.example.com"
      export SONAR_TOKEN="us-token"
      export SONAR_REGION="us"
      export BUILD_NUMBER="42"
      export GITHUB_RUN_ID="12345"
      export GITHUB_SHA="abc123"
      export GITHUB_REPOSITORY="test/repo"
      export CURRENT_VERSION="1.2.3"
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
      export CURRENT_VERSION="1.2.3"
      When call sonar_scanner_implementation "-Dsonar.analysis.prNumber=123" "-Dsonar.branch.name=feature"
      The status should be success
      The output should include "-Dsonar.analysis.prNumber=123"
      The output should include "-Dsonar.branch.name=feature"
    End
  End

  Describe 'Sonar analysis functionality'
    It 'runs single platform analysis when shadow scans disabled'
      export RUN_SHADOW_SCANS="false"
      export SONAR_PLATFORM="next"
      export CURRENT_VERSION="1.2.3"
      export NEXT_URL="https://next.sonarqube.com"
      export NEXT_TOKEN="next-token"
      export SQC_US_URL="https://sonarqube-us.sonarcloud.io"
      export SQC_US_TOKEN="us-token"
      export SQC_EU_URL="https://sonarcloud.io"
      export SQC_EU_TOKEN="eu-token"
      export BUILD_NUMBER="42"
      export GITHUB_RUN_ID="12345"
      export GITHUB_SHA="abc123"
      export GITHUB_REPOSITORY="test/repo"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The output should include "=== ORCHESTRATOR: Running Sonar analysis on selected platform: next ==="
      The output should include "Using Sonar platform: next"
      The output should not include "shadow scan enabled"
    End

    It 'runs multi-platform analysis when shadow scans enabled'
      export RUN_SHADOW_SCANS="true"
      export SONAR_PLATFORM="next"
      export CURRENT_VERSION="1.2.3"
      export NEXT_URL="https://next.sonarqube.com"
      export NEXT_TOKEN="next-token"
      export SQC_US_URL="https://sonarqube-us.sonarcloud.io"
      export SQC_US_TOKEN="us-token"
      export SQC_EU_URL="https://sonarcloud.io"
      export SQC_EU_TOKEN="eu-token"
      export BUILD_NUMBER="42"
      export GITHUB_RUN_ID="12345"
      export GITHUB_SHA="abc123"
      export GITHUB_REPOSITORY="test/repo"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The output should include "=== ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled) ==="
      The output should include "--- ORCHESTRATOR: Analyzing with platform: next ---"
      The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-us ---"
      The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-eu ---"
      The output should include "=== ORCHESTRATOR: Completed Sonar analysis on all platforms ==="
    End
  End

  Describe 'get_build_config()'
    export GITHUB_REF_NAME="main"
    export DEFAULT_BRANCH="main"
    export BUILD_NUMBER="42"
    export GITHUB_EVENT_NAME="push"
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3-42"

    It 'disables deployment when shadow scans enabled on main branch'
      export RUN_SHADOW_SCANS="true"
      When call get_build_config
      The status should be success
      The output should include "======= Shadow scans enabled - disabling deployment to prevent duplicate artifacts ======="
      The variable BUILD_ENABLE_DEPLOY should equal "false"
      The variable BUILD_ENABLE_SONAR should equal "true"
    End

    It 'allows deployment when shadow scans disabled on main branch'
      export RUN_SHADOW_SCANS="false"
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
      When call build_yarn
      The status should be success
      The output should include "Run Shadow Scans: true"
      The output should include "Sonar Platform: next"
      The output should include "shadow scan enabled"
      The output should not include "JFrog operations"
    End
  End

  Describe 'build_yarn() specific scenarios'
    It 'builds maintenance branch'
      export GITHUB_REF_NAME="branch-1.2" GITHUB_EVENT_NAME="push" PROJECT="test"
      When call build_yarn
      The status should be success
      The output should include "======= Building maintenance branch ======="
    End

    It 'builds pull request with deploy enabled'
      export GITHUB_REF_NAME="feature/test" GITHUB_EVENT_NAME="pull_request" PROJECT="test"
      export PULL_REQUEST="123" DEPLOY_PULL_REQUEST="true"
      When call build_yarn
      The status should be success
      The output should include "======= Building pull request ======="
      The output should include "======= with deploy ======="
    End

    It 'builds pull request without deploy'
      export GITHUB_REF_NAME="feature/test" GITHUB_EVENT_NAME="pull_request" PROJECT="test"
      export PULL_REQUEST="123" DEPLOY_PULL_REQUEST="false"
      When call build_yarn
      The status should be success
      The output should include "======= Building pull request ======="
      The output should include "======= no deploy ======="
    End

    It 'builds dogfood branch'
      export GITHUB_REF_NAME="dogfood-on-feature" GITHUB_EVENT_NAME="push" PROJECT="test"
      When call build_yarn
      The status should be success
      The output should include "======= Build dogfood branch ======="
    End

    It 'builds long-lived feature branch'
      export GITHUB_REF_NAME="feature/long/test" GITHUB_EVENT_NAME="push" PROJECT="test"
      When call build_yarn
      The status should be success
      The output should include "======= Build long-lived feature branch ======="
    End
  End

  Describe 'main()'
    It 'runs full build process'
      When run script build-yarn/build.sh
      The status should be success
      The output should include "=== Yarn Build, Deploy, and Analyze ==="
    End
  End
End
