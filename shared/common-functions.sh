#!/bin/bash
# Common SonarQube functions shared across build scripts
#
# This file implements an orchestrator pattern where:
# 1. Build scripts call orchestrator functions (defined here)
# 2. Orchestrators manage platform switching and call back to implementation functions
# 3. Implementation functions (defined in each build script) do the actual work
#
# CALLBACK CONTRACT:
# Build scripts MUST implement: sonar_scanner_implementation()
# This function will be called by orchestrate_sonar_platforms() for each platform
#
# CONTROL FLOW:
# build-script.sh → orchestrate_sonar_platforms() → sonar_scanner_implementation() → build-script.sh
#
# SonarQube platform configuration
set_sonar_platform_vars() {
  local platform="${1:?}"

  case "$platform" in
    "next")
      export SONAR_HOST_URL="$NEXT_URL"
      export SONAR_TOKEN="$NEXT_TOKEN"
      unset SONAR_REGION
      unset PROJECT_KEY
      ;;
    "sqc-us")
      export SONAR_HOST_URL="$SQC_US_URL"
      export SONAR_TOKEN="$SQC_US_TOKEN"
      export SONAR_REGION="us"
      export PROJECT_KEY="${$SQS_US_PROJECT_KEY:-''}"
      ;;
    "sqc-eu")
      export SONAR_HOST_URL="$SQC_EU_URL"
      export SONAR_TOKEN="$SQC_EU_TOKEN"
      unset SONAR_REGION
      export PROJECT_KEY="${$SQS_EU_PROJECT_KEY:-''}"
      ;;
    "none")
      echo "Sonar analysis disabled (platform: none)"
      return 0
      ;;
    *)
      echo "ERROR: Invalid Sonar platform '$platform'. Must be one of: next, sqc-us, sqc-eu, none" >&2
      return 1
      ;;
  esac
  echo "Using Sonar platform: $platform (URL: ${SONAR_HOST_URL#*//}, Region: ${SONAR_REGION:-none})"
}

# ORCHESTRATOR FUNCTION: Multi-platform SonarQube analysis coordinator
#
# This function:
# - Takes control from the build script
# - Manages platform switching logic
# - Calls back to sonar_scanner_implementation() for each platform
#
# CALLBACK DEPENDENCY:
# Requires build script to implement sonar_scanner_implementation() function
orchestrate_sonar_platforms() {
  if [ "$SONAR_PLATFORM" = "none" ] && [ "${RUN_SHADOW_SCANS}" != "true" ]; then
      echo "=== ORCHESTRATOR: Skipping Sonar analysis (platform: none) ==="
      return 0
  fi

  if [ "${RUN_SHADOW_SCANS}" = "true" ]; then
      echo "=== ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled) ==="
      local platforms=("next" "sqc-us" "sqc-eu")

      for platform in "${platforms[@]}"; do
          echo "::group::Sonar analysis on $platform"
          echo "--- ORCHESTRATOR: Analyzing with platform: $platform ---"
          set_sonar_platform_vars "$platform"
          # CALLBACK: Hand control back to build script's implementation
          sonar_scanner_implementation "$@"
          echo "::endgroup::"
      done
      echo "=== ORCHESTRATOR: Completed Sonar analysis on all platforms ==="
  else
      echo "=== ORCHESTRATOR: Running Sonar analysis on selected platform: $SONAR_PLATFORM ==="
      set_sonar_platform_vars "$SONAR_PLATFORM"
      # CALLBACK: Hand control back to build script's implementation
      sonar_scanner_implementation "$@"
  fi
}
