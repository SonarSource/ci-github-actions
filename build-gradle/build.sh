#!/bin/bash
# Build script for SonarSource Gradle projects.
# Supports building, testing, SonarQube analysis, and Artifactory deployment.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_PLATFORM: SonarQube primary platform (next, sqc-eu, or sqc-us)
# - NEXT_URL: URL of SonarQube server for next platform
# - NEXT_TOKEN: Access token to send analysis reports to SonarQube for next platform
# - SQC_US_URL: URL of SonarQube server for sqc-us platform
# - SQC_US_TOKEN: Access token to send analysis reports to SonarQube for sqc-us platform
# - SQC_EU_URL: URL of SonarQube server for sqc-eu platform
# - SQC_EU_TOKEN: Access token to send analysis reports to SonarQube for sqc-eu platform
# - RUN_SHADOW_SCANS: If true, run sonar scanner on all 3 platforms. If false, run on the platform provided by SONAR_PLATFORM.
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - ARTIFACTORY_DEPLOY_REPO: Name of deployment repository
# - ARTIFACTORY_DEPLOY_USERNAME: Username to deploy to Artifactory
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to Artifactory
# - ORG_GRADLE_PROJECT_signingKey: OpenPGP key for signing artifacts (private key content)
# - ORG_GRADLE_PROJECT_signingPassword: Passphrase of the signing key
# - ORG_GRADLE_PROJECT_signingKeyId: OpenPGP subkey id
# - DEFAULT_BRANCH: Default branch name (e.g. main)
# - PULL_REQUEST: Pull request number (e.g. 1234) or empty string
# - PULL_REQUEST_SHA: Pull request base SHA or empty string
#
# GitHub Actions auto-provided:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-gradle)
# - GITHUB_RUN_ID: GitHub workflow run ID
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_BASE_REF: Base branch for pull requests (only during pull_request events)
#
# Optional user customization:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - SKIP_TESTS: Whether to skip running tests (default: false)
# - GRADLE_ARGS: Additional arguments to pass to Gradle
#
# Auto-derived by script:
# - PROJECT: Project name derived from GITHUB_REPOSITORY
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# Source common functions shared across build scripts
# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}"
: "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${SONAR_PLATFORM:?}" "${RUN_SHADOW_SCANS:?}"
: "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
: "${ORG_GRADLE_PROJECT_signingKey:?}" "${ORG_GRADLE_PROJECT_signingPassword:?}" "${ORG_GRADLE_PROJECT_signingKeyId:?}"
: "${DEPLOY_PULL_REQUEST:=false}" "${SKIP_TESTS:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST
: "${GRADLE_ARGS:=}"

command_exists() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

