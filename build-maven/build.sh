#!/bin/bash
# Build and deploy a Maven project.
# Supports building, testing, SonarQube analysis, and Maven deployment to Artifactory.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_PLATFORM: SonarQube primary platform (next, sqc-eu, sqc-us, or none). Use 'none' to skip sonar scans.
# - NEXT_URL: URL of SonarQube server for next platform
# - NEXT_TOKEN: Access token to send analysis reports to SonarQube for next platform
# - SQC_US_URL: URL of SonarQube server for sqc-us platform
# - SQC_US_TOKEN: Access token to send analysis reports to SonarQube for sqc-us platform
# - SQC_EU_URL: URL of SonarQube server for sqc-eu platform
# - SQC_EU_TOKEN: Access token to send analysis reports to SonarQube for sqc-eu platform
# - RUN_SHADOW_SCANS: If true, run sonar scanner on all 3 platforms. If false, run on the platform provided by SONAR_PLATFORM.
# - ARTIFACTORY_URL: Artifactory repository URL
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - ARTIFACTORY_DEPLOY_REPO: Deployment repository name
# - ARTIFACTORY_DEPLOY_USERNAME: Username used by artifactory-maven-plugin
# - ARTIFACTORY_DEPLOY_PASSWORD: Access token to deploy to the repository
# - DEFAULT_BRANCH: Default branch name (e.g. main)
# - PULL_REQUEST: Pull request number (e.g. 1234) or empty string
#
# GitHub Actions auto-provided:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-maven)
# - GITHUB_RUN_ID: GitHub workflow run ID
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_BASE_REF: Base branch for pull requests (only during pull_request events)
# - GITHUB_HEAD_REF: Head branch for pull requests (only during pull_request events)
# - RUNNER_OS: Operating system (e.g. Linux, Windows)
#
# Optional user customization:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - MAVEN_LOCAL_REPOSITORY: Path to Maven local repository (default: $HOME/.m2/repository)
# - MAVEN_SETTINGS: Path to Maven settings.xml (default: $HOME/.m2/settings.xml)
# - MAVEN_OPTS: JVM options for Maven (e.g. -Xmx1536m -Xms128m)
# - SONAR_SCANNER_JAVA_OPTS: JVM options for SonarQube scanner (e.g. -Xmx512m)
# - SCANNER_VERSION: SonarQube Maven plugin version (default: 5.1.0.4751)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# Source common functions shared across build scripts
# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}"
# Required by maven-enforcer-plugin in SonarSource parent POM
: "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_PASSWORD:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}"
: "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${RUNNER_OS:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${SONAR_PLATFORM:?}"
if [[ "${SONAR_PLATFORM}" != "none" ]]; then
  : "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
fi
: "${RUN_SHADOW_SCANS:?}"
: "${MAVEN_LOCAL_REPOSITORY:=$HOME/.m2/repository}"
: "${DEPLOY_PULL_REQUEST:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST MAVEN_LOCAL_REPOSITORY
: "${MAVEN_SETTINGS:=$HOME/.m2/settings.xml}"

# FIXME Workaround for SonarSource parent POM; it can be removed after releases of parent 73+ and parent-oss 84+
export BUILD_ID=$BUILD_NUMBER

# Handle Windows path conversion for Maven settings
if [[ "$RUNNER_OS" == "Windows" ]]; then
  # Convert Unix-style path to Windows format for Maven
  MAVEN_SETTINGS=$(cygpath -w "$MAVEN_SETTINGS" 2>/dev/null || echo "$MAVEN_SETTINGS")
fi

# SonarQube parameters
: "${SCANNER_VERSION:=5.1.0.4751}"
readonly SONAR_GOAL="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"

# Common Maven flags used across build and analysis operations, exclude from coverage
# LCOV_EXCL_START
readonly COMMON_MVN_FLAGS=(
  "-Dmaven.test.redirectTestOutputToFile=false"
  "--settings" "$MAVEN_SETTINGS"
  "--batch-mode"
  "--no-transfer-progress"
  "--errors"
  "--fail-at-end"
  "--show-version"
)
# LCOV_EXCL_STOP

