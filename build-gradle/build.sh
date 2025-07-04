#!/bin/bash
# Regular way to build, analyze, and deploy a SonarSource Gradle project.
# Environment variables:
# - ARTIFACTORY_URL: Repox URL
# - ARTIFACTORY_MAVEN_REPO: repository to install dependencies from
# - ARTIFACTORY_ACCESS_TOKEN: access token to access the repository
# - ARTIFACTORY_DEPLOY_REPO: deployment repository
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: access token to deploy to the repository
# - SONAR_HOST_URL: URL of Sonar server
# - SONAR_TOKEN: access token to send analysis reports to SONAR_HOST_URL
# - GITHUB_REF_NAME: The short ref name of the branch or tag (e.g. main, branch-123, dogfood-on-123)
# - DEFAULT_BRANCH: default branch (e.g. main)
# - BUILD_NUMBER: build number (e.g. 42)
# - GITHUB_REPOSITORY: repository name (e.g. sonarsource/sonar-dummy-gradle)
# - GITHUB_EVENT_NAME: event name (e.g. push, pull_request)
# - GITHUB_EVENT_PATH: The path to the event webhook payload file. For example, /github/workflow/event.json.
# Artifact signing using https://docs.gradle.org/current/userguide/signing_plugin.html
# - ORG_GRADLE_PROJECT_signingKey: OpenPGP key for signing artifacts
# - ORG_GRADLE_PROJECT_signingPassword: passphrase of the signingKey
# - ORG_GRADLE_PROJECT_signingKeyId: OpenPGP subkey id
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:="https://repox.jfrog.io/artifactory"}"
: "${ARTIFACTORY_MAVEN_REPO:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${DEFAULT_BRANCH:?}" "${BUILD_NUMBER:?}" "${GITHUB_REPOSITORY:?}"
: "${GITHUB_EVENT_NAME:?}" "${GITHUB_EVENT_PATH:?}"

check_tool() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

# Similar to source github-env <BUILD|BUILD-PRIVATE>
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
  # Get initial version from gradle.properties
  INITIAL_VERSION=$(grep ^version gradle.properties| awk -F= '{print $2}')
  export INITIAL_VERSION
  echo "Retrieved INITIAL_VERSION=$INITIAL_VERSION from gradle.properties"
}

configure_gradle() {
  # Setup Gradle with JFrog CLI
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf gradle-config --server-id-resolve repox --repo-resolve "$ARTIFACTORY_MAVEN_REPO" \
    --server-id-deploy repox --repo-deploy "$ARTIFACTORY_DEPLOY_REPO"
}

