#!/bin/bash
# Build script for SonarSource Poetry projects.
# Supports building, testing, and JFrog Artifactory deployment.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
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
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-poetry)
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: Path to the event webhook payload file
# - GITHUB_ENV: Path to GitHub Actions environment file
# - GITHUB_OUTPUT: Path to GitHub Actions output file
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
: "${GITHUB_ENV:?}" "${GITHUB_OUTPUT:?}"
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

# FIXME BUILD-8337? this is similar to source github-env <BUILD|BUILD-PRIVATE>
set_build_env() {
  DEFAULT_BRANCH=${DEFAULT_BRANCH:=$(gh repo view --json defaultBranchRef --jq ".defaultBranchRef.name")}
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"
  echo "PULL_REQUEST: $PULL_REQUEST"
  export DEFAULT_BRANCH PULL_REQUEST PULL_REQUEST_SHA
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

# is_long_lived_feature_branch() {
#   [[ "${GITHUB_REF_NAME}" == "feature/long/"* ]]
# }

set_project_version() {
  if ! current_version=$(poetry version -s); then
    echo "Could not get version from Poetry project ('poetry version -s')" >&2
    echo "$current_version" >&2
    return 1
  fi
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
  check_tool jq --version
  check_tool python --version
  check_tool poetry --version
  check_tool jf --version
  set_build_env
  set_project_version
  jfrog_poetry_install
  poetry build
  if (is_pull_request && [[ "${DEPLOY_PULL_REQUEST:-}" == "true" ]]) || \
     (! is_pull_request && (is_default_branch || is_maintenance_branch || is_dogfood_branch)); then
    jfrog_poetry_publish
  fi

  # run scanner?
  #if is_main_branch && ! is_pull_request; then
  #  run_sonar_scanner \
  #  -Dsonar.projectVersion="$CURRENT_VERSION"
  #elif is_maintenance_branch && ! is_pull_request; then
  #  run_sonar_scanner \
  #  -Dsonar.branch.name="$GITHUB_REF_NAME"
  #elif is_pull_request; then
  #  run_sonar_scanner \
  #  -Dsonar.analysis.prNumber="$PULL_REQUEST"
  #elif is_long_lived_feature_branch && ! is_pull_request; then
  #  run_sonar_scanner \
  #  -Dsonar.branch.name="$GITHUB_REF_NAME"

  # run_sonar_scanner
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_poetry
fi
