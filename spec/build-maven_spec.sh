#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock mvn
  case "$*" in
    *"project.version"*) echo "1.2.3-SNAPSHOT" ;;
    *"versions:set"*) echo "mvn $*" ;;
    *) echo "mvn $*" ;;
  esac
End

Mock git
  echo "git $*"
End

Mock gh
  echo "gh $*"
End

Mock cygwin
  echo "cygwin $*"
End

# Set required environment variables
export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://dummy.repox"
export ARTIFACTORY_DEPLOY_REPO="deploy-repo-qa"
export ARTIFACTORY_DEPLOY_USERNAME="deploy-user"
export ARTIFACTORY_DEPLOY_PASSWORD="deploy-password"
export ARTIFACTORY_ACCESS_TOKEN="access-token"
export GITHUB_REPOSITORY="sonarsource/test-repo"
export DEFAULT_BRANCH="def_main"
export GITHUB_REF_NAME="a-branch"
export GITHUB_EVENT_NAME="push"
export GITHUB_SHA="abc123def456"
export BUILD_NUMBER="42"
export PULL_REQUEST=""
export SONAR_HOST_URL="https://sonarqube"
export SONAR_TOKEN="sonar-token"
export GITHUB_RUN_ID="123456789"
export GITHUB_OUTPUT=/dev/null
export RUNNER_OS="Linux"
# Add missing Sonar platform variables required by build script
export SONAR_PLATFORM="next"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube.us.sonarsource.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarqube.eu.sonarsource.com"
export SQC_EU_TOKEN="sqc-eu-token"
export RUN_SHADOW_SCANS="false"
export SCANNER_VERSION="5.1.0.4751"
MAVEN_SETTINGS="$(mktemp)"
touch "$MAVEN_SETTINGS"
export MAVEN_SETTINGS

Include build-maven/build.sh

Describe 'build.sh'
  It 'runs build_maven()'
    When run script build-maven/build.sh
    The status should be success
      The lines of stdout should equal 9
      The line 1 should include "mvn"
      The line 2 should include "mvn"
      The line 3 should include "Fetch Git references"
      The line 4 should include "git fetch"
      The line 5 should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
      The line 6 should match pattern "mvn --settings * org.codehaus.mojo:versions-maven-plugin*newVersion=1.2.3.42*"
      The line 7 should include "Build, no analysis, no deploy"
      The line 8 should include "Maven command: mvn verify"
      The line 9 should match pattern "mvn verify -Dmaven.test.redirectTestOutputToFile=false --settings * --batch-mode --no-transfer-progress --errors --fail-at-end --show-version"
  End

  It 'runs build_maven() for windows'
    export RUNNER_OS="Windows"
    When run script build-maven/build.sh
    The status should be success
      The lines of stdout should equal 9
      The line 1 should include "mvn"
      The line 2 should include "mvn"
      The line 3 should include "Fetch Git references"
      The line 4 should include "git fetch"
      The line 5 should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
      The line 6 should match pattern "mvn --settings * org.codehaus.mojo:versions-maven-plugin*newVersion=1.2.3.42*"
      The line 7 should include "Build, no analysis, no deploy"
      The line 8 should include "Maven command: mvn verify"
      The line 9 should match pattern "mvn verify -Dmaven.test.redirectTestOutputToFile=false --settings * --batch-mode --no-transfer-progress --errors --fail-at-end --show-version"
  End
End