run_gradle_build() {
  # Fetch all commit history for Sonar blame information
  git fetch --unshallow || true
  
  # Fetch references from github for PR analysis
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    git fetch origin "${GITHUB_BASE_REF}"
  fi

  # Use gradlew if available, otherwise use gradle
  command -v gradle &> /dev/null || alias gradle=./gradlew

  if [ "${GITHUB_REF_NAME}" == "$DEFAULT_BRANCH" ] && [ "$PULL_REQUEST" == "false" ]; then
    echo '======= Build, deploy and analyze master'
    
    jf gradle --no-daemon --info --stacktrace --console plain \
      build sonar artifactoryPublish \
      -DbuildNumber="$BUILD_NUMBER" \
      -Dsonar.host.url="$SONAR_HOST_URL" \
      -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.projectVersion="$INITIAL_VERSION" \
      -Dsonar.analysis.buildNumber="$BUILD_NUMBER" \
      -Dsonar.analysis.pipeline="$GITHUB_RUN_ID" \
      -Dsonar.analysis.sha1="$GITHUB_SHA" \
      -Dsonar.analysis.repository="$GITHUB_REPOSITORY" \
      --build-name="$PROJECT" --build-number="$BUILD_NUMBER" \
      "$@"
      
  elif [[ "${GITHUB_REF_NAME}" == "branch-"* ]] && [ "$PULL_REQUEST" == "false" ]; then
    echo '======= Build, deploy and analyze maintenance branch'
    
    jf gradle --no-daemon --info --stacktrace --console plain \
      build sonar artifactoryPublish \
      -DbuildNumber="$BUILD_NUMBER" \
      -Dsonar.host.url="$SONAR_HOST_URL" \
      -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.branch.name="$GITHUB_REF_NAME" \
      -Dsonar.projectVersion="$INITIAL_VERSION" \
      -Dsonar.analysis.buildNumber="$BUILD_NUMBER" \
      -Dsonar.analysis.pipeline="$GITHUB_RUN_ID" \
      -Dsonar.analysis.sha1="$GITHUB_SHA" \
      -Dsonar.analysis.repository="$GITHUB_REPOSITORY" \
      --build-name="$PROJECT" --build-number="$BUILD_NUMBER" \
      "$@"
      
  elif [ "$PULL_REQUEST" != "false" ]; then
    echo '======= Build and analyze pull request'
    
    if [ "${DEPLOY_PULL_REQUEST:-}" == "true" ]; then
      jf gradle --no-daemon --info --stacktrace --console plain \
        build sonar artifactoryPublish \
        -DbuildNumber="$BUILD_NUMBER" \
        -Dsonar.host.url="$SONAR_HOST_URL" \
        -Dsonar.token="$SONAR_TOKEN" \
        -Dsonar.analysis.buildNumber="$BUILD_NUMBER" \
        -Dsonar.analysis.pipeline="$GITHUB_RUN_ID" \
        -Dsonar.analysis.sha1="$PULL_REQUEST_SHA" \
        -Dsonar.analysis.repository="$GITHUB_REPOSITORY" \
        -Dsonar.analysis.prNumber="$PULL_REQUEST" \
        --build-name="$PROJECT" --build-number="$BUILD_NUMBER" \
        "$@"
    else
      gradle --no-daemon --info --stacktrace --console plain \
        build sonar \
        -DbuildNumber="$BUILD_NUMBER" \
        -Dsonar.host.url="$SONAR_HOST_URL" \
        -Dsonar.token="$SONAR_TOKEN" \
        -Dsonar.analysis.buildNumber="$BUILD_NUMBER" \
        -Dsonar.analysis.pipeline="$GITHUB_RUN_ID" \
        -Dsonar.analysis.sha1="$PULL_REQUEST_SHA" \
        -Dsonar.analysis.repository="$GITHUB_REPOSITORY" \
        -Dsonar.analysis.prNumber="$PULL_REQUEST" \
        "$@"
    fi
    
  elif [[ "$GITHUB_REF_NAME" == "dogfood-on-"* ]] && [ "$PULL_REQUEST" == "false" ]; then
    echo '======= Build and deploy dogfood branch'
    
    jf gradle --no-daemon --info --stacktrace --console plain \
      build artifactoryPublish -DbuildNumber="$BUILD_NUMBER" \
      --build-name="$PROJECT" --build-number="$BUILD_NUMBER" \
      "$@"
      
  elif [[ "$GITHUB_REF_NAME" == "feature/long/"* ]] && [ "$PULL_REQUEST" == "false" ]; then
    echo '======= Build and analyze long lived feature branch'
    
    gradle --no-daemon --info --stacktrace --console plain \
      build sonar \
      -DbuildNumber="$BUILD_NUMBER" \
      -Dsonar.host.url="$SONAR_HOST_URL" \
      -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.branch.name="$GITHUB_REF_NAME" \
      -Dsonar.analysis.buildNumber="$BUILD_NUMBER" \
      -Dsonar.analysis.pipeline="$GITHUB_RUN_ID" \
      -Dsonar.analysis.sha1="$GITHUB_SHA" \
      -Dsonar.analysis.repository="$GITHUB_REPOSITORY" \
      "$@"
      
  else
    echo '======= Build, no analysis, no deploy'
    
    gradle --no-daemon --info --stacktrace --console plain build "$@"
  fi
}

main() {
  check_tool java -version
  check_tool jf --version
  set_build_env
  set_project_version
  configure_gradle
  run_gradle_build "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi