#!/bin/bash
# Build script for SonarSource Poetry projects.
# Supports building, testing, SonarQube analysis, and JFrog Artifactory deployment.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_HOST_URL: URL of SonarQube server
# - SONAR_TOKEN: Access token to send analysis reports to SonarQube
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_PYPI_REPO: Repository to install dependencies from
# - ARTIFACTORY_ACCESS_TOKEN: Access token to access the repository
# - ARTIFACTORY_DEPLOY_REPO: Deployment repository name
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to the repository
# - DEFAULT_BRANCH: Default branch name (e.g. main)
# - PULL_REQUEST: Pull request number (e.g. 1234) or empty string
# - PULL_REQUEST_SHA: Pull request base SHA or empty string
#
# GitHub Actions auto-provided:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-poetry)
# - GITHUB_RUN_ID: GitHub Actions run ID
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: Path to the event webhook payload file
# - GITHUB_ENV: Path to GitHub Actions environment file
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_BASE_REF: Base branch for pull requests (only during pull_request events)
#
# Optional user customization:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
#
# Auto-derived by script:
# - PROJECT: Project name derived from GITHUB_REPOSITORY
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:?}"
: "${ARTIFACTORY_PYPI_REPO:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_EVENT_PATH:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${GITHUB_ENV:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"
: "${DEPLOY_PULL_REQUEST:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST

# Check if a command is available and runs it, typically: 'some_tool --version'
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

run_sonar_scanner() {
    local additional_params=("$@")

    # Install pysonar into Poetry's virtual environment without modifying project files
    if ! poetry run pysonar --help >/dev/null 2>&1; then
        echo "Installing pysonar into Poetry virtual environment..."
        poetry run pip install pysonar
    fi

    poetry run pysonar \
        -Dsonar.host.url="${SONAR_HOST_URL}" \
        -Dsonar.token="${SONAR_TOKEN}" \
        -Dsonar.analysis.buildNumber="${BUILD_NUMBER}" \
        -Dsonar.analysis.pipeline="${GITHUB_RUN_ID}" \
        -Dsonar.analysis.sha1="${GITHUB_SHA}" \
        -Dsonar.analysis.repository="${GITHUB_REPOSITORY}" \
        "${additional_params[@]}"
    echo "SonarQube scanner finished"
}

# FIXME BUILD-8337? this is similar to source github-env <BUILD|BUILD-PRIVATE>
set_build_env() {
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"
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

set_project_version() {
  local current_version release_version digit_count

  if ! current_version=$(poetry version -s); then
    echo "Could not get version from Poetry project ('poetry version -s')" >&2
    echo "$current_version" >&2
    return 1
  fi

  export CURRENT_VERSION="${current_version}"

  release_version=${current_version%".dev"*}
  # In case of 2 digits, we need to add a '0' as the 3rd digit.
  digit_count=$(echo "${release_version//./ }" | wc -w)
  if [[ "$digit_count" -lt 3 ]]; then
    release_version="$release_version.0"
  fi
  if [[ "$digit_count" -gt 3 && $release_version =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    release_version="${BASH_REMATCH[0]}"
    echo "WARN: version was truncated to $release_version because it had more than 3 digits"
  fi
  new_version="$release_version.${BUILD_NUMBER}"

  echo "Replacing version $current_version with $new_version"
  poetry version "$new_version"
  export PROJECT_VERSION=$new_version
  echo "PROJECT_VERSION=$PROJECT_VERSION" >> "$GITHUB_ENV"
}

# Determine build configuration based on branch type
get_build_config() {
  local enable_sonar enable_deploy
  local sonar_args=()

  if is_default_branch && ! is_pull_request; then
    echo "======= Building main branch ======="
    echo "Current version: ${CURRENT_VERSION}"

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

  # Export the configuration for use by build_poetry
  export BUILD_ENABLE_SONAR="$enable_sonar"
  export BUILD_ENABLE_DEPLOY="$enable_deploy"
  export BUILD_SONAR_ARGS="${sonar_args[*]:-}"
}

jfrog_poetry_install() {
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf poetry-config --server-id-resolve repox --repo-resolve "$ARTIFACTORY_PYPI_REPO"
  jf poetry install --build-name="$PROJECT" --build-number="$BUILD_NUMBER"
}

jfrog_poetry_publish() {
  jf config remove repox
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
  project_name=$(poetry version | awk '{print $1}')
  pushd dist
  jf rt upload ./ "$ARTIFACTORY_DEPLOY_REPO/$project_name/$PROJECT_VERSION/" --module="$project_name:$PROJECT_VERSION" \
    --build-name="$PROJECT" --build-number="$BUILD_NUMBER"
  popd
  jf rt build-collect-env "$PROJECT" "$BUILD_NUMBER"
  jf rt build-publish "$PROJECT" "$BUILD_NUMBER" \
    --env-include 'PROJECT;GIT_*;*VERSION*;BUILD_*;GITHUB_*;*BRANCH*;*ID;PULL_REQUEST*;ARTIFACTORY*' \
    --env-exclude "*login*;*pass*;*psw*;*pwd*;*secret*;*key*;*token*;*auth*" \
    --overwrite # avoid duplicate builds on re-runs
}

build_poetry() {
  echo "=== Poetry Build, Deploy, and Analyze ==="
  echo "Branch: ${GITHUB_REF_NAME}"
  echo "Pull Request: ${PULL_REQUEST}"
  echo "Deploy Pull Request: ${DEPLOY_PULL_REQUEST}"

  set_project_version
  get_build_config

  echo "Installing dependencies..."
  jfrog_poetry_install

  echo "Building project..."
  poetry build

  if [ "${BUILD_ENABLE_SONAR}" = "true" ]; then
    read -ra sonar_args <<< "$BUILD_SONAR_ARGS"
    run_sonar_scanner "${sonar_args[@]}"
  fi

  if [ "${BUILD_ENABLE_DEPLOY}" = "true" ]; then
    jfrog_poetry_publish
  fi

  echo "=== Build completed successfully ==="
}

main() {
  check_tool jq --version
  check_tool python --version
  check_tool poetry --version
  check_tool jf --version

  set_build_env
  build_poetry
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