# Check if a command is available and runs it, typically: 'some_tool --version'
check_tool() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

# CALLBACK IMPLEMENTATION: SonarQube scanner execution
#
# This function is called BY THE ORCHESTRATOR (orchestrate_sonar_platforms)
# INVERSION OF CONTROL: We implement this interface, orchestrator calls us
# The orchestrator will:
# 1. Set SONAR_HOST_URL and SONAR_TOKEN for the current platform
# 2. Call this function to execute the actual scanner
# 3. Repeat for each platform (if shadow scanning enabled)
sonar_scanner_implementation() {
    local additional_params=("$@")
    # Build sonar properties (using orchestrator-provided SONAR_HOST_URL/SONAR_TOKEN)
    local sonar_props=("-Dsonar.host.url=${SONAR_HOST_URL}" "-Dsonar.token=${SONAR_TOKEN}")
    sonar_props+=("-Dsonar.projectVersion=${CURRENT_VERSION}" "-Dsonar.scm.revision=$GITHUB_SHA")
    if [[ -n "${PROJECT_KEY:-}" ]]; then
      sonar_props+=("-Dsonar.projectKey=${PROJECT_KEY}" "-Dsonar.organization=sonarsource")
    fi
    sonar_props+=("${additional_params[@]+"${additional_params[@]}"}")

    echo "Maven command: mvn ${COMMON_MVN_FLAGS[*]} $SONAR_GOAL ${sonar_props[*]}"
    mvn "${COMMON_MVN_FLAGS[@]}" "$SONAR_GOAL" "${sonar_props[@]}"
}

is_default_branch() {
  [[ "$GITHUB_REF_NAME" == "$DEFAULT_BRANCH" ]]
}

is_maintenance_branch() {
  [[ "${GITHUB_REF_NAME}" == branch-* ]]
}

is_pull_request() {
  [[ "$GITHUB_EVENT_NAME" == pull_request ]]
}

is_dogfood_branch() {
  [[ "${GITHUB_REF_NAME}" == dogfood-on-* ]]
}

