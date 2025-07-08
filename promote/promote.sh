#!/bin/bash
# Regular way to promote a project build: JFrog Artifactory build promotion, and GitHub status check update
# Environment variables:
# - ARTIFACTORY_URL: Repox URL.
# - ARTIFACTORY_PROMOTE_ACCESS_TOKEN: Access token to promote builds
# - GITHUB_REF_NAME: Short ref name of the branch or tag (e.g. main, branch-123, dogfood-on-123)
# - DEFAULT_BRANCH: Default branch (e.g. main), defaults to the repository configuration
# - BUILD_NUMBER: Build number (e.g. 42)
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-poetry)
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: Path to the event webhook payload file. For example, /github/workflow/event.json.
# - MULTI_REPO_PROMOTE: If true, promotes to multiple repositories (default: false)
# - ARTIFACTORY_DEPLOY_REPO: Repository to deploy to. If not set, it will be retrieved from the build info.
# - ARTIFACTORY_TARGET: Target repository for the promotion. If not set, it will be determined based on the branch type.
# Required properties in the build info:
# - buildInfo.env.ARTIFACTORY_DEPLOY_REPO: Repository to deploy to (e.g. sonarsource-deploy-qa)
# - buildInfo.env.PROJECT_VERSION: Version of the project (e.g. 1.2.3)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:="https://repox.jfrog.io/artifactory"}"
: "${ARTIFACTORY_PROMOTE_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}" "${GITHUB_EVENT_PATH:?}" "${GITHUB_TOKEN:?}"
: "${GITHUB_SHA:?}"
GH_API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
BUILD_INFO_FILE=$(mktemp)
rm -f "$BUILD_INFO_FILE"

: "${MULTI_REPO_PROMOTE:=false}"
MULTI_REPO_SRC_PRIVATE=sonarsource-private-qa
MULTI_REPO_SRC_PUBLIC=sonarsource-public-qa

