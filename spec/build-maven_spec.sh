#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock mvn
  echo "mvn $*"
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
export SCANNER_VERSION="5.3.0.6276"
export CURRENT_VERSION="1.2.3-SNAPSHOT"
export PROJECT_VERSION="1.2.3.42"

Describe 'build-maven/build.sh'
  It 'does not run main when sourced'
    When run source build-maven/build.sh
    The status should be success
    The output should equal ""
  End
  It 'runs main function when executed directly'
    HOME=$(mktemp -d)
    export HOME
    mkdir -p "$HOME/.m2"
    touch "$HOME/.m2/settings.xml"
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    Mock git
      echo "git $*"
    End
    Mock mvn
      echo "mvn $*"
    End
    When run script build-maven/build.sh
    The status should be success
    The output should include "Maven command: mvn"
    rm -f "$GITHUB_OUTPUT"
  End
End

Include build-maven/build.sh

Describe 'build.sh'
  It 'runs build_maven()'
    Mock check_settings_xml
      true
    End
    When call build_maven
    The status should be success
    The lines of stdout should equal 6
    The line 1 should include "mvn"
    The line 2 should include "mvn --version"
    The line 3 should include "Skipping git fetch (Sonar analysis disabled)"
    The line 4 should include "Build, no analysis, no deploy"
    The line 5 should include "Maven command: mvn verify"
    The line 6 should match pattern "mvn verify"
  End

  It 'runs build_maven() for windows'
    export RUNNER_OS="Windows"
    Mock check_settings_xml
      true
    End
    When call build_maven
    The status should be success
    The lines of stdout should equal 6
    The line 1 should include "mvn"
    The line 2 should include "mvn --version"
    The line 3 should include "Skipping git fetch (Sonar analysis disabled)"
    The line 4 should include "Build, no analysis, no deploy"
    The line 5 should include "Maven command: mvn verify"
    The line 6 should match pattern "mvn verify"
  End
End

Describe 'export_built_artifacts()'
  It "skips silently when $DEPLOYED_OUTPUT_KEY=false"
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    mvn_output="/dev/null"
    echo "$DEPLOYED_OUTPUT_KEY=false" > "$GITHUB_OUTPUT"

    When call export_built_artifacts
    The status should be success
    The output should be blank
    rm -f "$GITHUB_OUTPUT"
  End

  It "captures artifacts when $DEPLOYED_OUTPUT_KEY=true and writes to GITHUB_OUTPUT"
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    echo "$DEPLOYED_OUTPUT_KEY=true" >> "$GITHUB_OUTPUT"

    # Mock mvn evaluations used by export_built_artifacts
    Mock mvn
      case "$*" in
        *"help:evaluate -Dexpression=maven.deploy.skip -q -DforceStdout"*) echo "false" ;;
        *"help:evaluate -Dexpression=project.build.directory -q -DforceStdout"*) echo "target" ;;
        *) echo "mvn $*" ;;
      esac
    End
    mvn_output=$(mktemp)
    {
      echo "[INFO] Installing /home/runner/work/test-repo/pom.xml to /home/runner/.m2/repository/org/sonarsource/app/1.0/app-1.0.pom"
      echo "[INFO] Installing /home/runner/work/test-repo/target/app-1.0.jar to /home/runner/.m2/repository/org/sonarsource/app/1.0/app-1.0.jar"
      echo "[INFO] Installing /home/runner/work/test-repo/target/app-1.0-sources.jar to /home/runner/.m2/repository/org/sonarsource/app/1.0/app-1.0-sources.jar"
    } > "$mvn_output"
    mkdir -p target
    touch target/app-1.0.jar
    touch target/app-1.0-sources.jar

    When call export_built_artifacts
    The status should be success
    The lines of stdout should equal 5
    The line 1 should equal "::group::Capturing built artifacts for attestation"
    The line 2 should equal "Scanning for artifacts in: */target/*"
    The line 3 should equal "Found artifacts for attestation:"
    The line 4 should equal "./target/app-1.0.jar"
    The line 5 should equal "::endgroup::"
    The lines of contents of file "$GITHUB_OUTPUT" should equal 9
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "$DEPLOYED_OUTPUT_KEY=true"
    The line 2 of contents of file "$GITHUB_OUTPUT" should equal "installed-artifacts<<EOF"
    The line 7 of contents of file "$GITHUB_OUTPUT" should equal "artifact-paths<<EOF"
    The line 8 of contents of file "$GITHUB_OUTPUT" should equal "./target/app-1.0.jar"
    The line 9 of contents of file "$GITHUB_OUTPUT" should equal "EOF"

    rm -rf target "$GITHUB_OUTPUT"
  End

  It 'reports no artifacts found when build directory is empty'
    GITHUB_OUTPUT=$(mktemp)
    export GITHUB_OUTPUT
    mvn_output="/dev/null"
    echo "$DEPLOYED_OUTPUT_KEY=true" > "$GITHUB_OUTPUT"

    # Mock mvn evaluations used by export_built_artifacts
    Mock mvn
      case "$*" in
        *"help:evaluate -Dexpression=maven.deploy.skip -q -DforceStdout"*) echo "false" ;;
        *"help:evaluate -Dexpression=project.build.directory -q -DforceStdout"*) echo "target" ;;
        *) echo "mvn $*" ;;
      esac
    End

    mkdir -p target

    When call export_built_artifacts
    The status should be success
    The lines of stdout should equal 4
    The line 1 should equal "::group::Capturing built artifacts for attestation"
    The line 2 should equal "Scanning for artifacts in: */target/*"
    The line 3 should equal "::warning title=No artifacts found::No artifacts found for attestation in build output directories"
    The line 4 should equal "::endgroup::"
    The lines of contents of file "$GITHUB_OUTPUT" should equal 4
    The line 1 of contents of file "$GITHUB_OUTPUT" should equal "$DEPLOYED_OUTPUT_KEY=true"
    rm -rf target "$GITHUB_OUTPUT"
  End
