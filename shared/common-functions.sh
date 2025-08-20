#!/bin/bash
# Common SonarQube functions shared across build scripts
# This file contains reusable functions for SonarQube platform configuration and analysis coordination.

# SonarQube platform configuration
set_sonar_platform_vars() {
  local platform="${1:?}"

  case "$platform" in
    "next")
      export SONAR_HOST_URL="$NEXT_URL"
      export SONAR_TOKEN="$NEXT_TOKEN"
      unset SONAR_REGION
      ;;
    "sqc-us")
      export SONAR_HOST_URL="$SQC_US_URL"
      export SONAR_TOKEN="$SQC_US_TOKEN"
      export SONAR_REGION="us"
      ;;
    "sqc-eu")
      export SONAR_HOST_URL="$SQC_EU_URL"
      export SONAR_TOKEN="$SQC_EU_TOKEN"
      unset SONAR_REGION
      ;;
    *)
      echo "ERROR: Invalid Sonar platform '$platform'. Must be one of: next, sqc-us, sqc-eu" >&2
      return 1
      ;;
  esac

  if [ -n "${SONAR_REGION:-}" ]; then
    echo "Using Sonar platform: $platform (URL: $SONAR_HOST_URL, Region: $SONAR_REGION)"
  else
    echo "Using Sonar platform: $platform (URL: $SONAR_HOST_URL)"
  fi
}

# SonarQube analysis
run_sonar_analysis() {
  if [ "${RUN_SHADOW_SCANS}" = "true" ]; then
      echo "=== Running Sonar analysis on all platforms (shadow scan enabled) ==="
      local platforms=("next" "sqc-us" "sqc-eu")

      for platform in "${platforms[@]}"; do
          echo "--- Analyzing with platform: $platform ---"
          set_sonar_platform_vars "$platform"
          run_sonar_scanner "$@"
      done

      echo "=== Completed Sonar analysis on all platforms ==="
  else
      echo "=== Running Sonar analysis on selected platform: $SONAR_PLATFORM ==="
      set_sonar_platform_vars "$SONAR_PLATFORM"
      run_sonar_scanner "$@"
  fi
}