check_tool() {
  # Check if a command is available and runs it, typically: 'some_tool --version'
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

is_main_branch() {
  [[ "$GITHUB_REF_NAME" = "$DEFAULT_BRANCH" ]]
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

is_merge_queue_branch() {
  [[ "${GITHUB_REF_NAME}" == "gh-readonly-queue/"* ]]
}

set_build_env() {
  DEFAULT_BRANCH=${DEFAULT_BRANCH:=$(gh repo view --json defaultBranchRef --jq ".defaultBranchRef.name")}
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"
  export DEFAULT_BRANCH
}

check_branch() {
  if is_merge_queue_branch; then
    echo "Github merge queue detected: promotion skipped."
    exit 0
  fi
  if ! (is_pull_request || is_main_branch || is_maintenance_branch || is_dogfood_branch); then
    echo "Promotion is only available for pull requests, main branch, maintenance branches, or dogfood branches." >&2
    echo "Current branch: ${GITHUB_REF_NAME} (GITHUB_EVENT_NAME: ${GITHUB_EVENT_NAME})" >&2
    return 1
  fi
}

jfrog_config_repox() {
  jf config remove repox
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_PROMOTE_ACCESS_TOKEN"
}

get_target_repos() {
  # Set targetRepo1 and targetRepo2 based on the branch type for multi-promotion
  if is_pull_request; then
    targetRepo1="sonarsource-private-dev"
    targetRepo2="sonarsource-public-dev"
  elif is_main_branch || is_maintenance_branch; then
    targetRepo1="sonarsource-private-builds"
    targetRepo2="sonarsource-public-builds"
  elif is_dogfood_branch; then
    targetRepo1="sonarsource-dogfood-builds"
    targetRepo2="sonarsource-dogfood-builds"
  fi
}

get_build_info_property() {
  property="$1"
  if ! [[ -s "$BUILD_INFO_FILE" ]]; then
    jf rt curl "api/build/$PROJECT/$BUILD_NUMBER" > "$BUILD_INFO_FILE"
  fi
  property_value=$(jq -r ".buildInfo.properties.\"buildInfo.env.$property\"" "$BUILD_INFO_FILE")
  if [[ "$property_value" == "null" || -z "$property_value" ]]; then
    echo "Failed to retrieve $property from buildInfo for build ${PROJECT}/${BUILD_NUMBER}" >&2
    jq -r '.errors' "$BUILD_INFO_FILE" >&2
    return 1
  fi
  echo "$property_value"
}

get_target_repo() {
  # Set targetRepo based on the branch type and ARTIFACTORY_DEPLOY_REPO, if not already set
  if [[ -n ${ARTIFACTORY_TARGET:-} ]]; then
    targetRepo="$ARTIFACTORY_TARGET"
    return
  fi
  : "${ARTIFACTORY_DEPLOY_REPO:=$(get_build_info_property ARTIFACTORY_DEPLOY_REPO)}"
  echo "ARTIFACTORY_DEPLOY_REPO=$ARTIFACTORY_DEPLOY_REPO"
  if is_pull_request; then
    targetRepo=${ARTIFACTORY_DEPLOY_REPO/%qa/dev}
  elif is_main_branch || is_maintenance_branch; then
    targetRepo=${ARTIFACTORY_DEPLOY_REPO/%qa/builds}
  elif is_dogfood_branch; then
    targetRepo=sonarsource-dogfood-builds
  fi
}

promote_multi() {
  # Call to https://github.com/SonarSource/re-tooling/tree/main/artifactory-user-plugins/multiRepoPromote
  echo "Promote $PROJECT/$BUILD_NUMBER build artifacts to $targetRepo1 and $targetRepo2"
  local promoteUrl="api/plugins/execute/multiRepoPromote?"
  promoteUrl+="params=buildName=$PROJECT;buildNumber=$BUILD_NUMBER;status=$status"
  promoteUrl+=";src1=$MULTI_REPO_SRC_PRIVATE;target1=$targetRepo1"
  promoteUrl+=";src2=$MULTI_REPO_SRC_PUBLIC;target2=$targetRepo2"
  jf rt curl "$promoteUrl"
}

promote_mono() {
  # Promote JFrog Artifactory build
  echo "Promote $PROJECT/$BUILD_NUMBER build artifacts to $targetRepo"
  jf rt bpr --status "$status" "$PROJECT" "$BUILD_NUMBER" "$targetRepo"
}

github_notify_promotion() {
  local project_version longDescription shortDescription buildUrl githubApiUrl
  project_version=$(get_build_info_property PROJECT_VERSION)
  longDescription="Latest promoted build of '${project_version}' from branch '${GITHUB_REF_NAME}'"
  shortDescription=${longDescription:0:140} # required for GH API endpoint (max 140 chars)
  buildUrl="${ARTIFACTORY_URL}/ui/builds/${PROJECT}/${BUILD_NUMBER}/"
  githubApiUrl="https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}"
  gh api -X POST -H "$GH_API_VERSION_HEADER" "$githubApiUrl" -H "Content-Type: application/json" --input - <<EOF
{
  "state": "success",
  "target_url": "$buildUrl",
  "description": "$shortDescription",
  "context": "repox-${GITHUB_REF_NAME}"
}
EOF
}

jfrog_promote() {
  local status='it-passed'
  if is_pull_request; then
    status='it-passed-pr'
  fi
  if [[ "${MULTI_REPO_PROMOTE}" == "true" ]]; then
    local targetRepo1 targetRepo2
    get_target_repos
    promote_multi
  else
    local targetRepo
    get_target_repo
    promote_mono
  fi
}

promote() {
  check_tool gh --version
  check_tool jq --version
  check_tool jf --version
  set_build_env
  check_branch
  jfrog_config_repox
  jfrog_promote
  github_notify_promotion
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  promote
fi
