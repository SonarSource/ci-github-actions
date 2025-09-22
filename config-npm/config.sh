#!/bin/bash
# Config script for SonarSource NPM projects.
#
# Required inputs (must be explicitly provided):
#
# GitHub Actions auto-provided:
#
# Optional user customization:
#
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

# Source common functions shared across build scripts
# shellcheck source=../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"