End


Describe 'run_sonar_scanner()'
  export SONAR_HOST_URL="https://test.sonarqube.com"
  export SONAR_TOKEN="test-token"
  # COMMON_MVN_FLAGS is now defined in build.sh, no need to redefine it here

  It 'runs sonar scanner with basic properties'
    When call sonar_scanner_implementation
    The status should be success
    The line 2 should include "mvn"
    The line 2 should include "org.sonarsource.scanner.maven:sonar-maven-plugin:5.3.0.6276:sonar"
    The line 2 should include "-Dsonar.host.url=https://test.sonarqube.com"
    The line 2 should include "-Dsonar.token=test-token"
    The line 2 should include "-Dsonar.projectVersion=1.2.3-SNAPSHOT"
    The lines of stdout should equal 2
  End

  It 'runs sonar scanner with additional parameters'
    When call sonar_scanner_implementation "-Dsonar.pullrequest.key=123"
    The status should be success
    The line 2 should include "-Dsonar.pullrequest.key=123"
    The lines of stdout should equal 2
  End

End

Describe 'orchestrate_sonar_platforms()'
  Mock sonar_scanner_implementation
    echo "sonar_scanner_implementation $*"
  End

  It 'runs analysis on single platform when shadow scans disabled'
    export RUN_SHADOW_SCANS="false"
    export SONAR_PLATFORM="next"
    When call orchestrate_sonar_platforms "-Dsome.property=value"
    The status should be success
    The lines of stdout should equal 3
    The line 1 should include "ORCHESTRATOR: Running Sonar analysis on selected platform: next"
    The line 2 should include "Using Sonar platform: next"
    The line 3 should include "sonar_scanner_implementation -Dsome.property=value"
  End

  It 'runs analysis on all platforms when shadow scans enabled'
    export RUN_SHADOW_SCANS="true"
    When call orchestrate_sonar_platforms "-Dsome.property=value"
    The status should be success
    The lines of stdout should equal 17
    The line 1 should include "ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled)"
    The line 3 should include "--- ORCHESTRATOR: Analyzing with platform: next ---"
    The line 4 should include "Using Sonar platform: next"
    The line 5 should include "sonar_scanner_implementation -Dsome.property=value"
    The line 8 should include "--- ORCHESTRATOR: Analyzing with platform: sqc-us ---"
    The line 9 should include "Using Sonar platform: sqc-us"
    The line 10 should include "sonar_scanner_implementation -Dsome.property=value"
    The line 13 should include "--- ORCHESTRATOR: Analyzing with platform: sqc-eu ---"
    The line 14 should include "Using Sonar platform: sqc-eu"
    The line 15 should include "sonar_scanner_implementation -Dsome.property=value"
    The line 17 should include "ORCHESTRATOR: Completed Sonar analysis on all platforms"
  End
