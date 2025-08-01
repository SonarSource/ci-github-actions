#!/bin/bash
# Build script for SonarSource Yarn projects.
# Supports building, testing, SonarQube analysis, and JFrog Artifactory deployment.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_HOST_URL: URL of SonarQube server
# - SONAR_TOKEN: Access token to send analysis reports to SonarQube
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to access the repository
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
#
# Auto-derived by script:
# - PROJECT: Project name derived from GITHUB_REPOSITORY
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:?}"
: "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"
: "${DEPLOY_PULL_REQUEST:=false}" "${SKIP_TESTS:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST SKIP_TESTS

check_tool() {
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

  # Validate required files exist
  if [ ! -f "package.json" ]; then
    echo "ERROR: package.json file not found in current directory." >&2
    exit 1
  fi

  if [ ! -f "yarn.lock" ]; then
    echo "ERROR: yarn.lock file not found. This is required for yarn --immutable installs." >&2
    exit 1
  fi

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

PACKAGE_JSON="package.json"

set_project_version() {
  local current_version release_version digit_count

  current_version=$(jq -r .version "$PACKAGE_JSON")
  if [ -z "${current_version}" ] || [ "${current_version}" == "null" ]; then
    echo "Could not get version from ${PACKAGE_JSON}" >&2
    exit 1
  fi

  export CURRENT_VERSION="${current_version}"

  # Calculate version with build ID for all branch types
  release_version="${current_version%"-SNAPSHOT"}"

  # Handle version digits: add missing .0 or .0.0, and fail for more than 3 digits
  digit_count=$(echo "${release_version//./ }" | wc -w)
  if [[ "$digit_count" -eq 1 ]]; then
    release_version="${release_version}.0.0"
  elif [[ "$digit_count" -eq 2 ]]; then
    release_version="${release_version}.0"
  elif [[ "$digit_count" -ne 3 ]]; then
    echo "ERROR: Unsupported version '$current_version' with $digit_count digits. Expected 1-3 digits (e.g., '1', '1.2', or '1.2.3')." >&2
    return 1
  fi
  PROJECT_VERSION="${release_version}-${BUILD_NUMBER}"

  export PROJECT_VERSION
  echo "project-version=${PROJECT_VERSION}" >> "${GITHUB_OUTPUT}"
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

jfrog_yarn_publish() {
  if [ -z "${ARTIFACTORY_URL:-}" ] || [ -z "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:-}" ]; then
    echo "ERROR: Deployment requires ARTIFACTORY_URL and ARTIFACTORY_DEPLOY_ACCESS_TOKEN to be set" >&2
    exit 1
  fi

  echo "::debug::Removing existing JFrog config..."
  jf config remove repox > /dev/null 2>&1 || true # Do not log if the repox config were not present

  echo "::debug::Adding JFrog config..."
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_DEPLOY_ACCESS_TOKEN"

  echo "::debug::Configuring Yarn repositories..."
  jf npm-config --repo-resolve "npm" --repo-deploy "$ARTIFACTORY_DEPLOY_REPO"

  echo "::debug::Publishing Yarn package..."
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

  echo "::debug::JFrog operations completed successfully"
}

# Determine build configuration based on branch type
get_build_config() {
  local enable_sonar enable_deploy
  local sonar_args=()

  if is_default_branch && ! is_pull_request; then
    echo "======= Building main branch ======="
    echo "Current version: ${CURRENT_VERSION}"
    echo "Checked version format: ${PROJECT_VERSION}."

    enable_sonar=true
    enable_deploy=true
    sonar_args=("-Dsonar.projectVersion=${CURRENT_VERSION}")

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

  # Export the configuration for use by run_standard_pipeline
  export BUILD_ENABLE_SONAR="$enable_sonar"
  export BUILD_ENABLE_DEPLOY="$enable_deploy"
  export BUILD_SONAR_ARGS="${sonar_args[*]:-}"
}

# Complete build pipeline with optional steps
run_standard_pipeline() {
  echo "Installing yarn dependencies..."
  yarn install --immutable

  echo "Setting project version to ${PROJECT_VERSION}..."
  npm version --no-git-tag-version --allow-same-version "${PROJECT_VERSION}"

  if [ "$SKIP_TESTS" != "true" ]; then
    echo "Running tests..."
    yarn test
  else
    echo "Skipping tests (SKIP_TESTS=true)"
  fi

  if [ "${BUILD_ENABLE_SONAR}" = "true" ]; then
    read -ra sonar_args <<< "$BUILD_SONAR_ARGS"
    run_sonar_scanner "${sonar_args[@]}"
  fi

  echo "Building project..."
  yarn build

  if [ "${BUILD_ENABLE_DEPLOY}" = "true" ]; then
    jfrog_yarn_publish
  fi
}

build_yarn() {
  echo "=== Yarn Build, Deploy, and Analyze ==="
  echo "Branch: ${GITHUB_REF_NAME}"
  echo "Pull Request: ${PULL_REQUEST}"
  echo "Deploy Pull Request: ${DEPLOY_PULL_REQUEST}"
  echo "Skip Tests: ${SKIP_TESTS}"

  set_project_version
  get_build_config
  run_standard_pipeline

  echo "=== Build completed successfully ==="
}

main() {
  check_tool jq --version
  check_tool jf --version
  check_tool yarn --version
  set_build_env
  build_yarn
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
