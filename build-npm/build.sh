#!/bin/bash
# Build script for SonarSource NPM projects.
# Supports building, testing, SonarQube analysis, and JFrog Artifactory deployment.
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
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to Artifactory
# - ARTIFACTORY_DEPLOY_REPO: Name of deployment repository
# - DEFAULT_BRANCH: Default branch name (e.g. main)
# - PULL_REQUEST: Pull request number (e.g. 1234) or empty string
# - PULL_REQUEST_SHA: Pull request base SHA or empty string
#
# GitHub Actions auto-provided:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name in format "owner/repo"
# - GITHUB_RUN_ID: GitHub Actions run ID
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_BASE_REF: Base branch for pull requests (only during pull_request events)
#
# Optional user customization:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - SKIP_TESTS: Whether to skip running tests (default: false)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}"
: "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${SONAR_PLATFORM:?}" "${RUN_SHADOW_SCANS:?}"
if [[ "${SONAR_PLATFORM}" != "none" ]]; then
  : "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
fi
: "${DEPLOY_PULL_REQUEST:=false}" "${SKIP_TESTS:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST SKIP_TESTS

git_fetch_unshallow() {
  if [ "$SONAR_PLATFORM" = "none" ]; then
    echo "Skipping git fetch (Sonar analysis disabled)"
    return 0
  fi

  if git rev-parse --is-shallow-repository --quiet >/dev/null 2>&1; then
    echo "Fetch Git references for SonarQube analysis..."
    git fetch --unshallow
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    echo "Fetch ${GITHUB_BASE_REF} for SonarQube analysis..."
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

set_build_env() {
  export PROJECT="${GITHUB_REPOSITORY#*/}"
  echo "PROJECT: ${PROJECT}"

  echo "::debug::Configuring JFrog and NPM repositories..."
  npm config set registry "$ARTIFACTORY_URL/api/npm/npm"
  npm config set "${ARTIFACTORY_URL//https:}/api/npm/:_authToken=$ARTIFACTORY_ACCESS_TOKEN"
  jf config remove repox > /dev/null 2>&1 || true # Do not log if the repox config were not present
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox
  jf npm-config --repo-resolve "npm"
}

# Version utility functions (from npm_version_utils and version_util)
PACKAGE_JSON="package.json"

check_version_format() {
  local version="$1"
  # Check if version follows semantic versioning pattern (X.Y.Z or X.Y.Z-something)
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "WARN: Version '${version}' does not match semantic versioning format (e.g., '1.2.3' or '1.2.3-beta.1')." >&2
  fi
}

set_project_version() {
  local current_version release_version digit_count

  current_version=$(jq -r .version "$PACKAGE_JSON")
  if [ -z "${current_version}" ] || [ "${current_version}" == "null" ]; then
    echo "Could not get version from ${PACKAGE_JSON}" >&2
    exit 1
  fi
  export CURRENT_VERSION=$current_version

  release_version="${current_version}"
  if ! is_pull_request; then
    if is_maintenance_branch && [[ ! ${current_version} =~ "-SNAPSHOT" ]]; then
      echo "Found RELEASE version on maintenance branch, skipping version update."
    else
      release_version="${current_version%"-SNAPSHOT"}"
      digit_count=$(echo "${release_version//./ }" | wc -w)
      if [ "${digit_count}" -lt 3 ]; then
          release_version="${release_version}.0"
      fi
      release_version="${release_version}-${BUILD_NUMBER}"
      echo "Replacing version ${current_version} with ${release_version}"
      npm version --no-git-tag-version --allow-same-version "${release_version}"
    fi
  fi
  check_version_format "${release_version}"
  echo "project-version=${release_version}" >> "${GITHUB_OUTPUT}"
  export PROJECT_VERSION=$release_version
}

# CALLBACK IMPLEMENTATION: SonarQube scanner execution
#
# This function is called BY THE ORCHESTRATOR (orchestrate_sonar_platforms)
# The orchestrator will:
# 1. Set SONAR_HOST_URL and SONAR_TOKEN for the current platform
# 2. Call this function to execute the actual scanner
# 3. Repeat for each platform (if shadow scanning enabled)
sonar_scanner_implementation() {
    local additional_params=("$@")
    # Build base scanner arguments (using orchestrator-provided SONAR_HOST_URL/SONAR_TOKEN)
    local scanner_args=()
    scanner_args+=("-Dsonar.host.url=${SONAR_HOST_URL}")
    scanner_args+=("-Dsonar.token=${SONAR_TOKEN}")
    scanner_args+=("-Dsonar.analysis.buildNumber=${BUILD_NUMBER}")
    scanner_args+=("-Dsonar.analysis.pipeline=${GITHUB_RUN_ID}")
    scanner_args+=("-Dsonar.analysis.sha1=${GITHUB_SHA}")
    scanner_args+=("-Dsonar.analysis.repository=${GITHUB_REPOSITORY}")
    scanner_args+=("-Dsonar.projectVersion=${CURRENT_VERSION}")
    scanner_args+=("-Dsonar.scm.revision=${GITHUB_SHA}")

    # Add region parameter only for sqc-us platform
    if [ -n "${SONAR_REGION:-}" ]; then
        scanner_args+=("-Dsonar.region=${SONAR_REGION}")
    fi

    scanner_args+=("${additional_params[@]+\"${additional_params[@]}\"}")

    echo "npx command: npx sonarqube-scanner -X ${scanner_args[*]}"
    npx sonarqube-scanner -X "${scanner_args[@]}"
}


jfrog_npm_publish() {
  echo "::debug::Configuring JFrog and NPM repositories..."
  jf config remove repox > /dev/null 2>&1 || true # Do not log if the repox config were not present
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
  jf npm-config --repo-resolve "npm" --repo-deploy "$ARTIFACTORY_DEPLOY_REPO"

  echo "::debug::Publishing NPM package..."
  jf npm publish --build-name="$PROJECT" --build-number="$BUILD_NUMBER"

  jf rt build-collect-env "$PROJECT" "$BUILD_NUMBER"

  echo "::debug::Publishing build info..."
  local build_publish_output
  build_publish_output=$(jf rt build-publish "$PROJECT" "$BUILD_NUMBER")
  echo "::debug::Build publish output: ${build_publish_output}"

  # Extract build info URL
  local build_info_url
  build_info_url=$(echo "$build_publish_output" | jq -r '.buildInfoUiUrl // empty')
  if [ -n "$build_info_url" ]; then
    echo "build-info-url=$build_info_url" >> "$GITHUB_OUTPUT"
    echo "::debug::Build info URL saved: $build_info_url"
  fi
}

# Determine build configuration based on branch type
get_build_config() {
  local enable_sonar enable_deploy
  local sonar_args=()

  if is_default_branch && ! is_pull_request; then
    echo "======= Building main branch ======="
    enable_sonar=true
    enable_deploy=true

  elif is_maintenance_branch && ! is_pull_request; then
    echo "======= Building maintenance branch ======="
    enable_sonar=true
    enable_deploy=true
    sonar_args=("-Dsonar.branch.name=${GITHUB_REF_NAME}")

  elif is_pull_request; then
    echo "======= Building pull request ======="
    enable_sonar=true
    sonar_args=("-Dsonar.analysis.prNumber=${PULL_REQUEST}")

    if [ "${DEPLOY_PULL_REQUEST:-false}" == "true" ]; then
      echo "======= with deploy ======="
      enable_deploy=true
    else
      echo "======= no deploy ======="
      enable_deploy=false
    fi

  elif is_dogfood_branch && ! is_pull_request; then
    echo "======= Build dogfood branch ======="
    enable_sonar=false
    enable_deploy=true

  elif is_long_lived_feature_branch && ! is_pull_request; then
    echo "======= Build long-lived feature branch ======="
    enable_sonar=true
    enable_deploy=false
    sonar_args=("-Dsonar.branch.name=${GITHUB_REF_NAME}")

  else
    echo "======= Build other branch ======="
    enable_sonar=false
    enable_deploy=false
  fi

  # Disable deployment when shadow scans are enabled to prevent duplicate artifacts
  if [ "${RUN_SHADOW_SCANS}" = "true" ]; then
    echo "======= Shadow scans enabled - disabling deployment to prevent duplicate artifacts ======="
    enable_deploy=false
  fi

  # Export the configuration for use by run_standard_pipeline
  export BUILD_ENABLE_SONAR="$enable_sonar"
  export BUILD_ENABLE_DEPLOY="$enable_deploy"
  export BUILD_SONAR_ARGS="${sonar_args[*]:-}"
}

# Complete build pipeline with optional steps
run_standard_pipeline() {
  echo "Installing npm dependencies..."
  npm ci

  if [ "$SKIP_TESTS" != "true" ]; then
    echo "Running tests..."
    npm test
  else
    echo "Skipping tests (SKIP_TESTS=true)"
  fi

  if [ "${BUILD_ENABLE_SONAR}" = "true" ]; then
    read -ra sonar_args <<< "$BUILD_SONAR_ARGS"
    # This will call back to shared sonar_scanner_implementation() function
    orchestrate_sonar_platforms "${sonar_args[@]+${sonar_args[@]}}"
  fi

  echo "Building project..."
  npm run build

  if [ "${BUILD_ENABLE_DEPLOY}" = "true" ]; then
    jfrog_npm_publish
  fi
}

build_npm() {
  echo "=== NPM Build, Deploy, and Analyze ==="
  echo "Branch: ${GITHUB_REF_NAME}"
  echo "Pull Request: ${PULL_REQUEST}"
  echo "Deploy Pull Request: ${DEPLOY_PULL_REQUEST}"
  echo "Skip Tests: ${SKIP_TESTS}"
  echo "Sonar Platform: ${SONAR_PLATFORM}"
  echo "Run Shadow Scans: ${RUN_SHADOW_SCANS}"
  get_build_config
  run_standard_pipeline
  echo "=== Build completed successfully ==="
}

main() {
  check_tool jq --version
  check_tool jf --version
  check_tool npm --version
  git_fetch_unshallow
  set_build_env
  set_project_version
  build_npm
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
