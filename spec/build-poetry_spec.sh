#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock python
  echo "python $*"
End
Mock poetry
  echo "poetry $*"
End
Mock jf
  echo "jf $*"
End

# Minimal environment variables
export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://dummy.repox"
export ARTIFACTORY_PYPI_REPO="<repox pypi repo>"
export ARTIFACTORY_ACCESS_TOKEN="dummy access token"
export ARTIFACTORY_DEPLOY_REPO="<deploy repo>"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="<deploy token>"
export GITHUB_REPOSITORY="my-org/my-repo"
export DEFAULT_BRANCH="main"
export GITHUB_REF_NAME="any-branch"
export GITHUB_EVENT_NAME="push"
export BUILD_NUMBER="42"
export PULL_REQUEST=""
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
export GITHUB_OUTPUT=/dev/null
export SONAR_HOST_URL="https://sonarqube.test"
export SONAR_TOKEN="dummy-sonar-token"
export GITHUB_SHA="dummy-sha"
export GITHUB_RUN_ID="dummy-run-id"
export SONAR_PLATFORM="next"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube-us.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
export RUN_SHADOW_SCANS="false"

Describe 'build-poetry/build.sh'
  It 'does not run build_poetry() if the script is sourced'
    When run source build-poetry/build.sh
    The status should be success
    The output should equal ""
  End

  It 'runs build_poetry()'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2"
      else
        echo "poetry $*"
      fi
    End
    Mock git
      echo "git $*"
    End
    When run script build-poetry/build.sh
      The status should be success
      The lines of stdout should equal 25
      The line 1 should include "jq"
      The line 2 should include "jq"
      The line 3 should include "python"
      The line 4 should include "python"
      The line 5 should include "poetry"
      The line 6 should include "poetry"
      The line 7 should include "jf"
      The line 8 should include "jf"
      The line 9 should equal "PROJECT: my-repo"
      The line 10 should equal "Fetch Git references for SonarQube analysis..."
      The line 11 should equal "git fetch --unshallow --filter=blob:none"
      The line 12 should equal "=== Poetry Build, Deploy, and Analyze ==="
      The line 13 should equal "Branch: any-branch"
      The line 14 should equal "Pull Request: "
      The line 15 should equal "Deploy Pull Request: false"
      The line 16 should equal "Replacing version 1.2 with 1.2.0.42"
      The line 17 should equal "poetry version 1.2.0.42"
      The line 18 should equal "======= Build other branch ======="

      The line 20 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token dummy access token"
      The line 21 should equal "jf poetry-config --server-id-resolve repox --repo-resolve <repox pypi repo>"
      The line 22 should equal "jf poetry install --build-name=my-repo --build-number=42"
      The line 24 should equal "poetry build"
      The line 25 should equal "=== Build completed successfully ==="
    End
End

Include build-poetry/build.sh

Describe 'check_tool()'
  It 'reports not installed tool'
    When call check_tool some_tool
    The status should be failure
    The line 1 of error should equal "some_tool is not installed."
  End

  It 'executes existing command with arguments'
    When call check_tool echo "test message"
    The status should be success
    The line 1 should include "echo"
    The line 2 should equal "test message"
  End
End

Describe 'set_build_env()'
  It 'sets the project name and do git fetch'
    Mock git
      echo "git $*"
    End
    When call set_build_env
    The status should be success
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "Fetch Git references for SonarQube analysis..."
    The variable PROJECT should equal "my-repo"
  End
  It 'Fetches base branch for SonarQube analysis'
    Mock git
      if [[ "$*" == "rev-parse --is-shallow-repository --quiet" ]]; then
        return 1
      else
        echo "git $*"
      fi
    End
    export GITHUB_BASE_REF="main"
    When call set_build_env
    The status should be success
    The line 1 should equal "PROJECT: my-repo"
    The line 2 should equal "Fetch main for SonarQube analysis..."
    The variable PROJECT should equal "my-repo"
  End
End