End

Describe 'check_settings_xml()'
  It 'succeeds when settings.xml exists'
    # Set up a temporary HOME directory
    temp_home=$(mktemp -d)
    export HOME="$temp_home"
    mkdir -p "$HOME/.m2"
    touch "$HOME/.m2/settings.xml"
    When call check_settings_xml
    The status should be success
    The output should be blank

    rm -rf "$temp_home"
  End

  It 'fails when settings.xml does not exist'
    # Set up a temporary HOME directory without settings.xml
    temp_home=$(mktemp -d)
    export HOME="$temp_home"
    mkdir -p "$HOME/.m2"
    When run check_settings_xml
    The status should be failure
    The lines of output should equal 1
    The output should include "Missing Maven settings.xml::Maven settings.xml file not found at $HOME/.m2/settings.xml"

    rm -rf "$temp_home"
  End

  It 'fails when .m2 directory does not exist'
    # Set up a temporary HOME directory without .m2 directory
    temp_home=$(mktemp -d)
    export HOME="$temp_home"
    When run check_settings_xml
    The status should be failure
    The lines of output should equal 1
    The output should include "Missing Maven settings.xml::Maven settings.xml file not found at $HOME/.m2/settings.xml"

    rm -rf "$temp_home"
  End
End

Describe 'git_fetch_unshallow()'
  It 'fetches unshallow repository'
    When call git_fetch_unshallow
    The lines of stdout should equal 2
    The line 1 should start with "Fetch Git references"
    The line 2 should equal "git fetch --unshallow"
  End

  It 'fallbacks and fetches base branch for pull request'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
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
    The line 2 should equal "git fetch origin def_main"
  End
End