Describe 'set_sonar_platform_vars()'
  It 'sets variables for next platform'
    When call set_sonar_platform_vars "next"
    The status should be success
    The lines of stdout should equal 1
    The line 1 should include "Using Sonar platform: next"
    The variable SONAR_HOST_URL should equal "$NEXT_URL"
    The variable SONAR_TOKEN should equal "$NEXT_TOKEN"
  End

  It 'sets variables for sqc-us platform'
    When call set_sonar_platform_vars "sqc-us"
    The status should be success
    The lines of stdout should equal 1
    The line 1 should include "Using Sonar platform: sqc-us"
    The variable SONAR_HOST_URL should equal "$SQC_US_URL"
    The variable SONAR_TOKEN should equal "$SQC_US_TOKEN"
  End

  It 'sets variables for sqc-eu platform'
    When call set_sonar_platform_vars "sqc-eu"
    The status should be success
    The lines of stdout should equal 1
    The line 1 should include "Using Sonar platform: sqc-eu"
    The variable SONAR_HOST_URL should equal "$SQC_EU_URL"
    The variable SONAR_TOKEN should equal "$SQC_EU_TOKEN"
  End

  It 'fails with unknown platform'
    When call set_sonar_platform_vars "unknown"
    The status should be failure
    The error should include "ERROR: Unknown sonar platform 'unknown'"
  End
End

Describe 'run_sonar_scanner()'
  Mock mvn
    echo "mvn $*"
  End
  export PROJECT_VERSION="1.2.3.42"
  export SONAR_HOST_URL="https://test.sonarqube.com"
  export SONAR_TOKEN="test-token"
  # COMMON_MVN_FLAGS is now defined in build.sh, no need to redefine it here

  It 'runs sonar scanner with basic properties'
    When call run_sonar_scanner
    The status should be success
    The lines of stdout should equal 2
    The line 1 should include "mvn"
    The line 1 should include "org.sonarsource.scanner.maven:sonar-maven-plugin:5.1.0.4751:sonar"
    The line 1 should include "-Dsonar.host.url=https://test.sonarqube.com"
    The line 1 should include "-Dsonar.token=test-token"
    The line 1 should include "-Dsonar.projectVersion=1.2.3.42"
    The line 1 should include "-Dsonar.scm.revision=abc123def456"
    The line 2 should include "SonarQube scanner finished for platform: test.sonarqube.com"
  End

  It 'runs sonar scanner with additional parameters'
    When call run_sonar_scanner "-Dsonar.pullrequest.key=123"
    The status should be success
    The lines of stdout should equal 2
    The line 1 should include "-Dsonar.pullrequest.key=123"
  End
End

Describe 'run_sonar_analysis()'
  Mock mvn
    echo "mvn $*"
  End
  Mock run_sonar_scanner
    echo "run_sonar_scanner $*"
  End

  export PROJECT_VERSION="1.2.3.42"

  It 'runs analysis on single platform when shadow scans disabled'
    export RUN_SHADOW_SCANS="false"
    export SONAR_PLATFORM="next"
    When call run_sonar_analysis "-Dsome.property=value"
    The status should be success
    The lines of stdout should equal 3
    The line 1 should include "Running Sonar analysis on selected platform: next"
    The line 2 should include "Using Sonar platform: next"
    The line 3 should include "run_sonar_scanner -Dsome.property=value"
  End

  It 'runs analysis on all platforms when shadow scans enabled'
    export RUN_SHADOW_SCANS="true"
    When call run_sonar_analysis "-Dsome.property=value"
    The status should be success
    The lines of stdout should equal 11
    The line 1 should include "Running Sonar analysis on all platforms (shadow scan enabled)"
    The line 2 should include "--- Analyzing with platform: next ---"
    The line 3 should include "Using Sonar platform: next"
    The line 4 should include "run_sonar_scanner -Dsome.property=value"
    The line 5 should include "--- Analyzing with platform: sqc-us ---"
    The line 6 should include "Using Sonar platform: sqc-us"
    The line 7 should include "run_sonar_scanner -Dsome.property=value"
    The line 8 should include "--- Analyzing with platform: sqc-eu ---"
    The line 9 should include "Using Sonar platform: sqc-eu"
    The line 10 should include "run_sonar_scanner -Dsome.property=value"
    The line 11 should include "Completed Sonar analysis on all platforms"
  End
End

Describe 'check_tool()'
  It 'reports not installed tool'
    When call check_tool some_tool
    The status should be failure
    The error should equal "some_tool is not installed."
  End
