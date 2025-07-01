#!/bin/bash
# Regular way to build and deploy a SonarSource Poetry project.
# Environment variables:
# - ARTIFACTORY_URL: Repox URL.
# - ARTIFACTORY_PYPI_REPO: Repository to install dependencies from (sonarsource-pypi)
# - ARTIFACTORY_ACCESS_TOKEN: Access token to access the repository
# - ARTIFACTORY_DEPLOY_REPO: Deployment repository (sonarsource-pypi-public-qa or sonarsource-pypi-private-qa)
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to the repository
# - GITHUB_REF_NAME: Short ref name of the branch or tag (e.g. main, branch-123, dogfood-on-123)
# - DEFAULT_BRANCH: Default branch (e.g. main), defaults to the repository configuration
# - BUILD_NUMBER: Build number (e.g. 42)
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-poetry)
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: Path to the event webhook payload file. For example, /github/workflow/event.json.
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:="https://repox.jfrog.io/artifactory"}"
: "${ARTIFACTORY_PYPI_REPO:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_EVENT_PATH:?}"
: "${GITHUB_ENV:?}" # "${GITHUB_OUTPUT:?}"

check_tool() {
  # Check if a command is available and runs it, typically: 'some_tool --version'
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

  if [[ "$GITHUB_EVENT_NAME" = "pull_request" ]]; then
    PULL_REQUEST=$(jq --raw-output .number "$GITHUB_EVENT_PATH")
    PULL_REQUEST_SHA=$(jq --raw-output .pull_request.base.sha "$GITHUB_EVENT_PATH")
  else
    PULL_REQUEST=false
  fi
  echo "PULL_REQUEST: $PULL_REQUEST"
  export DEFAULT_BRANCH PULL_REQUEST PULL_REQUEST_SHA
}

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
#  echo "PROJECT_VERSION=$PROJECT_VERSION" >> "$GITHUB_OUTPUT"
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
    --env-include 'PROJECT;GIT_*;*VERSION*;BUILD_*;GITHUB_*;*BRANCH*;*ID;PULL_REQUEST*' \
    --env-exclude "*login*;*pass*;*psw*;*pwd*;*secret*;*key*;*token*;*auth*" \
    --overwrite # avoid duplicate builds on re-runs
}

build-poetry() {
  check_tool jq --version
  check_tool python --version
  check_tool poetry --version
  check_tool jf --version
  set_build_env
  set_project_version
  jfrog_poetry_install
  poetry build
  if [[ -n "${PULL_REQUEST:-}" && "${DEPLOY_PULL_REQUEST:-}" == "true" ]] || \
     [[ -z "${PULL_REQUEST:-}" && ( "$GITHUB_REF_NAME" = "$DEFAULT_BRANCH" || "$GITHUB_REF_NAME" =~ ^branch- ||
                                    "$GITHUB_REF_NAME" =~ ^dogfood-on- ) ]]; then
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
  build-poetry
fi
