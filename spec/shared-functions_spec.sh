#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube-us.example.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"

Describe 'shared/common-functions.sh'
  Include shared/common-functions.sh

  Describe 'set_sonar_platform_vars()'
    It 'sets sonar variables for next platform'
      When call set_sonar_platform_vars "next"
      The status should be success
      The line 1 should equal "Using Sonar platform: next (URL: next.sonarqube.com, Region: none)"
      The variable SONAR_HOST_URL should equal "https://next.sonarqube.com"
      The variable SONAR_TOKEN should equal "next-token"
    End

    It 'sets sonar variables for sqc-us platform'
      When call set_sonar_platform_vars "sqc-us"
      The status should be success
      The line 1 should equal "Using Sonar platform: sqc-us (URL: sonarqube-us.example.com, Region: us)"
      The variable SONAR_HOST_URL should equal "https://sonarqube-us.example.com"
      The variable SONAR_TOKEN should equal "sqc-us-token"
    End

    It 'sets sonar variables for sqc-eu platform'
      When call set_sonar_platform_vars "sqc-eu"
      The status should be success
      The line 1 should equal "Using Sonar platform: sqc-eu (URL: sonarcloud.io, Region: none)"
      The variable SONAR_HOST_URL should equal "https://sonarcloud.io"
      The variable SONAR_TOKEN should equal "sqc-eu-token"
    End

    It 'handles none platform'
      When call set_sonar_platform_vars "none"
      The status should be success
      The line 1 should equal "Sonar analysis disabled (platform: none)"
      The variable SONAR_HOST_URL should be undefined
      The variable SONAR_TOKEN should be undefined
    End

    It 'fails with invalid platform'
      When call set_sonar_platform_vars "invalid"
      The status should be failure
      The stderr should include "ERROR: Invalid Sonar platform 'invalid'. Must be one of: next, sqc-us, sqc-eu, none"
    End

    It 'correctly formats URL display removing protocol'
      When call set_sonar_platform_vars "next"
      The status should be success
      The line 1 should include "(URL: next.sonarqube.com"
      The line 1 should not include "https://"
    End
  End

  Describe 'orchestrate_sonar_platforms()'
    # Mock sonar_scanner_implementation for orchestrator tests
    sonar_scanner_implementation() {
      echo "sonar_scanner_implementation called with: $*"
      echo "Using SONAR_HOST_URL: ${SONAR_HOST_URL}"
      echo "Using SONAR_TOKEN: ${SONAR_TOKEN}"
    }

    It 'runs single platform analysis when shadow scans disabled'
      export RUN_SHADOW_SCANS="false"
      export SONAR_PLATFORM="next"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The output should include "=== ORCHESTRATOR: Running Sonar analysis on selected platform: next ==="
      The output should include "Using Sonar platform: next"
      The output should not include "shadow scan enabled"
    End

    It 'runs multi-platform analysis when shadow scans enabled'
      export RUN_SHADOW_SCANS="true"
      export SONAR_PLATFORM="next"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The output should include "=== ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled) ==="
      The output should include "--- ORCHESTRATOR: Analyzing with platform: next ---"
      The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-us ---"
      The output should include "--- ORCHESTRATOR: Analyzing with platform: sqc-eu ---"
      The output should include "=== ORCHESTRATOR: Completed Sonar analysis on all platforms ==="
    End

    It 'skips sonar analysis when platform is none'
      export RUN_SHADOW_SCANS="false"
      export SONAR_PLATFORM="none"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The line 1 should equal "=== ORCHESTRATOR: Skipping Sonar analysis (platform: none) ==="
      The output should not include "sonar_scanner_implementation"
    End

    It 'runs shadow scans even when platform is none'
      export RUN_SHADOW_SCANS="true"
      export SONAR_PLATFORM="none"
      When call orchestrate_sonar_platforms "-Dsonar.test=value"
      The status should be success
      The output should include "=== ORCHESTRATOR: Running Sonar analysis on all platforms (shadow scan enabled) ==="
      The output should not include "Skipping Sonar analysis"
    End
  End
End
