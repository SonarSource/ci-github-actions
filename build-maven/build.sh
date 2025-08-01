#!/bin/bash
# Build and deploy a Maven project.
# Supports building, testing, SonarQube analysis, and Maven deployment to Artifactory.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_HOST_URL: URL of SonarQube server
# - SONAR_TOKEN: Access token to send analysis reports to SonarQube
# - ARTIFACTORY_URL: Artifactory repository URL
# - ARTIFACTORY_DEPLOY_REPO: Deployment repository name
# - ARTIFACTORY_DEPLOY_PASSWORD: Access token to deploy to the repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to access the private repository
# - ARTIFACTORY_DEPLOY_USERNAME: Username used by artifactory-maven-plugin
# - DEFAULT_BRANCH: Default branch name (e.g. main)
# - PULL_REQUEST: Pull request number (e.g. 1234) or empty string
#
# GitHub Actions auto-provided:
# - GITHUB_REF_NAME: Git branch name
# - GITHUB_SHA: Git commit SHA
# - GITHUB_REPOSITORY: Repository name (e.g. sonarsource/sonar-dummy-maven)
# - GITHUB_RUN_ID: GitHub workflow run ID
# - GITHUB_EVENT_NAME: Event name (e.g. push, pull_request)
# - GITHUB_OUTPUT: Path to GitHub Actions output file
# - GITHUB_BASE_REF: Base branch for pull requests (only during pull_request events)
# - GITHUB_HEAD_REF: Head branch for pull requests (only during pull_request events)
#
# Optional user customization:
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - MAVEN_LOCAL_REPOSITORY: Path to Maven local repository (default: $HOME/.m2/repository)
# - MAVEN_SETTINGS: Path to Maven settings.xml (default: $HOME/.m2/settings.xml)
# - MAVEN_OPTS: JVM options for Maven (e.g. -Xmx1536m -Xms128m)
# - SONAR_SCANNER_JAVA_OPTS: JVM options for SonarQube scanner (e.g. -Xmx512m)
# - SCANNER_VERSION: SonarQube Maven plugin version (default: 5.1.0.4751)
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

: "${ARTIFACTORY_URL:?}"
# Required by maven-enforcer-plugin in SonarSource parent POM
: "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_PASSWORD:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}"
: "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"
: "${MAVEN_LOCAL_REPOSITORY:=$HOME/.m2/repository}"
: "${DEPLOY_PULL_REQUEST:=false}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST MAVEN_LOCAL_REPOSITORY
: "${MAVEN_SETTINGS:=$HOME/.m2/settings.xml}"

# FIXME Workaround for SonarSource parent POM; it can be removed after releases of parent 73+ and parent-oss 84+
export BUILD_ID=$BUILD_NUMBER

# SonarQube parameters
: "${SCANNER_VERSION:=5.1.0.4751}"
readonly SONAR_GOAL="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"

# Check if a command is available and runs it, typically: 'some_tool --version'
check_tool() {
  if ! command -v "$1"; then
    echo "$1 is not installed." >&2
    return 1
  fi
  "$@"
}

is_default_branch() {
  [[ "$GITHUB_REF_NAME" == "$DEFAULT_BRANCH" ]]
}

is_maintenance_branch() {
  [[ "${GITHUB_REF_NAME}" == branch-* ]]
}

is_pull_request() {
  [[ "$GITHUB_EVENT_NAME" == pull_request ]]
}

is_dogfood_branch() {
  [[ "${GITHUB_REF_NAME}" == dogfood-on-* ]]
}