is_long_lived_feature_branch() {
  [[ "${GITHUB_REF_NAME}" == feature/long/* ]]
}

# Unshallow and fetch all commit history for SonarQube analysis and issue assignment
git_fetch_unshallow() {
  if [ "$SONAR_PLATFORM" = "none" ]; then
    echo "Skipping git fetch (Sonar analysis disabled)"
    return 0
  fi

  if git rev-parse --is-shallow-repository --quiet >/dev/null 2>&1; then
    echo "Fetch Git references for SonarQube analysis..."
    git fetch --unshallow
  elif is_pull_request; then
    echo "Fetch ${GITHUB_BASE_REF:?} for SonarQube analysis..."
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

# Evaluate a Maven property/expression with org.codehaus.mojo:exec-maven-plugin
maven_expression() {
  if ! mvn --settings "$MAVEN_SETTINGS" -q -Dexec.executable="echo" -Dexec.args="\${$1}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec; then
    echo "Failed to evaluate Maven expression '$1'" >&2
    mvn --settings "$MAVEN_SETTINGS" -X -Dexec.executable="echo" -Dexec.args="\${$1}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec
    return 1
  fi
}

# Set the project version as <MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>
# Update current_version variable with the current project version.
# Then remove the -SNAPSHOT suffix if present, complete with '.0' if needed, and append the build number at the end.
set_project_version() {
  if [ ! -f "$MAVEN_SETTINGS" ]; then
    echo "::error title=Missing Maven settings.xml::Maven settings.xml file not found at $MAVEN_SETTINGS"
    return 1
  fi
  local current_version
  if ! current_version=$(maven_expression "project.version" 2>&1); then
    echo -e "::error file=pom.xml,title=Maven project version::Could not get 'project.version' from Maven project\nERROR: $current_version"
    return 1
  fi
  export CURRENT_VERSION=$current_version

  local release_version="${current_version%"-SNAPSHOT"}"
  local digits="${release_version//[^.]/}"
  local digit_count="${#digits}"

  # shellcheck disable=SC2035
  if is_maintenance_branch && [[ "$current_version" != *"-SNAPSHOT" ]]; then
    if [[ "$digit_count" -ne 3 ]]; then
      echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
      return 1
    fi
    echo "Found RELEASE version on maintenance branch: ${current_version}. Skipping version update."
    export PROJECT_VERSION=$release_version
    return 0
  fi

  if [[ "$digit_count" -eq 0 ]]; then
    release_version="${release_version}.0.0"
  elif [[ "$digit_count" -eq 1 ]]; then
    release_version="${release_version}.0"
  elif [[ "$digit_count" -ne 2 ]]; then
    echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
    return 1
  fi
  release_version="${release_version}.${BUILD_NUMBER}"

  echo "Replacing version $current_version with $release_version"
  mvn --settings "$MAVEN_SETTINGS" org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion="$release_version" -DgenerateBackupPoms=false -B -e
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  export PROJECT_VERSION=$release_version
}

build_maven() {
  check_tool mvn --version
  git_fetch_unshallow

  set_project_version

  local maven_command_args
  local enable_sonar=false
  local sonar_args=()

  if is_default_branch || is_maintenance_branch; then
    echo "======= Build, deploy and analyze $GITHUB_REF_NAME ======="
    maven_command_args=("deploy" "-Pcoverage,deploy-sonarsource,release,sign")
    enable_sonar=true

  elif is_pull_request; then
    echo "======= Build and analyze pull request $PULL_REQUEST ($GITHUB_HEAD_REF) ======="
    sonar_args+=("-Dsonar.pullrequest.key=$PULL_REQUEST")
    sonar_args+=("-Dsonar.pullrequest.branch=$GITHUB_HEAD_REF")
    sonar_args+=("-Dsonar.pullrequest.base=$GITHUB_BASE_REF")

    if [[ "$DEPLOY_PULL_REQUEST" == "true" ]]; then
      echo "======= with deploy ======="
      maven_command_args=("deploy" "-Pcoverage,deploy-sonarsource")
    else
      echo "======= no deploy ======="
      maven_command_args=("verify" "-Pcoverage")
    fi
    enable_sonar=true

  elif is_dogfood_branch; then
    echo "======= Build, and deploy dogfood branch $GITHUB_REF_NAME ======="
    maven_command_args=("deploy" "-Pdeploy-sonarsource,release")

  elif is_long_lived_feature_branch; then
    echo "======= Build and analyze long lived feature branch $GITHUB_REF_NAME ======="
    maven_command_args=("verify" "-Pcoverage")
    enable_sonar=true

  else
    echo "======= Build, no analysis, no deploy $GITHUB_REF_NAME ======="
    maven_command_args=("verify")
  fi

  # Disable deployment when running shadow scans
  if [ "${RUN_SHADOW_SCANS}" = "true" ]; then
    echo "Shadow scans enabled - disabling deployment"
    # Replace deploy with verify to disable deployment
    if [[ "${maven_command_args[0]}" == "deploy" ]]; then
      maven_command_args[0]="verify"
      # Remove deploy-specific profiles but keep others
      for i in "${!maven_command_args[@]}"; do
        if [[ "${maven_command_args[$i]}" == *"deploy-sonarsource"* ]]; then
          # Remove deploy-sonarsource from profiles
          maven_command_args[i]=$(echo "${maven_command_args[i]}" | sed 's/,deploy-sonarsource//g' | sed 's/deploy-sonarsource,//g' | sed 's/deploy-sonarsource//g')
        fi
      done
    fi
  fi

  # Execute the main Maven build
  echo "Maven command: mvn ${maven_command_args[*]} ${COMMON_MVN_FLAGS[*]} $*"
  mvn "${maven_command_args[@]}" "${COMMON_MVN_FLAGS[@]}" "$@"

  # Execute SonarQube analysis if enabled
  if [ "$enable_sonar" = true ]; then
    # This will call back to shared sonar_scanner_implementation() function
    orchestrate_sonar_platforms "${sonar_args[@]+"${sonar_args[@]}"}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_maven "$@"
fi