set_build_env() {
  # Set default values
  : "${DEPLOY_PULL_REQUEST:=false}"
  : "${SKIP_TESTS:=false}"
  : "${GRADLE_ARGS:=}"
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"

  echo "Fetching commit history for SonarQube analysis..."
  git fetch --unshallow || true

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    echo "Fetching base branch: $GITHUB_BASE_REF"
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

set_project_version() {
  current_version=$($GRADLE_CMD properties --no-scan --no-daemon --console plain | grep 'version:' | tr -d "[:space:]" | cut -d ":" -f 2)
  export CURRENT_VERSION=$current_version
  release_version="${current_version/-SNAPSHOT/}"
  if [[ "${release_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    release_version="${release_version}.0"
  fi
  release_version="${release_version}.${BUILD_NUMBER}"
  echo "Replacing version $current_version with $release_version"
  sed -i.bak "s/$current_version/$release_version/g" gradle.properties
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
  export PROJECT_VERSION=$release_version
}

build_gradle_args() {
  local args=()

  # Base arguments
  args+=("--no-daemon" "--info" "--stacktrace" "--console" "plain")

  args+=("build")

  if [[ "$SKIP_TESTS" == "true" ]]; then
    args+=("-x" "test")
  fi

  # SonarQube analysis (orchestrator will provide SONAR_HOST_URL and SONAR_TOKEN)
  if [[ -n "${SONAR_HOST_URL:-}" && -n "${SONAR_TOKEN:-}" ]]; then
    args+=("sonar")
    args+=("-Dsonar.host.url=$SONAR_HOST_URL")
    args+=("-Dsonar.token=$SONAR_TOKEN")
    args+=("-Dsonar.analysis.buildNumber=$BUILD_NUMBER")
    args+=("-Dsonar.analysis.pipeline=$GITHUB_RUN_ID")
    args+=("-Dsonar.analysis.repository=$GITHUB_REPOSITORY")
    args+=("-Dsonar.projectVersion=${CURRENT_VERSION}")
    args+=("-Dsonar.scm.revision=$GITHUB_SHA")

    # Add branch-specific sonar arguments
    if is_default_branch && ! is_pull_request; then
      # Master branch analysis
      args+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

    elif is_maintenance_branch && ! is_pull_request; then
      # Maintenance branch analysis
      args+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
      args+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

    elif is_pull_request; then
      # Pull request analysis
      args+=("-Dsonar.analysis.sha1=$PULL_REQUEST_SHA")
      args+=("-Dsonar.analysis.prNumber=$PULL_REQUEST")

    elif is_long_lived_feature_branch && ! is_pull_request; then
      # Long-lived feature branch analysis
      args+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
      args+=("-Dsonar.analysis.sha1=$GITHUB_SHA")
    fi
  fi

  if should_deploy; then
    args+=("artifactoryPublish")
  fi

  # Build number
  args+=("-DbuildNumber=$BUILD_NUMBER")

  # Additional arguments
  if [[ -n "$GRADLE_ARGS" ]]; then
    read -ra extra_args <<< "$GRADLE_ARGS"
    args+=("${extra_args[@]}")
  fi

  echo "${args[@]}"
}

should_deploy() {
  # Disable deployment when shadow scans are enabled to prevent duplicate artifacts
  if [[ "${RUN_SHADOW_SCANS}" == "true" ]]; then
    return 1
  fi

  if is_pull_request; then
    # For pull requests, deploy only if explicitly enabled
    [[ "$DEPLOY_PULL_REQUEST" == "true" ]]
  else
    is_default_branch || \
    is_maintenance_branch || \
    is_dogfood_branch || \
    is_long_lived_feature_branch
  fi
}

get_build_type() {
  if is_default_branch && ! is_pull_request; then
    echo "default branch"
  elif is_maintenance_branch && ! is_pull_request; then
    echo "maintenance branch"
  elif is_pull_request; then
    echo "pull request"
  elif is_dogfood_branch && ! is_pull_request; then
    echo "dogfood branch"
  elif is_long_lived_feature_branch && ! is_pull_request; then
    echo "long-lived feature branch"
  else
    echo "regular build"
  fi
}

is_default_branch() {
  [[ "$GITHUB_REF_NAME" == "$DEFAULT_BRANCH" ]]
}

is_maintenance_branch() {
  [[ "${GITHUB_REF_NAME}" == "branch-"* ]]
}

is_pull_request() {
  [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]
}

is_dogfood_branch() {
  [[ "${GITHUB_REF_NAME}" == "dogfood-on-"* ]]
}

is_long_lived_feature_branch() {
  [[ "${GITHUB_REF_NAME}" == "feature/long/"* ]]
}

set_gradle_cmd() {
  if [[ -f "./gradlew" ]]; then
    export GRADLE_CMD="./gradlew"
  elif command_exists gradle; then
    export GRADLE_CMD="gradle"
  else
    echo "Neither ./gradlew nor gradle command found!" >&2
    exit 1
  fi
}

# CALLBACK IMPLEMENTATION: SonarQube scanner execution
#
# This function is called BY THE ORCHESTRATOR (orchestrate_sonar_platforms)
# The orchestrator will:
# 1. Set SONAR_HOST_URL and SONAR_TOKEN for the current platform
# 2. Call this function to execute the actual scanner
# 3. Repeat for each platform (if shadow scanning enabled)
sonar_scanner_implementation() {
  local gradle_args
  read -ra gradle_args <<< "$(build_gradle_args)"
  echo "Gradle command: $GRADLE_CMD ${gradle_args[*]}"
  "$GRADLE_CMD" "${gradle_args[@]}"
}

gradle_build() {
  local build_type
  build_type=$(get_build_type)
  echo "Starting $build_type build..."
  echo "Sonar Platform: ${SONAR_PLATFORM}"
  echo "Run Shadow Scans: ${RUN_SHADOW_SCANS}"

  # This will call back to sonar_scanner_implementation() function
  # No additional arguments needed as branch-specific args are handled in build_gradle_args()
  # TODO: Add support for sonar-platform=none to skip sonar analysis entirely
  # shellcheck disable=SC2119
  orchestrate_sonar_platforms
}

main() {
  # Unsetting JAVA_HOME fixes an issue on GitHub hosted Windows runners, where JAVA_HOME is set by default
  # and Gradle prioritizes this JDK instead of using the JDK from the path.
  unset JAVA_HOME
  command_exists java -version
  set_gradle_cmd
  set_build_env
  set_project_version
  gradle_build
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