is_long_lived_feature_branch() {
  [[ "${GITHUB_REF_NAME}" == feature/long/* ]]
}

# Unshallow and fetch all commit history for SonarQube analysis and issue assignment
git_fetch_unshallow() {
  # The --filter=blob:none flag significantly speeds up the download
  if git rev-parse --is-shallow-repository --quiet >/dev/null 2>&1; then
    echo "Fetch Git references for SonarQube analysis..."
    git fetch --unshallow --filter=blob:none
  elif is_pull_request; then
    echo "Fetch ${GITHUB_BASE_REF:?} for SonarQube analysis..."
    git fetch --filter=blob:none origin "${GITHUB_BASE_REF}"
  fi
}

# Evaluate a Maven property/expression with org.codehaus.mojo:exec-maven-plugin
maven_expression() {
  if ! mvn -q -Dexec.executable="echo" -Dexec.args="\${$1}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec; then
    echo "Failed to evaluate Maven expression '$1'" >&2
    mvn -X -Dexec.executable="echo" -Dexec.args="\${$1}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec
    return 1
  fi
}

# Set the project version as <MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>
# Update current_version variable with the current project version.
# Then remove the -SNAPSHOT suffix if present, complete with '.0' if needed, and append the build number at the end.
set_project_version() {
  if [ ! -f "$MAVEN_SETTINGS" ]; then
    echo "::error title=Missing Maven settings.xml::Maven settings.xml file not found at $MAVEN_SETTINGS"
    return 1
  fi
  local current_version
  if ! current_version=$(maven_expression "project.version" 2>&1); then
    echo -e "::error file=pom.xml,title=Maven project version::Could not get 'project.version' from Maven project\nERROR: $current_version"
    return 1
  fi

  local release_version="${current_version%"-SNAPSHOT"}"
  local digits="${release_version//[^.]/}"
  local digit_count="${#digits}"

  # shellcheck disable=SC2035
  if is_maintenance_branch && [[ "$current_version" != *"-SNAPSHOT" ]]; then
    echo "Found RELEASE version on maintenance branch: $current_version"
    if [[ "$digit_count" -ne 3 ]]; then
      echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
      return 1
    fi
    echo "Skipping version update."
    export PROJECT_VERSION=$current_version
    return 0
  fi

  if [[ "$digit_count" -eq 0 ]]; then
    release_version="${release_version}.0.0"
  elif [[ "$digit_count" -eq 1 ]]; then
    release_version="${release_version}.0"
  elif [[ "$digit_count" -ne 2 ]]; then
    echo "::error file=pom.xml,title=Maven project version::Unsupported version '$current_version' with $((digit_count + 1)) digits."
    return 1
  fi
  local new_version="${release_version}.${BUILD_NUMBER}"

  echo "Replacing version $current_version with $new_version"
  mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion="$new_version" -DgenerateBackupPoms=false -B -e
  export PROJECT_VERSION=$new_version
}

build_maven() {
  check_tool mvn --version
  git_fetch_unshallow

  set_project_version

  local maven_command_args
  local sonar_props=("-Dsonar.host.url=${SONAR_HOST_URL}" "-Dsonar.token=${SONAR_TOKEN}")
  sonar_props+=("-Dsonar.projectVersion=$PROJECT_VERSION" "-Dsonar.scm.revision=$GITHUB_SHA")

  if is_default_branch || is_maintenance_branch; then
    echo "======= Build, deploy and analyze $GITHUB_REF_NAME ======="
    maven_command_args=("deploy" "$SONAR_GOAL" "-Pcoverage,deploy-sonarsource,release,sign" "${sonar_props[@]}")

  elif is_pull_request; then
    echo "======= Build and analyze pull request $PULL_REQUEST ($GITHUB_HEAD_REF) ======="
    sonar_props+=("-Dsonar.pullrequest.key=$PULL_REQUEST")
    sonar_props+=("-Dsonar.pullrequest.branch=$GITHUB_HEAD_REF")
    sonar_props+=("-Dsonar.pullrequest.base=$GITHUB_BASE_REF")

    if [[ "$DEPLOY_PULL_REQUEST" == "true" ]]; then
      echo "======= with deploy ======="
      maven_command_args=("deploy" "$SONAR_GOAL" "-Pcoverage,deploy-sonarsource" "${sonar_props[@]}")
    else
      echo "======= no deploy ======="
      maven_command_args=("verify" "$SONAR_GOAL" "-Pcoverage" "${sonar_props[@]}")
    fi

  elif is_dogfood_branch; then
    echo "======= Build, and deploy dogfood branch $GITHUB_REF_NAME ======="
    maven_command_args=("deploy" "-Pdeploy-sonarsource,release")

  elif is_long_lived_feature_branch; then
    echo "======= Build and analyze long lived feature branch $GITHUB_REF_NAME ======="
    maven_command_args=("verify" "$SONAR_GOAL" "-Pcoverage" "${sonar_props[@]}")

  else
    echo "======= Build, no analysis, no deploy $GITHUB_REF_NAME ======="
    maven_command_args=("verify")
  fi

  readonly COMMON_MVN_FLAGS=("-Dmaven.test.redirectTestOutputToFile=false" "-B" "-e" "-V")
  echo "Maven command: mvn ${maven_command_args[*]} ${COMMON_MVN_FLAGS[*]} $*"
  mvn "${maven_command_args[@]}" "${COMMON_MVN_FLAGS[@]}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_maven "$@"
fi
