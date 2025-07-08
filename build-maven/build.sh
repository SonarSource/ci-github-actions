#!/bin/bash

set -euo pipefail

# Required environment variables
: "${ARTIFACTORY_URL:="https://repox.jfrog.io/artifactory"}"
: "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_PASSWORD:?}" "${ARTIFACTORY_PRIVATE_PASSWORD:?}"
: "${GITHUB_REF_NAME:?}" "${BUILD_NUMBER:?}" "${GITHUB_REPOSITORY:?}"
: "${GITHUB_EVENT_NAME:?}" "${PULL_REQUEST:?}" "${PULL_REQUEST_SHA:-}"
: "${SONAR_HOST_URL:?}" "${SONAR_TOKEN:?}"

# Set BUILD_ID for compatibility with SonarSource parent POM to change when BUILD-8508 resolved
BUILD_ID=$BUILD_NUMBER
export BUILD_NUMBER BUILD_ID

# =============================================================================
# CONFIGURATION CONSTANTS
# =============================================================================

readonly SCANNER_VERSION="${SCANNER_VERSION:-5.0.0.4389}"
readonly MASTER_MAVEN_OPTS="-Xmx1536m -Xms128m"
readonly MAINTENANCE_MAVEN_OPTS="-Xmx1536m -Xms128m"
readonly PR_MAVEN_OPTS="-Xmx1G -Xms128m"
readonly COMMON_MVN_FLAGS="-B -e -V"

# Maven profile combinations
readonly FULL_PROFILES="coverage,deploy-sonarsource,release,sign"
readonly DEPLOY_PROFILES="coverage,deploy-sonarsource"
readonly COVERAGE_ONLY="coverage"
readonly DOGFOOD_PROFILES="deploy-sonarsource,release"

# Common SonarQube properties
readonly COMMON_SONAR_PROPS="-Dsonar.analysis.buildNumber=${BUILD_NUMBER:-} -Dsonar.analysis.pipeline=${GITHUB_RUN_ID:-} -Dsonar.analysis.repository=${GITHUB_REPOSITORY:-}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Evaluate a Maven property/expression by leveraging Maven's property resolution
# This function uses the exec-maven-plugin to dynamically extract values from the POM
# without needing to parse XML directly. It's particularly useful for getting project
# properties like version, groupId, artifactId, etc.
maven_expression() {
    local expression="$1"
    mvn -q -Dexec.executable="echo" -Dexec.args="\${$expression}" --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec
}

# Validate version format: <major>.<minor>.<patch>.<buildNumber>
check_version_format() {
    local version="$1"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || echo "WARN: Version '$version' does not match the expected format '<MAJOR>.<MINOR>.<PATCH>.<BUILD_NUMBER>'."
}

# =============================================================================
# VERSION MANAGEMENT
# =============================================================================

# Convert SNAPSHOT version to release version with build number
set_maven_build_version() {
    local build_number="$1"
    local current_version

    if ! current_version=$(maven_expression "project.version"); then
        echo "ERROR: Could not get project.version from Maven project" >&2
        return 1
    fi

    local release_version="${current_version%"-SNAPSHOT"}"

    # Ensure at least 3 digits for version comparison
    # Ensure version has at least 3 components (e.g., "1.2" becomes "1.2.0")
    if [[ "${release_version//[^.]}" != ".." ]]; then
        release_version="$release_version.0"
    fi

    PROJECT_VERSION="$release_version.$build_number"
    echo "Replacing version $current_version with $PROJECT_VERSION"

    # Use Maven versions plugin to update all project versions (parent + modules) to the calculated version
    # -DnewVersion: Sets the new version across all POMs
    # -DgenerateBackupPoms=false: Don't create .pom.versionsBackup files
    # -B: Batch mode (non-interactive), -e: Show errors
    mvn org.codehaus.mojo:versions-maven-plugin:2.7:set -DnewVersion="$PROJECT_VERSION" -DgenerateBackupPoms=false -B -e
    export PROJECT_VERSION
}

# =============================================================================
# MAVEN EXECUTION FUNCTIONS
# =============================================================================

