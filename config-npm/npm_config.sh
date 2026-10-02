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
  jf config add repox --url "${ARTIFACTORY_URL%/artifactory*}" --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_ACCESS_TOKEN"
  jf config use repox
  jf npm-config --global --repo-resolve "npm"
  return 0
}

rewrite_lockfiles() {
  [[ "$ARTIFACTORY_URL" == https://repox.jfrog.io/* ]] && return 0
  local lockfile
  while IFS= read -r -d '' lockfile; do
    sed -i.bak "s#https://repox\.jfrog\.io/artifactory/api/npm/#${ARTIFACTORY_URL}/api/npm/#g" "$lockfile"
    rm -f "$lockfile.bak"
    echo "Resolving ${lockfile#./} through ${ARTIFACTORY_URL}"
  done < <(find . -name node_modules -prune -o \( -name package-lock.json -o -name npm-shrinkwrap.json \) -type f -print0)
  return 0
}

main() {
  echo "::group::Setup build environment"
  check_tool jq --version
  check_tool jf --version
  set_build_env
  rewrite_lockfiles
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