Describe 'build_maven()'
  Mock check_tool
    true
  End
  Mock check_settings_xml
    true
  End
  Mock git_fetch_unshallow
    true
  End
  Mock orchestrate_sonar_platforms
    echo "orchestrate_sonar_platforms $*"
  End

  Describe 'is_default_branch'
    export GITHUB_REF_NAME="def_main"

    It 'builds, deploys and analyzes main branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze def_main"
      The line 2 should start with "Maven command: mvn deploy"
      The line 3 should start with "mvn deploy"
      The line 3 should include "-Pdeploy-sonarsource -Pcoverage -Prelease,sign"
      The line 4 should start with "orchestrate_sonar_platforms"
    End

    It 'builds and analyzes main branch when DEPLOY is false'
      export DEPLOY="false"

      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze def_main"
      The line 2 should start with "Maven command: mvn install"
      The line 3 should start with "mvn install"
      The line 3 should include "-Pcoverage -Prelease,sign"
      The line 4 should start with "orchestrate_sonar_platforms"
    End
  End

  Describe 'is_maintenance_branch'
    export GITHUB_REF_NAME="branch-1.2"

    It 'builds, deploys and analyzes maintenance branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze branch-1.2"
      The line 3 should start with "mvn deploy"
      The line 4 should start with "orchestrate_sonar_platforms"
    End

    It 'builds and analyzes main branch when DEPLOY is false'
      export DEPLOY="false"

      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze branch-1.2"
      The line 2 should start with "Maven command: mvn install"
      The line 3 should start with "mvn install"
      The line 4 should start with "orchestrate_sonar_platforms"
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
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze pull request 123 (fix/jdoe/JIRA-1234-aFix)"
      The line 2 should start with "Maven command: mvn install"
      The line 3 should start with "mvn install"
      The line 3 should include "-Pcoverage"
      The line 4 should start with "orchestrate_sonar_platforms"
      The line 4 should include "-Dsonar.pullrequest.key=123"
      The line 4 should include "-Dsonar.pullrequest.branch=fix/jdoe/JIRA-1234-aFix"
      The line 4 should include "-Dsonar.pullrequest.base=def_main"
    End

    It 'builds, analyzes pull request with deploy when DEPLOY_PULL_REQUEST is true'
      export DEPLOY_PULL_REQUEST="true"
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze pull request 123 (fix/jdoe/JIRA-1234-aFix)"
      The line 2 should start with "Maven command: mvn deploy"
      The line 3 should start with "mvn deploy"
      The line 3 should include "-Pdeploy-sonarsource -Pcoverage"
      The line 4 should start with "orchestrate_sonar_platforms"
      The line 4 should include "-Dsonar.pullrequest.key=123"
      The line 4 should include "-Dsonar.pullrequest.branch=fix/jdoe/JIRA-1234-aFix"
      The line 4 should include "-Dsonar.pullrequest.base=def_main"
    End
    It 'builds, analyzes pull request with no deploy when DEPLOY_PULL_REQUEST is true and DEPLOY is false'
      export DEPLOY_PULL_REQUEST="true"
      export DEPLOY="false"
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze pull request 123 (fix/jdoe/JIRA-1234-aFix)"
      The line 2 should start with "Maven command: mvn install"
      The line 3 should start with "mvn install"
      The line 3 should include "-Pcoverage"
      The line 4 should start with "orchestrate_sonar_platforms"
      The line 4 should include "-Dsonar.pullrequest.key=123"
      The line 4 should include "-Dsonar.pullrequest.branch=fix/jdoe/JIRA-1234-aFix"
      The line 4 should include "-Dsonar.pullrequest.base=def_main"
    End
  End

  Describe 'is_dogfood_branch'
    export GITHUB_REF_NAME="dogfood-on-something"

    It 'builds and deploy'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Skipping git fetch (Sonar analysis disabled)"
      The line 2 should include "Build dogfood branch dogfood-on-something"
      The line 3 should start with "Maven command: mvn deploy"
      The line 4 should start with "mvn deploy"
      The line 4 should include "-Pdeploy-sonarsource -Prelease"
    End

    It 'builds when DEPLOY is false'
      export DEPLOY="false"
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Skipping git fetch (Sonar analysis disabled)"
      The line 2 should include "Build dogfood branch dogfood-on-something"
      The line 3 should start with "Maven command: mvn install"
      The line 4 should start with "mvn install"
      The line 4 should include "-Prelease"
    End
  End

  Describe 'is_feature_branch'
    export GITHUB_REF_NAME="feature/long/some-feature"

    It 'builds, deploys and analyzes long lived feature branch'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Build and analyze long lived feature branch feature/long/some-feature"
      The line 2 should start with "Maven command: mvn deploy"
      The line 3 should start with "mvn deploy"
      The line 3 should include "-Pdeploy-sonarsource -Pcoverage"
      The line 4 should start with "orchestrate_sonar_platforms"
    End
  End

  Describe 'other branches'
    export GITHUB_REF_NAME="some-branch"

    It 'builds only'
      When call build_maven
      The lines of stdout should equal 4
      The line 1 should include "Skipping git fetch (Sonar analysis disabled)"
      The line 2 should include "Build, no analysis, no deploy some-branch"
      The line 3 should start with "Maven command: mvn verify"
      The line 4 should start with "mvn verify"
    End
  End

  Describe 'shadow scans disable deployment'
    export GITHUB_REF_NAME="def_main"
    export RUN_SHADOW_SCANS="true"

    It 'disables deployment when shadow scans are enabled'
      When call build_maven
      The status should be success
      The stderr should include "Shadow scans enabled - disabling deployment"
      The output should include "Maven command: mvn install"
      The output should not include "Maven command: mvn deploy"
    End
  End

  Describe 'scan depends on the sonar platform and branch'
    It 'returns false'
      export SONAR_PLATFORM="none"
      When call should_scan
      The status should be failure
    End
    It 'returns true'
      export SONAR_PLATFORM="next"
      export GITHUB_REF_NAME="def_main"
      When call should_scan
      The status should be success
    End
  End
End
