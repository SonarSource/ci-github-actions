#!/bin/bash
# Build script for SonarSource NPM projects.
# Supports building, testing, SonarQube analysis, and JFrog Artifactory deployment.
#
# Required environment variables:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name in format "owner/repo"
# - GITHUB_RUN_ID: GitHub Actions run ID
# - BUILD_NUMBER: Build number for versioning
# - SONAR_HOST_URL: URL of SonarQube server
# - SONAR_TOKEN: Access token to send analysis reports to SonarQube
# - ARTIFACTORY_URL: URL to Artifactory repository (required for deployment)
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to Artifactory (required for deployment)
# - ARTIFACTORY_DEPLOY_REPO: Name of deployment repository (used by jfrog_npm_publish)
#
# Optional environment variables:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - SKIP_TESTS: Whether to skip running tests (default: false)
# - DEFAULT_BRANCH: Main branch pattern (default: "main$|^master")
# - GITHUB_BASE_REF: Base branch for pull requests (auto-set by GitHub Actions)
# - GITHUB_OUTPUT: Path to GitHub Actions output file (auto-set by GitHub Actions)
# - PULL_REQUEST: Pull request number or "false" (auto-set by action)
# - PROJECT: Project name derived from GITHUB_REPOSITORY (auto-set by script)

set -euo pipefail

: "${ARTIFACTORY_URL:="https://repox.jfrog.io/artifactory"}"
: "${GITHUB_REF_NAME:?}" "${GITHUB_SHA:?}" "${GITHUB_REPOSITORY:?}"
: "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"

