#!/bin/bash
# Build and deploy a Maven project.
# Supports building, testing, SonarQube analysis, and Maven deployment to Artifactory.
#
# Required inputs (must be explicitly provided):
# - BUILD_NUMBER: Build number for versioning
# - SONAR_PLATFORM: SonarQube primary platform (next, sqc-eu, sqc-us, or none). Use 'none' to skip sonar scans.
# - NEXT_URL: URL of SonarQube server for next platform
# - NEXT_TOKEN: Access token to send analysis reports to SonarQube for next platform
# - SQC_US_URL: URL of SonarQube server for sqc-us platform
# - SQC_US_TOKEN: Access token to send analysis reports to SonarQube for sqc-us platform
# - SQC_EU_URL: URL of SonarQube server for sqc-eu platform
# - SQC_EU_TOKEN: Access token to send analysis reports to SonarQube for sqc-eu platform
# - RUN_SHADOW_SCANS: If true, run sonar scanner on all 3 platforms. If false, run on the platform provided by SONAR_PLATFORM.
# - ARTIFACTORY_URL: Artifactory repository URL
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - ARTIFACTORY_DEPLOY_REPO: Deployment repository name
# - ARTIFACTORY_DEPLOY_USERNAME: Username used by artifactory-maven-plugin
# - ARTIFACTORY_DEPLOY_PASSWORD: Access token to deploy to the repository
# - CURRENT_VERSION: Current project version as in pom.xml
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
# - RUNNER_OS: Operating system (e.g. Linux, Windows)
#
# Optional user customization:
# - DEPLOY: Whether to deploy (default: true)
# - DEPLOY_PULL_REQUEST: Whether to deploy pull request artifacts (default: false)
# - SONAR_SCANNER_JAVA_OPTS: JVM options for SonarQube scanner (e.g. -Xmx512m)
# - SCANNER_VERSION: SonarQube Maven plugin version (default: 5.3.0.6276)
# - USER_MAVEN_ARGS: Additional arguments to pass to Maven
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}"
# Required by maven-enforcer-plugin in SonarSource parent POM
: "${ARTIFACTORY_DEPLOY_REPO:?}"
: "${DEPLOY:=true}"
: "${CURRENT_VERSION:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_EVENT_NAME:?}"
: "${GITHUB_SHA:?}"
: "${GITHUB_OUTPUT:?}"
: "${RUNNER_OS:?}"
: "${PULL_REQUEST?}" "${DEFAULT_BRANCH:?}"
if [[ "${SONAR_PLATFORM:?}" != "none" ]]; then
  : "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
fi
: "${RUN_SHADOW_SCANS:?}"
if [[ "$DEPLOY" != "false" && "$RUN_SHADOW_SCANS" != "true" ]]; then
  : "${ARTIFACTORY_DEPLOY_USERNAME:?}" "${ARTIFACTORY_DEPLOY_PASSWORD:?}"
fi
: "${DEPLOY_PULL_REQUEST:=false}"
: "${USER_MAVEN_ARGS:=}"
export ARTIFACTORY_URL DEPLOY_PULL_REQUEST
readonly DEPLOYED_OUTPUT_KEY="deployed"

# FIXME Workaround for SonarSource parent POM; it can be removed after releases of parent 73+ and parent-oss 84+
export BUILD_ID=$BUILD_NUMBER

# SonarQube parameters
: "${SCANNER_VERSION:=5.3.0.6276}"
readonly SONAR_GOAL="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"

# CALLBACK IMPLEMENTATION: SonarQube scanner execution
#
# This function is called BY THE ORCHESTRATOR (orchestrate_sonar_platforms)
# INVERSION OF CONTROL: We implement this interface, orchestrator calls us
# The orchestrator will:
# 1. Set SONAR_HOST_URL and SONAR_TOKEN for the current platform
# 2. Call this function to execute the actual scanner
# 3. Repeat for each platform (if shadow scanning enabled)
sonar_scanner_implementation() {
    local additional_params=("$@")
    # Build sonar properties (using orchestrator-provided SONAR_HOST_URL/SONAR_TOKEN)
    local sonar_props=("-Dsonar.host.url=${SONAR_HOST_URL}" "-Dsonar.token=${SONAR_TOKEN}")
    sonar_props+=("-Dsonar.projectVersion=${CURRENT_VERSION}" "-Dsonar.scm.revision=$GITHUB_SHA")
    sonar_props+=("${additional_params[@]+"${additional_params[@]}"}")

    echo "Maven command: mvn $SONAR_GOAL ${sonar_props[*]}"
    mvn "$SONAR_GOAL" "${sonar_props[@]}"
}

# Unshallow and fetch all commit history for SonarQube analysis and issue assignment
git_fetch_unshallow() {
  if git rev-parse --is-shallow-repository --quiet >/dev/null 2>&1; then
    echo "Fetch Git references for SonarQube analysis..."
    git fetch --unshallow || true # Ignore errors like "fatal: --unshallow on a complete repository does not make sense"
  elif is_pull_request; then
    echo "Fetch ${GITHUB_BASE_REF:?} for SonarQube analysis..."
    git fetch origin "${GITHUB_BASE_REF}"
  fi
  return 0
}

check_settings_xml() {
  if [ ! -f "$HOME/.m2/settings.xml" ]; then
    echo "::error title=Missing Maven settings.xml::Maven settings.xml file not found at $HOME/.m2/settings.xml"
    exit 1
  fi
}

