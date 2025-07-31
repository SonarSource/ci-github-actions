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
    "version"*) echo "npm version completed" ;;
    *) echo "npm $*" ;;
  esac
End

Mock npx
  [[ "$*" =~ sonarqube-scanner ]] && echo "SonarQube scanner completed" || echo "npx $*"
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
export SONAR_HOST_URL="https://sonar.example.com" SONAR_TOKEN="sonar-token"
export DEPLOY_PULL_REQUEST="false" SKIP_TESTS="false" DEFAULT_BRANCH="main" PULL_REQUEST=""

# Create mock files
echo '{"version": "1.2.3-SNAPSHOT", "name": "test-project"}' > package.json
touch yarn.lock

Describe 'build-yarn/build.sh'
  Include build-yarn/build.sh

  Describe 'check_tool()'
    It 'succeeds when tool exists'
      When call check_tool jq --version
      The status should be success
      The output should include "jq-1.8.1"
    End

    It 'fails when tool missing'
      When run check_tool nonexistent --version
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
      The output should include "git fetch --unshallow --filter=blob:none"
    End

    It 'fetches base ref for PR'
      export GITHUB_BASE_REF="main"
      When call git_fetch_unshallow
      The output should include "Fetch main for SonarQube analysis..."
      The output should include "git fetch --filter=blob:none origin main"
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
      The variable PROJECT_VERSION should equal "1.2.3-42"
      The variable CURRENT_VERSION should equal "1.2.3-SNAPSHOT"
    End

    It 'handles 1-digit versions'
      export MOCK_VERSION="1-SNAPSHOT"
      When call set_project_version
      The variable PROJECT_VERSION should equal "1.0.0-42"
    End

    It 'handles 2-digit versions'
      export MOCK_VERSION="1.2-SNAPSHOT"
      When call set_project_version
      The variable PROJECT_VERSION should equal "1.2.0-42"
    End

    It 'fails on invalid version (null)'
      export MOCK_VERSION="null"
      When run set_project_version
      The status should be failure
      The stderr should include "Could not get version from package.json"
    End

    It 'fails on version with more than 3 digits'
      export MOCK_VERSION="1.2.3.4-SNAPSHOT"
      When run set_project_version
      The status should be failure
      The stderr should include "Unsupported version"
    End
  End

  Describe 'run_standard_pipeline()'
    It 'runs full pipeline'
      export PROJECT="test" PROJECT_VERSION="1.2.3-42"
      When call run_standard_pipeline true true -Dsonar.branch.name=main
      The output should include "Installing yarn dependencies..."
      The output should include "Setting project version to 1.2.3-42..."
      The output should include "Running tests..."
      The output should include "SonarQube scanner completed"
      The output should include "Building project..."
      The output should include "::debug::JFrog operations completed successfully"
    End

    It 'skips tests when SKIP_TESTS=true'
      export SKIP_TESTS="true" PROJECT="test" PROJECT_VERSION="1.2.3-42"
      When call run_standard_pipeline false false
      The output should include "Skipping tests (SKIP_TESTS=true)"
      The output should not include "Running tests..."
    End
  End

  Describe 'jfrog_yarn_publish()'
    It 'publishes successfully'
      export PROJECT="test"
      When call jfrog_yarn_publish
      The output should include "::debug::JFrog operations completed successfully"
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
      BeforeCall 'echo "{\"version\": \"1.2.3-SNAPSHOT\"}" > package.json && touch yarn.lock'
      When run script build-yarn/build.sh
      The status should be success
      The output should include "=== Yarn Build, Deploy, and Analyze ==="
    End
  End
End