Describe 'helper functions'
  Describe 'set_sonar_platform_vars()'
    It 'sets correct URL and token for next platform'
      When call set_sonar_platform_vars "next"
      The status should be success
      The line 1 should equal 'Using Sonar platform: next (URL: https://next.sonarqube.com)'
      The variable SONAR_HOST_URL should equal "https://next.sonarqube.com"
      The variable SONAR_TOKEN should equal "next-token"
    End

    It 'sets correct URL and token for sqc-us platform'
      When call set_sonar_platform_vars "sqc-us"
      The status should be success
      The line 1 should equal 'Using Sonar platform: sqc-us (URL: https://sonarqube-us.com)'
      The variable SONAR_HOST_URL should equal "https://sonarqube-us.com"
      The variable SONAR_TOKEN should equal "sqc-us-token"
    End

    It 'sets correct URL and token for sqc-eu platform'
      When call set_sonar_platform_vars "sqc-eu"
      The status should be success
      The line 1 should equal 'Using Sonar platform: sqc-eu (URL: https://sonarcloud.io)'
      The variable SONAR_HOST_URL should equal "https://sonarcloud.io"
      The variable SONAR_TOKEN should equal "sqc-eu-token"
    End

    It 'returns error for unknown platform'
      When call set_sonar_platform_vars "unknown"
      The status should be failure
      The line 1 of error should equal 'ERROR: Unknown sonar platform '"'"'unknown'"'"'. Expected: next, sqc-us, or sqc-eu'
    End
  End

  Describe 'is_maintenance_branch()'
    It 'returns true for branch-* pattern'
      export GITHUB_REF_NAME="branch-1.2"
      When call is_maintenance_branch
      The status should be success
    End

    It 'returns false for non-maintenance branch'
      export GITHUB_REF_NAME="main"
      When call is_maintenance_branch
      The status should be failure
    End
  End

  Describe 'is_dogfood_branch()'
    It 'returns true for dogfood-on-* pattern'
      export GITHUB_REF_NAME="dogfood-on-main"
      When call is_dogfood_branch
      The status should be success
    End

    It 'returns false for non-dogfood branch'
      export GITHUB_REF_NAME="main"
      When call is_dogfood_branch
      The status should be failure
    End
  End

  Describe 'is_merge_queue_branch()'
    It 'returns true for gh-readonly-queue/* pattern'
      export GITHUB_REF_NAME="gh-readonly-queue/123"
      When call is_merge_queue_branch
      The status should be success
    End

    It 'returns false for non-mergequeue branch'
      export GITHUB_REF_NAME="main"
      When call is_merge_queue_branch
      The status should be failure
    End
  End
End

Describe 'set_project_version()'
  It 'appends .0 given version is 1.2 and append BUILD_NUMBER'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2 with 1.2.0.42"
    The variable CURRENT_VERSION should equal "1.2"
    The variable PROJECT_VERSION should equal "1.2.0.42"
  End

  It 'appends BUILD_NUMBER given version is 1.2.3'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2.3 with 1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'replaces dev with BUILD_NUMBER given version is 1.2.3.dev'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3.dev"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "Replacing version 1.2.3.dev with 1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3.dev"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'replaces 41 with BUILD_NUMBER given version is 1.2.3.41'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "1.2.3.41"
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 should equal "WARN: version was truncated to 1.2.3 because it had more than 3 digits"
    The line 2 should equal "Replacing version 1.2.3.41 with 1.2.3.42"
    The variable CURRENT_VERSION should equal "1.2.3.41"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'returns error message if version cannot be retrieved'
    Mock poetry
      if [[ "$*" == "version -s" ]]; then
        echo "Failed to get version"
        exit 1
      else
        echo "poetry $*"
      fi
    End
    When call set_project_version
    The line 1 of error should equal "Could not get version from Poetry project ('poetry version -s')"
    The line 2 of error should equal "Failed to get version"
    The variable CURRENT_VERSION should be undefined
    The variable PROJECT_VERSION should be undefined
    The status should be failure
  End
End

Describe 'jfrog_poetry_install()'
  export PROJECT="my-repo"
  It 'installs Poetry dependencies using JFrog CLI'
    When call jfrog_poetry_install
    The line 1 should include "jf config add repox"
    The line 2 should include "jf poetry-config"
    The line 3 should include "jf poetry install"
  End
End