should_deploy() {
  # Disable deployment when explicitly requested
  if [[ "${DEPLOY}" != "true" ]]; then
    return 1
  fi

  # Disable deployment when shadow scans are enabled to prevent duplicate artifacts
  if [[ "${RUN_SHADOW_SCANS}" = "true" ]]; then
    echo "Shadow scans enabled - disabling deployment" >&2
    return 1
  fi

  if is_pull_request; then
    # For pull requests, deploy only if explicitly enabled
    [[ "$DEPLOY_PULL_REQUEST" = "true" ]]
  else
    is_default_branch || \
    is_maintenance_branch || \
    is_dogfood_branch || \
    is_long_lived_feature_branch
  fi
}

should_scan() {
  if [ "$SONAR_PLATFORM" = "none" ]; then
    return 1
  fi
  is_default_branch || is_maintenance_branch || is_pull_request || is_long_lived_feature_branch
  return $?
}

build_maven() {
  check_tool mvn --version
  check_settings_xml

  if should_scan; then
    git_fetch_unshallow
  else
    echo "Skipping git fetch (Sonar analysis disabled)"
  fi

  local maven_command_args mvn_output
  if should_deploy; then
    maven_command_args=("deploy" "-Pdeploy-sonarsource")
  else
    maven_command_args=("install")
  fi

  if should_scan; then
    maven_command_args+=("-Pcoverage")
  fi

  if is_default_branch || is_maintenance_branch; then
    echo "======= Build and analyze $GITHUB_REF_NAME ======="
    maven_command_args+=("-Prelease,sign")
  elif is_pull_request; then
    echo "======= Build and analyze pull request $PULL_REQUEST ($GITHUB_HEAD_REF) ======="
  elif is_dogfood_branch; then
    echo "======= Build dogfood branch $GITHUB_REF_NAME ======="
    maven_command_args+=("-Prelease")
  elif is_long_lived_feature_branch; then
    echo "======= Build and analyze long lived feature branch $GITHUB_REF_NAME ======="
  else
    echo "======= Build, no analysis, no deploy $GITHUB_REF_NAME ======="
    maven_command_args=("verify")
  fi

  # Execute the main Maven build
  mvn_output=$(mktemp)
  echo "Maven command: mvn ${maven_command_args[*]} $*"
  mvn "${maven_command_args[@]}" "$@" | tee "$mvn_output"

  if should_deploy; then
    echo "$DEPLOYED_OUTPUT_KEY=true" >> "$GITHUB_OUTPUT"
    export_built_artifacts
  fi

  # Execute SonarQube analysis if enabled
  if should_scan; then
    local sonar_args=()
    if is_pull_request; then
      sonar_args+=("-Dsonar.pullrequest.key=$PULL_REQUEST")
      sonar_args+=("-Dsonar.pullrequest.branch=$GITHUB_HEAD_REF")
      sonar_args+=("-Dsonar.pullrequest.base=$GITHUB_BASE_REF")
    fi
    # This will call back to shared sonar_scanner_implementation() function
    orchestrate_sonar_platforms "${sonar_args[@]+"${sonar_args[@]}"}" "$@"
  fi
}

export_built_artifacts() {
  local installed_artifacts deployed build_dir artifacts

  installed_artifacts=$(grep Installing "$mvn_output" | sed 's,.*\.m2/repository/,,' || true)
  {
    echo "installed-artifacts<<EOF"
    echo "$installed_artifacts"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"

  # FIXME the following to use public_artifacts and private_artifacts arrays as in deploy-artifacts.sh
  deployed=$(grep "$DEPLOYED_OUTPUT_KEY=" "$GITHUB_OUTPUT" 2>/dev/null | cut -d= -f2)
  [[ "$deployed" != "true" ]] && return 0

  echo "::group::Capturing built artifacts for attestation"

  # Query Maven for build directory name, fallback to 'target'
  build_dir=$(mvn help:evaluate -Dexpression=project.build.directory -q -DforceStdout 2>/dev/null | xargs basename 2>/dev/null || echo "target")
  echo "Scanning for artifacts in: */${build_dir}/*"

  # Find all built artifacts (excluding sources, javadoc, tests)
  local artifacts
  local name_includes=(-name '*.jar' -o -name '*.war' -o -name '*.ear' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar')
  name_includes+=(-o -name '*.pom' -o -name '*.asc' -o -name '*.json')
  local name_excludes=(! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-tests.jar')
  artifacts=$(/usr/bin/find . -path "*/${build_dir}/*" \( "${name_includes[@]}" \) "${name_excludes[@]}" -type f 2>/dev/null)

  # Sort and deduplicate (avoid Windows sort.exe)
  if [[ -n "$artifacts" ]]; then
    artifacts=$(echo "$artifacts" | /usr/bin/sort -u)
  fi

  if [[ -z "$artifacts" ]]; then
    echo "::warning title=No artifacts found::No artifacts found for attestation in build output directories"
    echo "::endgroup::"
    return 0
  fi

  echo "Found artifacts for attestation:"
  echo "$artifacts"

  {
    echo "artifact-paths<<EOF"
    echo "$artifacts"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"

  echo "::endgroup::"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck disable=SC2086
  build_maven $USER_MAVEN_ARGS
fi
