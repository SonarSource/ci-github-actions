#!/bin/bash
# Configure NPM authentication.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory repository
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories

set -euo pipefail

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}"

set_build_env() {
  echo "Configuring JFrog and NPM repositories..."
  cat <<EOF >> ~/.npmrc
registry=${ARTIFACTORY_URL}/api/npm/npm
${ARTIFACTORY_URL#https:}/api/npm/:_authToken=${ARTIFACTORY_ACCESS_TOKEN}
EOF
  jf config remove repox > /dev/null 2>&1 || true # Ignore inexistent configuration
  jf config add repox --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox
  jf npm-config --repo-resolve "npm"
  return 0
}

main() {
  echo "::group::Setup build environment"
  check_tool jq --version
  check_tool jf --version
  set_build_env
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
