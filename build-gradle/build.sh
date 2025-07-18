#!/bin/bash
# Build script for SonarSource Gradle projects.
# Supports building, testing, SonarQube analysis, and Artifactory deployment.
#
# Environment variables:
# - SONAR_HOST_URL: URL of SonarQube server
# - SONAR_TOKEN: access token to send analysis reports to SonarQube
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_DEPLOY_REPO: name of deployment repository
# - ARTIFACTORY_DEPLOY_USERNAME: login to deploy to Artifactory
# - ARTIFACTORY_DEPLOY_PASSWORD: password to deploy to Artifactory
# - ORG_GRADLE_PROJECT_signingKey: OpenPGP key for signing artifacts (private key content)
# - ORG_GRADLE_PROJECT_signingPassword: passphrase of the signing key
# - ORG_GRADLE_PROJECT_signingKeyId: OpenPGP subkey id
# - DEPLOY_PULL_REQUEST: whether to deploy pull request artifacts (default: false)
# - SKIP_TESTS: whether to skip running tests (default: false)
# - GRADLE_ARGS: additional arguments to pass to Gradle

set -euo pipefail

: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_SHA:?}" "${GITHUB_REPOSITORY:?}"
: "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_PASSWORD:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}" "${ORG_GRADLE_PROJECT_signingKey:?}" "${ORG_GRADLE_PROJECT_signingPassword:?}" "${ORG_GRADLE_PROJECT_signingKeyId:?}"
: "${DEPLOY_PULL_REQUEST:?}" "${SKIP_TESTS:?}"

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

  if is_pull_request; then
    PULL_REQUEST=$(jq --raw-output .number "$GITHUB_EVENT_PATH")
    PULL_REQUEST_SHA=$(jq --raw-output .pull_request.base.sha "$GITHUB_EVENT_PATH")
  else
    PULL_REQUEST=false
  fi

  echo "Fetching commit history for SonarQube analysis..."
  git fetch --unshallow || true

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    echo "Fetching base branch: $GITHUB_BASE_REF"
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

set_project_version() {
  current_version=$(gradle properties --no-scan | grep 'version:' | tr -d "[:space:]" | cut -d ":" -f 2)
  release_version="${current_version/-SNAPSHOT/}"
  if [[ "${release_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    release_version="${release_version}.0"
  fi
  release_version="${release_version}.${BUILD_NUMBER}"

  echo "Replacing version $current_version with $release_version"
  sed -i.bak "s/$current_version/$release_version/g" gradle.properties
  export PROJECT_VERSION=$release_version
  echo "project-version=$release_version" >> "$GITHUB_OUTPUT"
}

build_gradle_args() {
  local args=()

  # Base arguments
  args+=("--no-daemon" "--info" "--stacktrace" "--console" "plain")

  args+=("build")

  if [[ "$SKIP_TESTS" == "true" ]]; then
    args+=("-x" "test")
    echo "Skipping tests as requested"
  fi

  # SonarQube analysis
  if [[ -n "${SONAR_HOST_URL:-}" && -n "${SONAR_TOKEN:-}" ]]; then
    args+=("sonar")
    args+=("-Dsonar.host.url=$SONAR_HOST_URL")
    args+=("-Dsonar.token=$SONAR_TOKEN")
    args+=("-Dsonar.analysis.buildNumber=$BUILD_NUMBER")
    args+=("-Dsonar.analysis.pipeline=$GITHUB_RUN_ID")
    args+=("-Dsonar.analysis.repository=$GITHUB_REPOSITORY")
  fi

  # Artifactory deployment
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
  if is_pull_request; then
    # For pull requests, deploy only if explicitly enabled
    [[ "$DEPLOY_PULL_REQUEST" == "true" ]]
  else
    [[ "$GITHUB_REF_NAME" == "master" ]] || \
    [[ "$GITHUB_REF_NAME" == branch-* ]] || \
    [[ "$GITHUB_REF_NAME" == dogfood-on-* ]] || \
    [[ "$GITHUB_REF_NAME" == feature/long/* ]]
  fi
}

get_build_type() {
  if [[ "$GITHUB_REF_NAME" == "master" ]] && ! is_pull_request; then
    echo "master branch"
  elif [[ "$GITHUB_REF_NAME" == branch-* ]] && ! is_pull_request; then
    echo "maintenance branch"
  elif is_pull_request; then
    echo "pull request"
  elif [[ "$GITHUB_REF_NAME" == dogfood-on-* ]] && ! is_pull_request; then
    echo "dogfood branch"
  elif [[ "$GITHUB_REF_NAME" == feature/long/* ]] && ! is_pull_request; then
    echo "long-lived feature branch"
  else
    echo "regular build"
  fi
}

set_sonar_args() {
  local -n args_ref=$1

  if [[ -z "${SONAR_HOST_URL:-}" || -z "${SONAR_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ "$GITHUB_REF_NAME" == "master" ]] && ! is_pull_request; then
    # Master branch analysis
    args_ref+=("-Dsonar.projectVersion=$PROJECT_VERSION")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

  elif [[ "$GITHUB_REF_NAME" == branch-* ]] && ! is_pull_request; then
    # Maintenance branch analysis
    args_ref+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
    args_ref+=("-Dsonar.projectVersion=$PROJECT_VERSION")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

  elif is_pull_request; then
    # Pull request analysis
    args_ref+=("-Dsonar.analysis.sha1=$PULL_REQUEST_SHA")
    args_ref+=("-Dsonar.analysis.prNumber=$PULL_REQUEST")

  elif [[ "$GITHUB_REF_NAME" == feature/long/* ]] && ! is_pull_request; then
    # Long-lived feature branch analysis
    args_ref+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")
  fi
}

is_pull_request() {
  [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]
}

gradle_build() {
  # Setup Gradle
  if command_exists gradle; then
    GRADLE_CMD="gradle"
  elif [[ -f "./gradlew" ]]; then
    GRADLE_CMD="./gradlew"
  fi

  local gradle_args
  read -ra gradle_args <<< "$(build_gradle_args)"

  set_sonar_args gradle_args

  local build_type
  build_type=$(get_build_type)

  echo "Starting $build_type build..."
  echo "Gradle command: $GRADLE_CMD ${gradle_args[*]}"

  "$GRADLE_CMD" "${gradle_args[@]}"
}

main() {
  command_exists java -version
  command_exists gradle -version
  set_build_env
  set_project_version
  gradle_build
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
