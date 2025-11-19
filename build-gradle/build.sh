#!/bin/bash
# Build script for SonarSource Gradle projects.
# Supports building, testing, SonarQube analysis, and Artifactory deployment.
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
# - CURRENT_VERSION: Current project version as in gradle.properties
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
# - DEPLOY: Whether to deploy (default: true)
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - SKIP_TESTS: Whether to skip running tests (default: false)
# - GRADLE_ARGS: Additional arguments to pass to Gradle
#
# Auto-derived by script:
# - PROJECT: Project name derived from GITHUB_REPOSITORY
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${RUN_SHADOW_SCANS:?}"
: "${CURRENT_VERSION:?}"
if [[ "${SONAR_PLATFORM:?}" != "none" ]]; then
  : "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
fi
: "${ORG_GRADLE_PROJECT_signingKey:?}" "${ORG_GRADLE_PROJECT_signingPassword:?}" "${ORG_GRADLE_PROJECT_signingKeyId:?}"
: "${DEPLOY_PULL_REQUEST:=false}" "${DEPLOY:=true}"
export DEPLOY_PULL_REQUEST
: "${SKIP_TESTS:=false}"
: "${GRADLE_ARGS:=}"

git_fetch_unshallow() {
  if [ "$SONAR_PLATFORM" = "none" ]; then
    echo "Skipping git fetch (Sonar analysis disabled)"
    return 0
  fi

  echo "Fetching commit history for SonarQube analysis..."
  git fetch --unshallow || true

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    echo "Fetching base branch: $GITHUB_BASE_REF"
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

set_build_env() {
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"
  git_fetch_unshallow
}

should_deploy() {
  # Disable deployment when explicitly requested
  if [[ "${DEPLOY}" != "true" ]]; then
    return 1
  fi

  # Disable deployment when shadow scans are enabled to prevent duplicate artifacts
  if [[ "${RUN_SHADOW_SCANS}" = "true" ]]; then
    echo "Shadow scans enabled - disabling deployment" >&2
    return 1
  fi

  if is_pull_request; then
    # For pull requests, deploy only if explicitly enabled
    [[ "$DEPLOY_PULL_REQUEST" = "true" ]]
  else
    is_default_branch || \
    is_maintenance_branch || \
    is_dogfood_branch || \
    is_long_lived_feature_branch
  fi
}

build_gradle_args() {
  local args=()

  # Base arguments
  args+=("--no-daemon" "--stacktrace" "--console" "plain")

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
    if is_default_branch; then
      # Master branch analysis
      args+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

    elif is_maintenance_branch; then
      # Maintenance branch analysis
      args+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
      args+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

    elif is_pull_request; then
      # Pull request analysis
      args+=("-Dsonar.analysis.sha1=$PULL_REQUEST_SHA")
      args+=("-Dsonar.analysis.prNumber=$PULL_REQUEST")

    elif is_long_lived_feature_branch; then
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

set_gradle_cmd() {
  if [[ -f "./gradlew" ]]; then
    check_tool ./gradlew --version
    export GRADLE_CMD="./gradlew"
  elif check_tool gradle --version; then
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
gradle_build_and_analyze() {
  local gradle_args
  read -ra gradle_args <<< "$(build_gradle_args)"
  echo "Gradle command: $GRADLE_CMD ${gradle_args[*]}"
  "$GRADLE_CMD" "${gradle_args[@]}"
  if should_deploy; then
    echo "deployed=true" >> "$GITHUB_OUTPUT"
    export_built_artifacts
  fi
}

# ORCHESTRATOR CONTRACT: Required callback function
# This function must exist for orchestrate_sonar_platforms() to work
# It delegates to the actual implementation
sonar_scanner_implementation() {
  gradle_build_and_analyze "$@"
}

gradle_build() {
  local build_type
  build_type=$(get_build_type)
  echo "Starting $build_type build..."
  echo "Sonar Platform: ${SONAR_PLATFORM}"
  echo "Run Shadow Scans: ${RUN_SHADOW_SCANS}"

  if [[ "$SONAR_PLATFORM" == "none" ]]; then
    # Build without sonar - call gradle_build_and_analyze directly
    gradle_build_and_analyze
  else
    # Build with sonar analysis via orchestrator
    # shellcheck disable=SC2119
    orchestrate_sonar_platforms
  fi
}

export_built_artifacts() {
  if ! should_deploy; then
    return 0
  fi

  echo "::group::Capturing built artifacts for attestation"

  # Find all built artifacts, excluding sources/javadoc/tests JARs
  local artifacts
  local path_includes=(-path '*/build/libs/*' -o -path '*/build/distributions/*' -o -path '*/build/reports/*')
  local name_includes=(-name '*.jar' -o -name '*.war' -o -name '*.ear' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar')
  name_includes+=(-o -name '*.json')
  local name_excludes=(! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-tests.jar')
  artifacts=$(/usr/bin/find . \( "${path_includes[@]}" \) \( "${name_includes[@]}" \) "${name_excludes[@]}" -type f 2>/dev/null)

  # Sort and deduplicate (avoid Windows sort.exe)
  if [[ -n "$artifacts" ]]; then
    artifacts=$(echo "$artifacts" | /usr/bin/sort -u)
  fi

  if [[ -z "$artifacts" ]]; then
    echo "::warning title=No artifacts found::No artifacts found for attestation in build output directories"
    echo "::endgroup::"
    return 0
  fi

  echo "Found artifacts for attestation:"
  echo "$artifacts"

  {
    echo "artifact-paths<<EOF"
    echo "$artifacts"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"

  echo "::endgroup::"
}

main() {
  check_tool java -version
  set_gradle_cmd
  set_build_env
  gradle_build
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
