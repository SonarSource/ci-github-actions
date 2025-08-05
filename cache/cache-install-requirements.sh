#!/usr/bin/env bash

# cache-install-requirements.sh
# Install OS-level requirements for the cache action
# This script installs jq without relying on mise or creating config files

set -euo pipefail

echo "Installing cache action OS-level requirements..."

# Check if jq is already available
if command -v jq >/dev/null 2>&1; then
  echo "✅ jq is already available: $(jq --version)"
  exit 0
fi

# Install jq based on the operating system
case "$(uname -s)" in
  Linux*)
    echo "Installing jq on Linux..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y jq
    elif command -v apk >/dev/null 2>&1; then
      sudo apk add --no-cache jq
    else
      echo "❌ Unsupported Linux package manager"
      exit 1
    fi
    ;;
  Darwin*)
    echo "Installing jq on macOS..."
    if command -v brew >/dev/null 2>&1; then
      brew install jq
    else
      echo "❌ Homebrew not found. Please install jq manually."
      exit 1
    fi
    ;;
  *)
    echo "❌ Unsupported operating system: $(uname -s)"
    exit 1
    ;;
esac

echo "✅ Successfully installed jq"
echo "jq version: $(jq --version)"