End

Describe 'git_fetch_unshallow()'
  It 'fetches unshallow repository'
    When call git_fetch_unshallow
    The lines of stdout should equal 2
    The line 1 should start with "Fetch Git references"
    The line 2 should equal "git fetch --unshallow --filter=blob:none"
  End

  It 'fallbacks and fetches base branch for pull request'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_BASE_REF="def_main"
    Mock git
      case "$*" in
        *"rev-parse --is-shallow-repository"*) return 0;;
        *) echo "git $*" ;;
      esac
    End
    When call git_fetch_unshallow
    The lines of stdout should equal 2
    The line 1 should start with "Fetch def_main"
    The line 2 should equal "git fetch --filter=blob:none origin def_main"
  End
End

Describe 'maven_expression()'
  It 'extracts project version'
    When call maven_expression "project.version"
    The output should equal "1.2.3-SNAPSHOT"
  End
End

Describe 'set_project_version()'
  export GITHUB_REF_NAME="branch-1"

  It 'converts SNAPSHOT version to build version'
    When call set_project_version
    The lines of stdout should equal 2
    The line 1 should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
    The line 2 should match pattern "mvn --settings * org.codehaus.mojo:versions-maven-plugin*newVersion=1.2.3.42*"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'handles 1-digit version by adding .0.0'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1-SNAPSHOT" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The lines of stdout should equal 2
    The line 1 should include "Replacing version 1-SNAPSHOT with 1.0.0.42"
    The variable PROJECT_VERSION should equal "1.0.0.42"
  End

  It 'handles 2-digit version by adding .0'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2-SNAPSHOT" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The lines of stdout should equal 2
    The line 1 should include "Replacing version 1.2-SNAPSHOT with 1.2.0.42"
    The variable PROJECT_VERSION should equal "1.2.0.42"
  End

  It 'fails on not compliant version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3.4-SNAPSHOT" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The status should be failure
    The lines of stdout should equal 1
    The line 1 should include "Unsupported version '1.2.3.4-SNAPSHOT' with 4 digits"
    The variable PROJECT_VERSION should be undefined
  End

  It 'handles non-SNAPSHOT version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3.42" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The lines of stdout should equal 2
    The line 1 should include "Found RELEASE version on maintenance branch"
    The line 2 should include "Skipping version update"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'fails on not compliant non-SNAPSHOT version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The status should be failure
    The lines of stdout should equal 2
    The line 1 should include "Found RELEASE version on maintenance branch"
    The line 2 should include "Unsupported version '1.2.3' with 3 digits"
    The variable PROJECT_VERSION should be undefined
  End

  It 'fails when maven expression fails'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "Something went wrong" >&2; exit 1 ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_project_version
    The status should be failure
    The lines of stdout should equal 4
    The line 1 should include "Could not get 'project.version' from Maven project"
    The line 2 should equal "ERROR: Something went wrong"
    The line 3 should equal "Failed to evaluate Maven expression 'project.version'"
    The line 4 should equal "Something went wrong"
  End

  It 'fails when Maven settings.xml is missing'
    export MAVEN_SETTINGS="missing-settings.xml"
    When call set_project_version
    The status should be failure
    The lines of stdout should equal 1
    The line 1 should include "Maven settings.xml file not found at $MAVEN_SETTINGS"
    The variable PROJECT_VERSION should be undefined
    unset MAVEN_SETTINGS
  End
End

