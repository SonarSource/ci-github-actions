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
  else
    echo "jq $*"
  fi
End

Mock jf
  if [[ "$*" == "--version" ]]; then
    echo "jf version 2.77.0"
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

# Set up environment variables
export GITHUB_REPOSITORY="my-org/test-project"
export GITHUB_ENV=/dev/null
export GITHUB_EVENT_NAME="push"
export GITHUB_OUTPUT=/dev/null
export BUILD_NUMBER="42"
export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
export ARTIFACTORY_ACCESS_TOKEN="reader-token"

# Create mock package.json
echo '{"version": "1.2.3-SNAPSHOT", "name": "test-project"}' > package.json

Describe 'config-npm/config.sh'
  It 'does not run main when sourced'
    When run source config-npm/config.sh
    The status should be success
    The output should equal ""
  End
End

Include config-npm/config.sh

common_setup() {
  GITHUB_OUTPUT=$(mktemp)
  export GITHUB_OUTPUT
  GITHUB_ENV=$(mktemp)
  export GITHUB_ENV
}

common_cleanup() {
  [[ -f "$GITHUB_OUTPUT" ]] && rm "$GITHUB_OUTPUT"
  [[ -f "$GITHUB_ENV" ]] && rm "$GITHUB_ENV"
}

Describe 'set_build_env()'
  It 'sets up build environment correctly'
    export GITHUB_REPOSITORY="my-org/test-project"
    When call set_build_env
    The status should be success
    The line 1 should include "Configuring JFrog and NPM repositories"
    The line 2 should equal "npm config set registry https://repox.jfrog.io/artifactory/api/npm/npm"
    The line 3 should equal "npm config set //repox.jfrog.io/artifactory/api/npm/:_authToken=reader-token"
    The line 4 should equal "jf config add repox --artifactory-url https://repox.jfrog.io/artifactory --access-token reader-token"
    The line 5 should equal "jf config use repox"
    The line 6 should equal "jf npm-config --repo-resolve npm"
  End
End

Describe 'check_version_format()'
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

Describe 'set_project_version()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'exits with error when version cannot be read from package.json'
    export MOCK_VERSION="null"
    export BUILD_NUMBER="42"
    export GITHUB_OUTPUT=/dev/null
    export GITHUB_REF_NAME="main"
    When run set_project_version
    The status should be failure
    The line 1 should equal "Setting project version..."
    The stderr should include "Could not get version from package.json"
    The variable CURRENT_VERSION should be undefined
    The variable PROJECT_VERSION should be undefined
  End

  It 'exits with error when version is empty'
    export MOCK_VERSION=""
    export BUILD_NUMBER="42"
    export GITHUB_OUTPUT=/dev/null
    export GITHUB_REF_NAME="main"
    When run set_project_version
    The status should be failure
    The line 1 should equal "Setting project version..."
    The stderr should include "Could not get version from package.json"
    The variable CURRENT_VERSION should be undefined
    The variable PROJECT_VERSION should be undefined
  End

  It 'skips version update when already set in environment'
    export CURRENT_VERSION="1.2.3-SNAPSHOT"
    export PROJECT_VERSION="1.2.3-42"
    export BUILD_NUMBER="42"
    export GITHUB_REF_NAME="main"
    When call set_project_version
    The status should be success
    The line 1 should equal "Setting project version..."
    The line 2 should equal "Using provided CURRENT_VERSION 1.2.3-SNAPSHOT and PROJECT_VERSION 1.2.3-42 without changes."
    The contents of file "$GITHUB_OUTPUT" should include "current-version=1.2.3-SNAPSHOT"
    The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.3-42"
  End

  It 'skips version update on maintenance branch with release version'
    export MOCK_VERSION="1.2.3"
    export BUILD_NUMBER="42"
    export GITHUB_REF_NAME="branch-1.2"
    When call set_project_version
    The status should be success
    The line 1 should equal "Setting project version..."
    The line 2 should equal "CURRENT_VERSION=1.2.3 (from package.json)"
    The line 3 should equal "Found RELEASE version on maintenance branch, skipping version update."
    The contents of file "$GITHUB_OUTPUT" should include "current-version=1.2.3"
    The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.3"
    The contents of file "$GITHUB_ENV" should include "CURRENT_VERSION=1.2.3"
    The contents of file "$GITHUB_ENV" should include "PROJECT_VERSION=1.2.3"
    The variable CURRENT_VERSION should equal "1.2.3"
    The variable PROJECT_VERSION should equal "1.2.3"
  End

  It 'adds .0 to 2-digit version numbers'
    export MOCK_VERSION="1.2-SNAPSHOT"
    export BUILD_NUMBER="42"
    export GITHUB_REF_NAME="main"
    When call set_project_version
    The status should be success
    The line 1 should equal "Setting project version..."
    The line 2 should equal "CURRENT_VERSION=1.2-SNAPSHOT (from package.json)"
    The line 3 should equal "Replacing version 1.2-SNAPSHOT with 1.2.0-42"
    The contents of file "$GITHUB_OUTPUT" should include "current-version=1.2-SNAPSHOT"
    The contents of file "$GITHUB_OUTPUT" should include "project-version=1.2.0-42"
    The contents of file "$GITHUB_ENV" should include "CURRENT_VERSION=1.2-SNAPSHOT"
    The contents of file "$GITHUB_ENV" should include "PROJECT_VERSION=1.2.0-42"
    The variable CURRENT_VERSION should equal "1.2-SNAPSHOT"
    The variable PROJECT_VERSION should equal "1.2.0-42"
  End

  It 'handles 2-digit version in maintenance branch SNAPSHOT'
    export MOCK_VERSION="1.2-SNAPSHOT"
    export GITHUB_REF_NAME="branch-1.2"
    export PROJECT="test-project"
    export BUILD_NUMBER="42"
    When call set_project_version
    The status should be success
    The line 1 should equal "Setting project version..."
    The line 2 should equal "CURRENT_VERSION=1.2-SNAPSHOT (from package.json)"
    The line 3 should equal "Replacing version 1.2-SNAPSHOT with 1.2.0-42"
  End
End

Describe 'main()'
  It 'runs tool checks and calls set_build_env and set_project_version'
    export GITHUB_REF_NAME="main"
    When run script config-npm/config.sh
    The status should be success
    The lines of stdout should equal 23
    The line 1 should include "Check tools"
    The line 2 should include "jq"
    The line 3 should equal "jq-1.8.1"
    The line 4 should include "jf"
    The line 5 should equal "jf version 2.77.0"
    The line 6 should include "npm"
    The line 7 should equal "10.2.4"
    The line 9 should include "Setup build environment"
    The line 10 should include "Configuring JFrog and NPM repositories"
    The line 17 should include "Set project version"
    The line 19 should equal "CURRENT_VERSION=1.2.3-SNAPSHOT (from package.json)"
    The line 20 should include "Replacing version"
  End
End

rm package.json
