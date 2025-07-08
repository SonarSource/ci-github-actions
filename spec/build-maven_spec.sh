#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Mock external dependencies
Mock mvn
  case "$*" in
    *"project.version"*) echo "1.2.3-SNAPSHOT" ;;
    *"project.groupId"*) echo "com.sonarsource" ;;
    *"project.artifactId"*) echo "test-project" ;;
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

# Set required environment variables
export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_DEPLOY_REPO="sonarsource-public-qa"
export ARTIFACTORY_DEPLOY_PASSWORD="deploy-password"
export ARTIFACTORY_PRIVATE_PASSWORD="private-password"
export GITHUB_REF_NAME="master"
export BUILD_NUMBER="42"
export GITHUB_REPOSITORY="sonarsource/test-repo"
export GITHUB_EVENT_NAME="push"
export PULL_REQUEST="false"
export SONAR_HOST_URL="https://sonarcloud.io"
export SONAR_TOKEN="sonar-token"
export GITHUB_SHA="abc123def456"
export GITHUB_RUN_ID="123456789"

Describe 'build.sh'
  It 'should not run the main function if the script is sourced'
    When run source build-maven/build.sh
    The status should be success
    The output should equal ""
  End

  It 'should run the main function'
    When run script build-maven/build.sh
    The status should be success
    The output should include "Starting optimized Maven build"
    The output should include "Detected build context: master"
    The output should include "Build completed successfully"
  End
End

Include build-maven/build.sh

Describe 'detect_build_context'
  It 'should detect master context'
    export GITHUB_REF_NAME="master"
    export PULL_REQUEST="false"
    When call detect_build_context
    The output should equal "master"
  End

  It 'should detect maintenance context'
    export GITHUB_REF_NAME="branch-8.0"
    export PULL_REQUEST="false"
    When call detect_build_context
    The output should equal "maintenance"
  End

  It 'should detect pr context'
    export GITHUB_REF_NAME="feature/test"
    export PULL_REQUEST="123"
    When call detect_build_context
    The output should equal "pr"
  End

  It 'should detect dogfood context'
    export GITHUB_REF_NAME="dogfood-on-master"
    export PULL_REQUEST="false"
    When call detect_build_context
    The output should equal "dogfood"
  End

  It 'should detect feature context'
    export GITHUB_REF_NAME="feature/long/my-feature"
    export PULL_REQUEST="false"
    When call detect_build_context
    The output should equal "feature"
  End

  It 'should detect default context'
    export GITHUB_REF_NAME="feature/short"
    export PULL_REQUEST="false"
    When call detect_build_context
    The output should equal "default"
  End
End

Describe 'maven_expression'
  It 'should extract project version'
    When call maven_expression "project.version"
    The output should equal "1.2.3-SNAPSHOT"
  End

  It 'should extract project groupId'
    When call maven_expression "project.groupId"
    The output should equal "com.sonarsource"
  End
End

Describe 'set_maven_build_version'
  It 'should convert SNAPSHOT version to build version'
    When call set_maven_build_version "42"
    The output should include "Replacing version 1.2.3-SNAPSHOT with 1.2.3.42"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'should handle 2-digit version by adding .0'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2-SNAPSHOT" ;;
        *"versions:set"*) echo "mvn $*" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_maven_build_version "42"
    The output should include "Replacing version 1.2-SNAPSHOT with 1.2.0.42"
    The variable PROJECT_VERSION should equal "1.2.0.42"
  End

  It 'should handle non-SNAPSHOT version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3" ;;
        *"versions:set"*) echo "mvn $*" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_maven_build_version "42"
    The output should include "Replacing version 1.2.3 with 1.2.3.42"
    The variable PROJECT_VERSION should equal "1.2.3.42"
  End

  It 'should fail when maven expression fails'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "ERROR" >&2; return 1 ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call set_maven_build_version "42"
    The status should be failure
    The error should include "Could not get project.version from Maven project"
  End
End

Describe 'check_version_format'
  It 'should accept valid version format'
    When call check_version_format "1.2.3.42"
    The output should equal ""
  End

  It 'should warn about invalid version format'
    When call check_version_format "1.2.3"
    The output should include "WARN: Version '1.2.3' does not match the expected format"
  End
End

Describe 'get_sonar_properties'
  It 'should generate master properties'
    export CURRENT_VERSION="1.2.3"
    When call get_sonar_properties "master" "sha123"
    The output should include "-Dsonar.host.url=https://sonarcloud.io"
    The output should include "-Dsonar.token=sonar-token"
    The output should include "-Dsonar.projectVersion=1.2.3"
    The output should include "-Dsonar.analysis.sha1=sha123"
  End

  It 'should generate maintenance properties'
    When call get_sonar_properties "maintenance" "sha456"
    The output should include "-Dsonar.branch.name=master"
    The output should include "-Dsonar.analysis.sha1=sha456"
  End

  It 'should generate PR properties'
    When call get_sonar_properties "pr" "sha789"
    The output should include "-Dsonar.analysis.prNumber=false"
    The output should include "-Dsonar.analysis.sha1=sha789"
  End
