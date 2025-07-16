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

: "${GITHUB_REF_NAME:?Required environment variable not set}"
: "${BUILD_NUMBER:?Required environment variable not set}"
: "${GITHUB_RUN_ID:?Required environment variable not set}"
: "${GITHUB_SHA:?Required environment variable not set}"
: "${GITHUB_REPOSITORY:?Required environment variable not set}"


command_exists() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

set_build_env() {
  export PROJECT=${GITHUB_REPOSITORY#*/}
  echo "PROJECT: $PROJECT"

  if [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
    PULL_REQUEST=$(jq --raw-output .number "$GITHUB_EVENT_PATH")
    PULL_REQUEST_SHA=$(jq --raw-output .pull_request.base.sha "$GITHUB_EVENT_PATH")
  else
    PULL_REQUEST=false
  fi
  echo "PULL_REQUEST: $PULL_REQUEST"
  export PULL_REQUEST PULL_REQUEST_SHA

  # Set default values
  : "${DEPLOY_PULL_REQUEST:=false}"
  : "${SKIP_TESTS:=false}"
  : "${GRADLE_ARGS:=}"

  echo "Fetching commit history for SonarQube analysis..."
  git fetch --unshallow || true

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    echo "Fetching base branch: $GITHUB_BASE_REF"
    git fetch origin "${GITHUB_BASE_REF}"
  fi
}

set_project_version() {
  # Get project version from gradle.properties
  if [[ -f "gradle.properties" ]]; then
    INITIAL_VERSION=$(grep ^version gradle.properties | awk -F= '{print $2}')
    export INITIAL_VERSION
    echo "Retrieved INITIAL_VERSION=$INITIAL_VERSION from gradle.properties"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "project-version=$INITIAL_VERSION" >> "$GITHUB_OUTPUT"
      echo "build-number=${BUILD_NUMBER}" >> "$GITHUB_OUTPUT"
    fi
  else
    echo "gradle.properties not found, version information may be unavailable"
  fi
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
  local pull_request="${PULL_REQUEST:-false}"

  if [[ "$pull_request" != "false" ]]; then
    # For pull requests, deploy only if explicitly enabled
    [[ "$DEPLOY_PULL_REQUEST" == "true" ]]
  else
    [[ "$GITHUB_REF_NAME" == "master" ]] || \
    [[ "$GITHUB_REF_NAME" == branch-* ]] || \
    [[ "$GITHUB_REF_NAME" == dogfood-on-* ]] || \
    [[ "$GITHUB_REF_NAME" == feature/long/* ]]
  fi
}

set_sonar_args() {
  local -n args_ref=$1
  local pull_request="${PULL_REQUEST:-false}"

  if [[ -z "${SONAR_HOST_URL:-}" || -z "${SONAR_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ "$GITHUB_REF_NAME" == "master" && "$pull_request" == "false" ]]; then
    # Master branch analysis
    args_ref+=("-Dsonar.projectVersion=$INITIAL_VERSION")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

  elif [[ "$GITHUB_REF_NAME" == branch-* && "$pull_request" == "false" ]]; then
    # Maintenance branch analysis
    args_ref+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
    args_ref+=("-Dsonar.projectVersion=$INITIAL_VERSION")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")

  elif [[ "$pull_request" != "false" ]]; then
    # Pull request analysis
    args_ref+=("-Dsonar.analysis.sha1=$PULL_REQUEST_SHA")
    args_ref+=("-Dsonar.analysis.prNumber=$PULL_REQUEST")

  elif [[ "$GITHUB_REF_NAME" == feature/long/* && "$pull_request" == "false" ]]; then
    # Long-lived feature branch analysis
    args_ref+=("-Dsonar.branch.name=$GITHUB_REF_NAME")
    args_ref+=("-Dsonar.analysis.sha1=$GITHUB_SHA")
  fi
}

gradle_build() {
  # Setup Gradle
  if command_exists gradle; then
    GRADLE_CMD="gradle"
  elif [[ -f "./gradlew" ]]; then
    GRADLE_CMD="./gradlew"
    chmod +x ./gradlew
  else
    echo "Neither gradle nor gradlew found" >&2
    return 1
  fi

  echo "Using Gradle command: $GRADLE_CMD"
  export GRADLE_CMD

  # Conditional validation for SonarQube
  if [[ -n "${SONAR_HOST_URL:-}" && -z "${SONAR_TOKEN:-}" ]]; then
    echo "SONAR_TOKEN is required when SONAR_HOST_URL is set" >&2
    return 1
  fi

  # Conditional validation for Artifactory
  if [[ -n "${ARTIFACTORY_DEPLOY_REPO:-}" && ( -z "${ARTIFACTORY_DEPLOY_USERNAME:-}" || -z "${ARTIFACTORY_DEPLOY_PASSWORD:-}" ) ]]; then
    echo "ARTIFACTORY_DEPLOY_USERNAME and ARTIFACTORY_DEPLOY_PASSWORD are required when ARTIFACTORY_DEPLOY_REPO is set" >&2
    return 1
  fi

  local gradle_args
  read -ra gradle_args <<< "$(build_gradle_args)"

  set_sonar_args gradle_args

  local build_type
  local pull_request="${PULL_REQUEST:-false}"

  if [[ "$GITHUB_REF_NAME" == "master" && "$pull_request" == "false" ]]; then
    build_type="master branch"
  elif [[ "$GITHUB_REF_NAME" == branch-* && "$pull_request" == "false" ]]; then
    build_type="maintenance branch"
  elif [[ "$pull_request" != "false" ]]; then
    build_type="pull request"
  elif [[ "$GITHUB_REF_NAME" == dogfood-on-* && "$pull_request" == "false" ]]; then
    build_type="dogfood branch"
  elif [[ "$GITHUB_REF_NAME" == feature/long/* && "$pull_request" == "false" ]]; then
    build_type="long-lived feature branch"
  else
    build_type="regular build"
  fi

  echo "Starting $build_type build..."
  echo "Gradle command: $GRADLE_CMD ${gradle_args[*]}"

  if "$GRADLE_CMD" "${gradle_args[@]}"; then
    echo "Build completed successfully"
    return 0
  else
    echo "Build failed" >&2
    return 1
  fi
}

main() {
  command_exists java -version
  if command_exists gradle; then
    command_exists gradle --version
  fi
  set_build_env
  set_project_version
  gradle_build
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
