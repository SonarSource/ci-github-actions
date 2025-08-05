#!/usr/bin/env bash

# cache-mise-install.sh
# Install OS-level requirements for the cache action using mise
# This script avoids conflicts with existing mise.local.toml files

set -euo pipefail

echo "Installing cache action OS-level requirements..."
mise use --pin jq@1.8.1
echo "jq version: $(jq --version)"