# Generate common SonarQube properties
get_sonar_properties() {
    local context="$1"
    local sha="${2:-$GITHUB_SHA}"

    local props="-Dsonar.host.url=${SONAR_HOST_URL} -Dsonar.token=${SONAR_TOKEN} $COMMON_SONAR_PROPS"

    case "$context" in
        "master")
            props="$props -Dsonar.projectVersion=${CURRENT_VERSION} -Dsonar.analysis.sha1=$sha"
            ;;
        "maintenance"|"feature")
            props="$props -Dsonar.branch.name=${GITHUB_REF_NAME} -Dsonar.analysis.sha1=$sha"
            ;;
        "pr")
            props="$props -Dsonar.analysis.sha1=$sha -Dsonar.analysis.prNumber=${PULL_REQUEST}"
            ;;
    esac

    echo "$props"
}

# Execute Maven command with explicit parameter handling
execute_maven() {
    local maven_goals="$1"
    local maven_profiles="$2"
    local maven_properties="$3"

    echo "======= Maven Command Details ======="
    echo "• Goals to execute: $maven_goals"

    # Build command components
    local profile_args=""
    if [ -n "$maven_profiles" ]; then
        profile_args="-P$maven_profiles"
        echo "• Profiles to activate: $maven_profiles"
    else
        echo "• Profiles: none"
    fi

    local property_args=""
    if [ -n "$maven_properties" ]; then
        property_args="$maven_properties"
        echo "• Additional properties: $maven_properties"
    else
        echo "• Additional properties: none"
    fi

    # Construct final command
    local full_command="mvn $maven_goals $profile_args $property_args $COMMON_MVN_FLAGS"

    echo "• Common flags: $COMMON_MVN_FLAGS"
    echo "======================================"
    echo "Executing: $full_command"
    echo ""

    eval "$full_command"
}

# =============================================================================
# BUILD CONTEXT DETECTION
# =============================================================================

detect_build_context() {
    if [[ "${GITHUB_REF_NAME}" == "master" && "${PULL_REQUEST}" == "false" ]]; then
        echo "master"
    elif [[ "${GITHUB_REF_NAME}" == "branch-"* && "${PULL_REQUEST}" == "false" ]]; then
        echo "maintenance"
    elif [[ "${PULL_REQUEST}" != "false" ]]; then
        echo "pr"
    elif [[ "${GITHUB_REF_NAME}" == "dogfood-on-"* && "${PULL_REQUEST}" == "false" ]]; then
        echo "dogfood"
    elif [[ "${GITHUB_REF_NAME}" == "feature/long/"* && "${PULL_REQUEST}" == "false" ]]; then
        echo "feature"
    else
        echo "default"
    fi
}

# =============================================================================
# CONTEXT-SPECIFIC BUILD FUNCTIONS
# =============================================================================

build_master() {
    echo "======= Build, deploy and analyze master ======="

    git fetch --quiet origin "${GITHUB_REF_NAME}"
    export MAVEN_OPTS="${MAVEN_OPTS:-$MASTER_MAVEN_OPTS}"

    # Store current version for SonarQube analysis
    local current_version
    current_version=$(maven_expression "project.version")
    export CURRENT_VERSION=$current_version

    # Set up build version
    echo "Setting up build version with build number: ${BUILD_NUMBER}"
    set_maven_build_version "${BUILD_NUMBER}"
    check_version_format "$PROJECT_VERSION"
    echo "Version updated to: $PROJECT_VERSION"

    # Execute Maven with SonarQube analysis
    local sonar_goal="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"
    local sonar_props
    sonar_props=$(get_sonar_properties "master")
    local test_redirect="-Dmaven.test.redirectTestOutputToFile=false"

    execute_maven "deploy $sonar_goal" "$FULL_PROFILES" "$sonar_props $test_redirect"
}