End

Describe 'execute_maven'
  It 'should execute maven with all parameters'
    When call execute_maven "deploy" "coverage,deploy-sonarsource" "-Dtest.prop=value"
    The output should include "Goals to execute: deploy"
    The output should include "Profiles to activate: coverage,deploy-sonarsource"
    The output should include "Additional properties: -Dtest.prop=value"
    The output should include "mvn deploy -Pcoverage,deploy-sonarsource -Dtest.prop=value -B -e -V"
  End

  It 'should execute maven without profiles'
    When call execute_maven "verify" "" "-Dtest.prop=value"
    The output should include "Profiles: none"
    The output should include "mvn verify -Dtest.prop=value -B -e -V"
  End

  It 'should execute maven without properties'
    When call execute_maven "compile" "coverage" ""
    The output should include "Additional properties: none"
    The output should include "mvn compile -Pcoverage -B -e -V"
  End
End

Describe 'build_master'
  setup() {
    # shellcheck disable=SC2317
    export MAVEN_OPTS=""
    # shellcheck disable=SC2317
    export CURRENT_VERSION=""
    # shellcheck disable=SC2317
    export PROJECT_VERSION=""
  }
  Before 'setup'

  Mock set_maven_build_version
    export PROJECT_VERSION="1.2.3.42"
    echo "Version updated to: $PROJECT_VERSION"
  End
  Mock check_version_format
  End
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should execute master build'
    When call build_master
    The output should include "Build, deploy and analyze master"
    The output should include "git fetch --quiet origin master"
    The output should include "Setting up build version with build number: 42"
    The output should include "Version updated to: 1.2.3.42"
    The output should include "execute_maven"
    The variable MAVEN_OPTS should include "1536m"
  End
End

Describe 'build_pr'
  setup() {
    # shellcheck disable=SC2317
    export MAVEN_OPTS=""
    # shellcheck disable=SC2317
    export PROJECT_VERSION=""
  }
  Before 'setup'

  Mock set_maven_build_version
    export PROJECT_VERSION="1.2.3.42"
  End
  Mock check_version_format
  End
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should execute PR build without deploy'
    unset DEPLOY_PULL_REQUEST
    When call build_pr
    The output should include "Build and analyze pull request"
    The output should include "no deploy"
    The output should include "execute_maven verify"
    The variable MAVEN_OPTS should include "1G"
  End

  It 'should execute PR build with deploy'
    export DEPLOY_PULL_REQUEST="true"
    When call build_pr
    The output should include "with deploy"
    The output should include "execute_maven deploy"
  End
End

Describe 'build_maintenance'
  setup() {
    # shellcheck disable=SC2317
    export MAVEN_OPTS=""
    # shellcheck disable=SC2317
    export CURRENT_VERSION=""
    # shellcheck disable=SC2317
    export PROJECT_VERSION=""
  }
  Before 'setup'

  Mock set_maven_build_version
    export PROJECT_VERSION="1.2.3.42"
  End
  Mock check_version_format
  End
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should handle SNAPSHOT version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3-SNAPSHOT" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call build_maintenance
    The output should include "Found SNAPSHOT version"
    The output should include "Setting up build version with build number: 42"
  End

  It 'should handle RELEASE version'
    Mock mvn
      case "$*" in
        *"project.version"*) echo "1.2.3" ;;
        *) echo "mvn $*" ;;
      esac
    End
    When call build_maintenance
    The output should include "Found RELEASE version"
    The output should include "Deploy 1.2.3"
    The output should include "Using current version: 1.2.3"
  End
End

Describe 'build_dogfood'
  setup() {
    # shellcheck disable=SC2317
    export PROJECT_VERSION=""
  }
  Before 'setup'

  Mock set_maven_build_version
    export PROJECT_VERSION="1.2.3.42"
  End
  Mock check_version_format
  End
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should execute dogfood build'
    When call build_dogfood
    The output should include "Build dogfood branch"
    The output should include "execute_maven deploy"
  End
End

Describe 'build_feature'
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should execute feature build'
    When call build_feature
    The output should include "Build and analyze long lived feature branch"
    The output should include "execute_maven verify"
  End
End

Describe 'build_default'
  Mock execute_maven
    echo "execute_maven $*"
  End

  It 'should execute default build'
    When call build_default
    The output should include "Build, no analysis, no deploy"
    The output should include "execute_maven verify"
  End
End

Describe 'main'
  Mock detect_build_context
    echo "master"
  End
  Mock build_master
    echo "build_master executed"
  End

  It 'should execute main function'
    When call main
    The output should include "Starting optimized Maven build"
    The output should include "Detected build context: master"
    The output should include "build_master executed"
    The output should include "Build completed successfully"
  End

End