check_tool() {
  # Check if a command is available and runs it, typically: 'some_tool --version'
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

git_fetch_unshallow() {
  # The --filter=blob:none flag significantly speeds up the download
  if git rev-parse --is-shallow-repository --quiet >/dev/null 2>&1; then
    echo "Fetch Git references for SonarQube analysis..."
    git fetch --unshallow --filter=blob:none
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    echo "Fetch ${GITHUB_BASE_REF} for SonarQube analysis..."
    git fetch --filter=blob:none origin "${GITHUB_BASE_REF}"
  fi
}

set_build_env() {
  export PROJECT="${GITHUB_REPOSITORY#*/}"
  echo "PROJECT: ${PROJECT}"
  echo "Fetching commit history for SonarQube analysis..."
  git_fetch_unshallow
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

is_merge_queue_branch() {
  [[ "${GITHUB_REF_NAME}" == "gh-readonly-queue/"* ]]
}

# Version utility functions (from npm_version_utils and version_util)
PACKAGE_JSON="package.json"

set_project_version() {
  local current_version release_version digit_count

  current_version=$(jq -r .version "$PACKAGE_JSON")
  if [ -z "${current_version}" ] || [ "${current_version}" == "null" ]; then
    echo "Could not get version from ${PACKAGE_JSON}" >&2
    exit 1
  fi

  export CURRENT_VERSION="${current_version}"

  # Set version with build ID for most branch types
  # (maintenance branch handles this differently based on SNAPSHOT vs RELEASE)
  if ! is_maintenance_branch || is_pull_request; then
    release_version="${current_version%"-SNAPSHOT"}"

    # In case of 2 digits, we need to add the 3rd digit (0 obviously)
    # Mandatory in order to compare versions (patch VS non patch)
    digit_count=$(echo "${release_version//./ }" | wc -w)
    if [ "${digit_count}" -lt 3 ]; then
        release_version="${release_version}.0"
    fi
    PROJECT_VERSION="${release_version}-${BUILD_NUMBER}"

    echo "Replacing version ${current_version} with ${PROJECT_VERSION}"
    npm version --no-git-tag-version --allow-same-version "${PROJECT_VERSION}"
  else
    # For maintenance branches, keep original version initially
    PROJECT_VERSION="${current_version}"
  fi

  export PROJECT_VERSION
  echo "project-version=${PROJECT_VERSION}" >> "${GITHUB_OUTPUT}"
}

check_version_format() {
  local version="$1"
  local extracted_points point_count

  extracted_points="${version//[^.]}"
  point_count=${#extracted_points}
  if [[ "${point_count}" != 3 ]]; then
    echo "WARN: Version '${version}' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'." >&2
  fi
}

run_sonar_scanner() {
    local additional_params=("$@")

    npx sonarqube-scanner -X \
        -Dsonar.host.url="${SONAR_HOST_URL}" \
        -Dsonar.token="${SONAR_TOKEN}" \
        -Dsonar.analysis.buildNumber="${BUILD_NUMBER}" \
        -Dsonar.analysis.pipeline="${GITHUB_RUN_ID}" \
        -Dsonar.analysis.sha1="${GITHUB_SHA}" \
        -Dsonar.analysis.repository="${GITHUB_REPOSITORY}" \
        "${additional_params[@]}"
    echo "SonarQube scanner finished"
}

jfrog_npm_publish() {
  if [ -z "${ARTIFACTORY_URL:-}" ] || [ -z "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:-}" ]; then
    echo "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN to be set" >&2
    exit 1
  fi

  echo "DEBUG: Removing existing JFrog config..."
  jf config remove repox > /dev/null 2>&1 # Do not log if the repox config were not present

  echo "DEBUG: Adding JFrog config..."
  if ! jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_DEPLOY_ACCESS_TOKEN"; then
    echo "ERROR: Failed to add JFrog config" >&2
    exit 1
  fi

  echo "DEBUG: Configuring NPM repositories..."
  if ! jf npm-config --repo-resolve "npm" --repo-deploy "$ARTIFACTORY_DEPLOY_REPO"; then
    echo "ERROR: Failed to configure NPM repositories" >&2
    exit 1
  fi

  echo "DEBUG: Publishing NPM package..."
  if ! jf npm publish --build-name="$PROJECT" --build-number="$BUILD_NUMBER"; then
    echo "ERROR: Failed to publish NPM package" >&2
    exit 1
  fi

  jf rt build-collect-env "$PROJECT" "$BUILD_NUMBER"

  echo "DEBUG: Publishing build info..."
  local build_publish_output
  if ! build_publish_output=$(jf rt build-publish "$PROJECT" "$BUILD_NUMBER"); then
    echo "ERROR: Failed to publish build info" >&2
    exit 1
  fi

  echo "DEBUG: Build publish output: ${build_publish_output}"

  # Extract build info URL
  local build_info_url
  build_info_url=$(echo "$build_publish_output" | jq -r '.buildInfoUiUrl // empty')
  if [ -n "$build_info_url" ]; then
    echo "build-info-url=$build_info_url" >> "$GITHUB_OUTPUT"
    echo "DEBUG: Build info URL saved: $build_info_url"
  fi

  echo "DEBUG: JFrog operations completed successfully"
}

# Complete build pipeline with optional steps
# Usage: run_standard_pipeline <enable_sonar> <enable_deploy> [sonar_args...]
run_standard_pipeline() {
  local enable_sonar="${1:-true}"
  local enable_deploy="${2:-true}"
  shift 2  # Remove first two parameters
  local sonar_args=("$@")  # Remaining parameters are sonar args

  echo "Installing npm dependencies..."
  npm ci

  if [ "$SKIP_TESTS" != "true" ]; then
    echo "Running tests..."
    npm test
  else
    echo "Skipping tests (SKIP_TESTS=true)"
  fi

  if [ "${enable_sonar}" = "true" ]; then
    run_sonar_scanner "${sonar_args[@]}"
  fi

  echo "Building project..."
  npm run build

  if [ "${enable_deploy}" = "true" ]; then
    jfrog_npm_publish
  fi
}

build_npm() {
  echo "=== NPM Build, Deploy, and Analyze ==="
  echo "Branch: ${GITHUB_REF_NAME}"
  echo "Pull Request: ${PULL_REQUEST}"
  echo "Deploy Pull Request: ${DEPLOY_PULL_REQUEST}"
  echo "Skip Tests: ${SKIP_TESTS}"

  set_project_version

  local enable_sonar enable_deploy
  local sonar_args=()

  if is_default_branch && ! is_pull_request; then
    echo "======= Building main branch ======="
    echo "Current version: ${CURRENT_VERSION}"
    check_version_format "${PROJECT_VERSION}"
    echo "Checked version format: ${PROJECT_VERSION}."

    enable_sonar=true
    enable_deploy=true
    sonar_args=("-Dsonar.projectVersion=${CURRENT_VERSION}")

  elif is_maintenance_branch && ! is_pull_request; then
    echo "======= Building maintenance branch ======="

    if [[ ${CURRENT_VERSION} =~ "-SNAPSHOT" ]]; then
      echo "======= Found SNAPSHOT version ======="
      echo "Set npm version with build ID: ${BUILD_NUMBER}."
      check_version_format "${PROJECT_VERSION}"
    else
      echo "======= Found RELEASE version ======="
      echo "======= Deploy ${CURRENT_VERSION} ======="
      check_version_format "${CURRENT_VERSION}"
    fi

    enable_sonar=true
    enable_deploy=true
    sonar_args=("-Dsonar.branch.name=${GITHUB_REF_NAME}")

  elif is_pull_request; then
    echo "======= Building pull request ======="

    enable_sonar=true
    sonar_args=("-Dsonar.analysis.prNumber=${PULL_REQUEST}")

    if [ "${DEPLOY_PULL_REQUEST:-false}" == "true" ]; then
      echo "======= with deploy ======="
      check_version_format "${PROJECT_VERSION}"
      enable_deploy=true
    else
      echo "======= no deploy ======="
      enable_deploy=false
    fi

  elif is_dogfood_branch && ! is_pull_request; then
    echo "======= Build dogfood branch ======="
    check_version_format "${PROJECT_VERSION}"
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

  run_standard_pipeline "$enable_sonar" "$enable_deploy" "${sonar_args[@]+"${sonar_args[@]}"}"

  echo "=== Build completed successfully ==="
}

main() {
  check_tool jq --version
  check_tool jf --version
  check_tool npm --version
  set_build_env
  build_npm
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