build_maintenance() {
    echo "======= Build and deploy maintenance branch ======="

    git fetch --quiet origin "${GITHUB_REF_NAME}"
    export MAVEN_OPTS="${MAVEN_OPTS:-$MAINTENANCE_MAVEN_OPTS}"

    local current_version
    current_version=$(maven_expression "project.version")
    export CURRENT_VERSION=$current_version

    if [[ "$CURRENT_VERSION" =~ "-SNAPSHOT" ]]; then
        echo "======= Found SNAPSHOT version ======="
        echo "Setting up build version with build number: ${BUILD_NUMBER}"
        set_maven_build_version "${BUILD_NUMBER}"
        check_version_format "$PROJECT_VERSION"
        echo "Version updated to: $PROJECT_VERSION"
    else
        echo "======= Found RELEASE version ======="
        echo "======= Deploy $CURRENT_VERSION ======="
        check_version_format "$CURRENT_VERSION"
        echo "Using current version: $CURRENT_VERSION"
    fi

    # Deploy first, then analyze separately
    execute_maven "deploy" "$FULL_PROFILES" ""

    # Separate SonarQube analysis
    local sonar_props
    sonar_props=$(get_sonar_properties "maintenance")
    execute_maven "org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar" "" "$sonar_props"
}

build_pr() {
    echo "======= Build and analyze pull request ======="

    export MAVEN_OPTS="${MAVEN_OPTS:-$PR_MAVEN_OPTS}"

    # Set up build version
    echo "Setting up build version with build number: ${BUILD_NUMBER}"
    set_maven_build_version "${BUILD_NUMBER}"
    check_version_format "$PROJECT_VERSION"
    echo "Version updated to: $PROJECT_VERSION"

    # Execute Maven with SonarQube analysis
    local sonar_goal="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"
    local test_redirect="-Dmaven.test.redirectTestOutputToFile=false"

    if [[ "${DEPLOY_PULL_REQUEST:-}" == "true" ]]; then
        echo "======= with deploy ======="
        local sonar_props
        sonar_props=$(get_sonar_properties "pr" "$GITHUB_SHA")
        execute_maven "deploy $sonar_goal" "$DEPLOY_PROFILES" "$sonar_props $test_redirect"
    else
        echo "======= no deploy ======="
        local sonar_props
        sonar_props=$(get_sonar_properties "pr" "${PULL_REQUEST_SHA:-$GITHUB_SHA}")
        execute_maven "verify $sonar_goal" "$COVERAGE_ONLY" "$sonar_props $test_redirect"
    fi
}

build_dogfood() {
    echo "======= Build dogfood branch ======="

    # Set up build version
    echo "Setting up build version with build number: ${BUILD_NUMBER}"
    set_maven_build_version "${BUILD_NUMBER}"
    check_version_format "$PROJECT_VERSION"
    echo "Version updated to: $PROJECT_VERSION"

    execute_maven "deploy" "$DOGFOOD_PROFILES" ""
}

build_feature() {
    echo "======= Build and analyze long lived feature branch ======="

    # Execute Maven with SonarQube analysis
    local sonar_goal="org.sonarsource.scanner.maven:sonar-maven-plugin:${SCANNER_VERSION}:sonar"
    local sonar_props
    sonar_props=$(get_sonar_properties "feature")
    local test_redirect="-Dmaven.test.redirectTestOutputToFile=false"

    execute_maven "verify $sonar_goal" "$COVERAGE_ONLY" "$sonar_props $test_redirect"
}

build_default() {
    echo "======= Build, no analysis, no deploy ======="

    execute_maven "verify" "" "-Dmaven.test.redirectTestOutputToFile=false"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "======= Starting optimized Maven build ======="
    echo "======= Environment setup handled by action.yml ======="

    # Detect build context and execute appropriate build strategy
    local context
    context=$(detect_build_context)

    echo "======= Detected build context: $context ======="

    # Execute the appropriate build function based on detected context
    case "$context" in
        "master")
            build_master
            ;;
        "maintenance")
            build_maintenance
            ;;
        "pr")
            build_pr
            ;;
        "dogfood")
            build_dogfood
            ;;
        "feature")
            build_feature
            ;;
        "default")
            build_default
            ;;
        *)
            echo "ERROR: Unknown build context: $context" >&2
            exit 1
            ;;
    esac

    echo "======= Build completed successfully ======="
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