Describe 'build_poetry()'
  setup() {
    mkdir -p dist
  }

  cleanup() {
    rm -rf dist
  }
  Before 'setup'
  After 'cleanup'

  Mock check_tool
  End
  Mock set_build_env
  End
  Mock set_project_version
  End
  export PROJECT_VERSION="1.0.0.$BUILD_NUMBER"
  export PROJECT="my-repo"
  Mock jfrog_poetry_install
  End

  It 'builds and publishes when on the default branch (main) and not a PR'
    export PULL_REQUEST=""
    export GITHUB_REF_NAME="main"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: main'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Building main branch ======='
    The line 8 should equal 'poetry build'
    The line 9 should equal 'run_sonar_analysis()'
    The line 10 should equal '=== Running Sonar analysis on selected platform: next ==='
    The line 12 should equal 'Using Sonar platform: next (URL: https://next.sonarqube.com)'
    The line 13 should equal 'poetry run pip install pysonar'
    The line 15 should equal 'poetry run pysonar -Dsonar.host.url=https://next.sonarqube.com -Dsonar.token=next-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo'
    The line 17 should equal 'jf config remove repox'
    The line 18 should equal 'jf config add repox --artifactory-url https://dummy.repox --access-token <deploy token>'
    The line 19 should include '/dist'
    The line 20 should equal 'jf rt upload ./ <deploy repo>/poetry/1.0.0.42/ --module=poetry:1.0.0.42 --build-name=my-repo --build-number=42'
    The line 22 should equal 'jf rt build-collect-env my-repo 42'
    The line 23 should include 'jf rt build-publish my-repo 42'
    The line 24 should include '=== Build completed successfully ==='
    The status should be success
  End

  It 'skips deploy when on a PR and DEPLOY_PULL_REQUEST is not true'
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST="123"
    export GITHUB_REF_NAME="123/merge"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: 123/merge'
    The line 3 should equal 'Pull Request: 123'
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Building pull request ======='
    The line 6 should equal '======= no deploy ======='
    The line 9 should equal 'poetry build'
    The line 10 should equal 'run_sonar_analysis()'
    The line 11 should equal '=== Running Sonar analysis on selected platform: next ==='
    The line 13 should equal 'Using Sonar platform: next (URL: https://next.sonarqube.com)'
    The line 14 should equal 'poetry run pip install pysonar'
    The line 16 should equal 'poetry run pysonar -Dsonar.host.url=https://next.sonarqube.com -Dsonar.token=next-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo -Dsonar.analysis.prNumber=123'
    The line 18 should equal '=== Build completed successfully ==='
    The status should be success
  End

  It 'builds and publishes when on a PR and DEPLOY_PULL_REQUEST is true'
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST="123"
    export GITHUB_REF_NAME="123/merge"
    export DEPLOY_PULL_REQUEST="true"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: 123/merge'
    The line 3 should equal 'Pull Request: 123'
    The line 4 should equal 'Deploy Pull Request: true'
    The line 5 should equal '======= Building pull request ======='
    The line 6 should equal '======= with deploy ======='
    The line 9 should equal 'poetry build'
    The line 10 should equal 'run_sonar_analysis()'
    The line 11 should equal '=== Running Sonar analysis on selected platform: next ==='
    The line 13 should equal 'Using Sonar platform: next (URL: https://next.sonarqube.com)'
    The line 14 should equal 'poetry run pip install pysonar'
    The line 16 should equal 'poetry run pysonar -Dsonar.host.url=https://next.sonarqube.com -Dsonar.token=next-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo -Dsonar.analysis.prNumber=123'
    The line 18 should equal "jf config remove repox"
    The line 19 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token <deploy token>"
    The line 20 should include "/dist"
    The line 21 should equal "jf rt upload ./ <deploy repo>/poetry/1.0.0.42/ --module=poetry:1.0.0.42 --build-name=my-repo --build-number=42"
    The line 23 should equal "jf rt build-collect-env my-repo 42"
    The line 24 should include "jf rt build-publish my-repo 42"
    The status should be success
  End

  It 'disables sonarqube on dogfood branch'
    export GITHUB_REF_NAME="dogfood-on-test"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: dogfood-on-test'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Build dogfood branch ======='
    The status should be success
    The variable BUILD_ENABLE_SONAR should equal "false"
  End

  It 'disables deploy on long-lived branch'
    export GITHUB_REF_NAME="feature/long/test"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: feature/long/test'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Build long-lived feature branch ======='
    The status should be success
    The variable BUILD_ENABLE_SONAR should equal "true"
    The variable BUILD_SONAR_ARGS should equal "-Dsonar.branch.name=feature/long/test"
  End

  It 'enables deploy and scan on maintenance branch'
    export GITHUB_REF_NAME="branch-1.2"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: branch-1.2'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Building maintenance branch ======='
    The status should be success
    The variable BUILD_ENABLE_SONAR should equal "true"
  End

  It 'disables deploy and scan on merge queue branch'
    export GITHUB_REF_NAME="gh-readonly-queue/123"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: gh-readonly-queue/123'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Build other branch ======='
    The status should be success
    The variable BUILD_ENABLE_SONAR should equal "false"
    The variable BUILD_ENABLE_DEPLOY should equal "false"
  End

  It 'runs shadow scans on all platforms when RUN_SHADOW_SCANS is true'
    export PULL_REQUEST=""
    export GITHUB_REF_NAME="main"
    export RUN_SHADOW_SCANS="true"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: main'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Building main branch ======='
    The line 8 should equal 'poetry build'
    The line 9 should equal 'run_sonar_analysis()'
    The line 10 should equal '=== Running Sonar analysis on all platforms (shadow scan enabled) ==='
    The line 12 should equal '--- ORCHESTRATOR: Analyzing with platform: next ---'
    The line 13 should equal 'Using Sonar platform: next (URL: https://next.sonarqube.com)'
    The line 14 should equal 'poetry run pip install pysonar'
    The line 16 should equal 'poetry run pysonar -Dsonar.host.url=https://next.sonarqube.com -Dsonar.token=next-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo'
    The line 19 should equal '--- ORCHESTRATOR: Analyzing with platform: sqc-us ---'
    The line 20 should equal 'Using Sonar platform: sqc-us (URL: https://sonarqube-us.com)'
    The line 21 should equal 'poetry run pip install pysonar'
    The line 23 should equal 'poetry run pysonar -Dsonar.host.url=https://sonarqube-us.com -Dsonar.token=sqc-us-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo'
    The line 26 should equal '--- ORCHESTRATOR: Analyzing with platform: sqc-eu ---'
    The line 27 should equal 'Using Sonar platform: sqc-eu (URL: https://sonarcloud.io)'
    The line 28 should equal 'poetry run pip install pysonar'
    The line 30 should equal 'poetry run pysonar -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=sqc-eu-token -Dsonar.analysis.buildNumber=42 -Dsonar.analysis.pipeline=dummy-run-id -Dsonar.analysis.sha1=dummy-sha -Dsonar.analysis.repository=my-org/my-repo'
    The line 32 should equal '=== Completed Sonar analysis on all platforms ==='
    The status should be success
  End

  It 'skips sonar analysis when sonar-platform is none'
    export PULL_REQUEST=""
    export GITHUB_REF_NAME="main"
    export SONAR_PLATFORM="none"

    When call build_poetry
    The line 1 should equal '=== Poetry Build, Deploy, and Analyze ==='
    The line 2 should equal 'Branch: main'
    The line 3 should equal 'Pull Request: '
    The line 4 should equal 'Deploy Pull Request: false'
    The line 5 should equal '======= Building main branch ======='
    The line 8 should equal 'poetry build'
    The line 9 should equal 'run_sonar_analysis()'
    The line 10 should equal "=== Sonar platform set to 'none'. Skipping Sonar analysis."
    The line 11 should equal 'jf config remove repox'
    The line 12 should equal 'jf config add repox --artifactory-url https://dummy.repox --access-token <deploy token>'
    The line 13 should include '/dist'
    The line 14 should equal 'jf rt upload ./ <deploy repo>/poetry/1.0.0.42/ --module=poetry:1.0.0.42 --build-name=my-repo --build-number=42'
    The line 16 should equal 'jf rt build-collect-env my-repo 42'
    The line 17 should include 'jf rt build-publish my-repo 42'
    The line 18 should equal '=== Build completed successfully ==='
    The status should be success
  End
End
