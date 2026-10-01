#!/bin/bash
# Configure NuGet authentication and point the Repox package sources of NuGet configuration files at ARTIFACTORY_URL.
#
# Required environment variables (must be explicitly provided):
# - ARTIFACTORY_URL: URL to Artifactory used to resolve packages
# - ARTIFACTORY_USERNAME: Username to read Repox repositories
# - ARTIFACTORY_ACCESS_TOKEN: Access token to read Repox repositories
# - NUGET_CONFIG_FILES: Newline-separated NuGet configuration files to update
#
# GitHub Actions auto-provided:
# - GITHUB_ENV: Path to GitHub Actions environment file

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_USERNAME:?}" "${ARTIFACTORY_ACCESS_TOKEN:?}" "${NUGET_CONFIG_FILES:?}" "${GITHUB_ENV:?}"

readonly SAAS_ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"

export_credentials() {
  {
    echo "ARTIFACTORY_URL=$ARTIFACTORY_URL"
    echo "ARTIFACTORY_USERNAME=$ARTIFACTORY_USERNAME"
    echo "ARTIFACTORY_ACCESS_TOKEN=$ARTIFACTORY_ACCESS_TOKEN"
    echo "ARTIFACTORY_USER=$ARTIFACTORY_USERNAME"
    echo "ARTIFACTORY_PASSWORD=$ARTIFACTORY_ACCESS_TOKEN"
  } >> "$GITHUB_ENV"
  return 0
}

point_nuget_config() {
  local config="$1"
  local saas_pattern="value=\"${SAAS_ARTIFACTORY_URL//./\\.}/"
  if [[ ! -f "$config" ]]; then
    echo "::error::NuGet configuration file not found: $config" >&2
    return 1
  fi
  if ! grep -q "$saas_pattern" "$config"; then
    echo "::error::No package source on $SAAS_ARTIFACTORY_URL in $config" >&2
    return 1
  fi
  sed -i.bak "s#${saas_pattern}#value=\"${ARTIFACTORY_URL}/#g" "$config"
  rm -f "$config.bak"
  echo "Package sources of $config now resolve through $ARTIFACTORY_URL"
  return 0
}

main() {
  echo "::group::Configure NuGet"
  export_credentials
  if [[ "${ARTIFACTORY_URL%/}" == "$SAAS_ARTIFACTORY_URL" ]]; then
    echo "NuGet configuration files already resolve through $SAAS_ARTIFACTORY_URL"
  else
    local config
    while IFS= read -r config; do
      config="${config%$'\r'}"
      config="$(echo "$config" | xargs)"
      [[ -z "$config" ]] && continue
      point_nuget_config "$config" || return 1
    done <<< "$NUGET_CONFIG_FILES"
  fi
  echo "::endgroup::"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
