#!/bin/bash
# Common Maven flags used across build and analysis operations
# These flags ensure consistent Maven behavior for CI/CD operations

readonly COMMON_MVN_FLAGS=(
  "-Dmaven.test.redirectTestOutputToFile=false"
  "--settings" "$MAVEN_SETTINGS"
  "--batch-mode"
  "--no-transfer-progress"
  "--errors"
  "--fail-at-end"
  "--show-version"
)
export COMMON_MVN_FLAGS
