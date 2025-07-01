#!/bin/bash
# Regular way to promote a generic project: JFrog promotion, and GitHub notification.
# Environment variables:
# - ARTIFACTORY_URL: Repox URL
# - ARTIFACTORY_PYPI_REPO: repository to install dependencies from (sonarsource-pypi)
# - ARTIFACTORY_ACCESS_TOKEN: access token to access the repository
# - ARTIFACTORY_DEPLOY_REPO: deployment repository (sonarsource-pypi-public-qa or sonarsource-pypi-private-qa)
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: access token to deploy to the repository
# - GITHUB_REF_NAME: The short ref name of the branch or tag (e.g. main, branch-123, dogfood-on-123)
# - DEFAULT_BRANCH: default branch (e.g. main)
# - BUILD_NUMBER: build number (e.g. 42)
# - GITHUB_REPOSITORY: repository name (e.g. sonarsource/sonar-dummy-poetry)
# - GITHUB_EVENT_NAME: event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: The path to the event webhook payload file. For example, /github/workflow/event.json.
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${GITHUB_REF_NAME:?}" "${DEFAULT_BRANCH?}" "${BUILD_NUMBER?}" "${PROJECT?}"
: "${ARTIFACTORY_URL:?}"
: "${ARTIFACTORY_PROMOTE_ACCESS_TOKEN:?}"
: "${PROJECT:?}"
: "${BUILD_NUMBER:?}"

: "${MULTI_REPO_PROMOTE:=false}"
: "${GITHUB_REF_NAME:?}"
DEFAULT_BRANCH_PATTERN="^${DEFAULT_BRANCH:-"main$|^master"}$"

fetch_git_history() {
  git fetch --unshallow || true
}

fetch_pr_references() {
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

is_main_branch() {
  [[ "${GITHUB_REF_NAME}" =~ $DEFAULT_BRANCH_PATTERN ]]
}

is_maintenance_branch() {
  [[ "${GITHUB_REF_NAME}" == "branch-"* ]]
}

is_pull_request() {
  [[ "${PULL_REQUEST:-false}" != "false" ]]
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
#source "$(dirname "$0")"/includes/git_utils

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

jfrog_poetry_install() {
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf poetry-config --server-id-resolve repox --repo-resolve "$ARTIFACTORY_PYPI_REPO"
  jf poetry install --build-name="$PROJECT" --build-number="$BUILD_NUMBER"
}

jfrog_promote() {
  if is_pull_request; then
    STATUS='it-passed-pr'
  else
    STATUS='it-passed'
  fi
  
  jfrog config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_PROMOTE_ACCESS_TOKEN"
  
  if is_merge_queue_branch; then
    echo "Github merge queue detected: promotion skipped."
    exit 0
  elif [[ "${MULTI_REPO_PROMOTE}" == "true" ]]; then
    promote_multi
  else
    promote
  fi
}

get_deploy_repo() {
  buildInfo=$(jfrog rt curl "api/build/$PROJECT/$BUILD_NUMBER")
  if type jq &>/dev/null; then
    ARTIFACTORY_DEPLOY_REPO=$(jq -r '.buildInfo.properties."buildInfo.env.ARTIFACTORY_DEPLOY_REPO"' <<<"$buildInfo")
    if [[ "$ARTIFACTORY_DEPLOY_REPO" == "null" ]]; then
      echo "Failed to retrieve ARTIFACTORY_DEPLOY_REPO from buildInfo for build ${PROJECT}/${BUILD_NUMBER}" >&2
      jq -r '.errors' <<<"$buildInfo" >&2
      exit 1
    fi
  else
    if ! ARTIFACTORY_DEPLOY_REPO=$(grep buildInfo.env.ARTIFACTORY_DEPLOY_REPO <<<"$buildInfo" | cut -d\" -f4); then
      echo "Failed to retrieve ARTIFACTORY_DEPLOY_REPO from buildInfo for build ${PROJECT}/${BUILD_NUMBER}" >&2
      grep -A3 errors <<<"$buildInfo" >&2
      exit 1
    fi
  fi
  echo "Retrieved ARTIFACTORY_DEPLOY_REPO=$ARTIFACTORY_DEPLOY_REPO from buildInfo."
}

get_target_repo() {
  if is_pull_request; then
    ARTIFACTORY_TARGET=${ARTIFACTORY_DEPLOY_REPO/%qa/dev}
  elif is_main_branch || is_maintenance_branch; then
    ARTIFACTORY_TARGET=${ARTIFACTORY_DEPLOY_REPO/%qa/builds}
  elif is_dogfood_branch; then
    ARTIFACTORY_TARGET=sonarsource-dogfood-builds
  else
    echo "Promotion is not available from a working branch (not a pull request, nor a maintenance or dogfood branch)" >&2
    exit 1
  fi
}

promote() {
  if [[ -z ${ARTIFACTORY_TARGET:-} ]]; then
    if [[ -z ${ARTIFACTORY_DEPLOY_REPO:-} ]]; then
      get_deploy_repo
    fi
    get_target_repo
  fi
  echo "Promote $PROJECT/$BUILD_NUMBER build artifacts to $ARTIFACTORY_TARGET"
  jfrog rt bpr --status "$STATUS" "$PROJECT" "$BUILD_NUMBER" "$ARTIFACTORY_TARGET"
}

get_target_repos() {
  if is_pull_request; then
    targetRepo1="sonarsource-private-dev"
    targetRepo2="sonarsource-public-dev"
  elif is_main_branch || is_maintenance_branch; then
    targetRepo1="sonarsource-private-builds"
    targetRepo2="sonarsource-public-builds"
  elif is_dogfood_branch; then
    targetRepo1="sonarsource-dogfood-builds"
    targetRepo2="sonarsource-dogfood-builds"
  else
    echo "Promotion is not available from a working branch (not a pull request, nor a maintenance or dogfood branch)" >&2
    exit 1
  fi
}

promote_multi() {
  local src1=sonarsource-private-qa src2=sonarsource-public-qa targetRepo1 targetRepo2
  get_target_repos
  echo "Promote $PROJECT/$BUILD_NUMBER build artifacts to $targetRepo1 and $targetRepo2"
  jfrog rt curl "api/plugins/execute/multiRepoPromote?params=buildName=$PROJECT;buildNumber=$BUILD_NUMBER;src1=$src1;target1=$targetRepo1;src2=$src2;target2=$targetRepo2;status=$STATUS"
}

main() {
#  check_tool python --version
#  check_tool poetry --version
  check_tool jf --version
  set_build_env
  set_project_version
  jfrog_poetry_install # install or config only?

  echo ">> Promote build"
  set +o verbose
  source github-env PROMOTE
  set +o verbose
  jfrog config remove repox
  jfrog_promote
  if [[ -v GITHUB_TOKEN ]]; then
    github-notify-promotion
  else
    echo "GITHUB_TOKEN unset: skipping build number commit status on GitHub"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