Describe 'build_maven()'
  Mock check_tool
  End
  Mock git_fetch_unshallow
  End
  Mock set_project_version
  End
  Mock run_sonar_analysis
    echo "run_sonar_analysis $*"
  End
  export PROJECT_VERSION="1.2.3.42"

  Describe 'is_default_branch'
    export GITHUB_REF_NAME="def_main"

    It 'builds, deploys and analyzes main branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build, deploy and analyze def_main"
      The line 2 should start with "Maven command: mvn deploy"
      The line 3 should start with "mvn deploy"
      The line 3 should include "-Pcoverage,deploy-sonarsource,release,sign"
      The line 4 should start with "run_sonar_analysis"
    End
  End

  Describe 'is_maintenance_branch'
    export GITHUB_REF_NAME="branch-1.2"

    It 'builds, deploys and analyzes maintenance branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build, deploy and analyze branch-1.2"
      The line 3 should start with "mvn deploy"
      The line 4 should start with "run_sonar_analysis"
    End
  End

  Describe 'is_pull_request'
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST="123"
    export GITHUB_REF_NAME="123/merge"
    export GITHUB_HEAD_REF="fix/jdoe/JIRA-1234-aFix"
    export GITHUB_BASE_REF="def_main"

    It 'builds, analyzes pull request with no deploy by default'
      When call build_maven
      The lines of stdout should equal 5
      The line 1 should include "Build and analyze pull request 123 (fix/jdoe/JIRA-1234-aFix)"
      The line 2 should include "no deploy"
      The line 3 should start with "Maven command: mvn verify"
      The line 4 should start with "mvn verify"
      The line 4 should include "-Pcoverage"
      The line 5 should start with "run_sonar_analysis"
      The line 5 should include "-Dsonar.pullrequest.key=123"
      The line 5 should include "-Dsonar.pullrequest.branch=fix/jdoe/JIRA-1234-aFix"
      The line 5 should include "-Dsonar.pullrequest.base=def_main"
    End

    It 'builds, analyzes pull request with deploy when DEPLOY_PULL_REQUEST is true'
      export DEPLOY_PULL_REQUEST="true"
      When call build_maven
      The lines of stdout should equal 5
      The line 1 should include "Build and analyze pull request 123 (fix/jdoe/JIRA-1234-aFix)"
      The line 2 should include "with deploy"
      The line 3 should start with "Maven command: mvn deploy"
      The line 4 should start with "mvn deploy"
      The line 4 should include "-Pcoverage,deploy-sonarsource"
      The line 5 should start with "run_sonar_analysis"
      The line 5 should include "-Dsonar.pullrequest.key=123"
      The line 5 should include "-Dsonar.pullrequest.branch=fix/jdoe/JIRA-1234-aFix"
      The line 5 should include "-Dsonar.pullrequest.base=def_main"
    End
  End

  Describe 'is_dogfood_branch'
    export GITHUB_REF_NAME="dogfood-on-something"

    It 'builds'
      When call build_maven
      The lines of stdout should equal 3
      The line 1 should include "Build, and deploy dogfood branch dogfood-on-something"
      The line 2 should start with "Maven command: mvn deploy"
      The line 3 should start with "mvn deploy"
      The line 3 should include "-Pdeploy-sonarsource,release"
    End
  End

  Describe 'is_feature_branch'
    export GITHUB_REF_NAME="feature/long/some-feature"

    It 'builds and analyzes long lived feature branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze long lived feature branch feature/long/some-feature"
      The line 2 should start with "Maven command: mvn verify"
      The line 3 should start with "mvn verify"
      The line 3 should include "-Pcoverage"
      The line 4 should start with "run_sonar_analysis"
    End
  End

  Describe 'other branches'
    export GITHUB_REF_NAME="some-branch"

    It 'builds only'
      When call build_maven
      The lines of stdout should equal 3
      The line 1 should include "Build, no analysis, no deploy some-branch"
      The line 2 should start with "Maven command: mvn verify"
      The line 3 should start with "mvn verify"
    End
  End

  Describe 'shadow scans disable deployment'
    export GITHUB_REF_NAME="def_main"
    export RUN_SHADOW_SCANS="true"

    It 'disables deployment when shadow scans are enabled'
      When call build_maven
      The status should be success
      The output should include "Shadow scans enabled - disabling deployment"
      The output should include "Maven command: mvn verify"
      The output should not include "Maven command: mvn deploy"
    End
  End
End
