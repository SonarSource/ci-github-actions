#!/bin/bash
# Wait until a SaaS-minted Artifactory token is accepted by an edge node.
#
# /api/system/ping is anonymous; use a protected storage API that validates the token.
#
# Required environment variables:
# - ARTIFACTORY_URL: Artifactory base URL (…/artifactory)
# - ARTIFACTORY_USERNAME: Artifactory username
# - ARTIFACTORY_ACCESS_TOKEN: Artifactory access token
#
# Optional:
# - REPOX_URL: Instance URL used to skip the wait for SaaS (jfrog.io)
# - ARTIFACTORY_TOKEN_SYNC_MAX_ATTEMPTS: Max poll attempts (default 60)
# - ARTIFACTORY_TOKEN_SYNC_SLEEP_SECONDS: Sleep between attempts (default 5)

set -euo pipefail

is_saas_repox() {
  local url="${1:-}"
  [[ "$url" == *jfrog.io* ]]
}

require_artifactory_credentials() {
  if [[ -z "${ARTIFACTORY_URL:-}" || -z "${ARTIFACTORY_USERNAME:-}" || -z "${ARTIFACTORY_ACCESS_TOKEN:-}" ]]; then
    echo "::error title=Missing Artifactory credentials::Cannot wait for token sync without credentials" >&2
    return 1
  fi
  return 0
}

check_artifactory_token() {
  local check_url="$1"
  local http_code
  # Do not append a fallback via || echo: curl -w still emits http_code (often 000) on failure.
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 30 \
    -u "${ARTIFACTORY_USERNAME}:${ARTIFACTORY_ACCESS_TOKEN}" \
    "$check_url" || true)"
  echo "${http_code:-000}"
}

wait_for_artifactory_token_sync() {
  local repox_url check_url max_attempts sleep_seconds attempt http_code

  repox_url="${REPOX_URL:-${ARTIFACTORY_URL:-}}"
  if is_saas_repox "$repox_url"; then
    echo "Skipping token sync wait for SaaS Repox ($repox_url)"
    return 0
  fi

  require_artifactory_credentials || return 1

  check_url="${ARTIFACTORY_URL%/}/api/storage/sonarsource-qa"
  max_attempts="${ARTIFACTORY_TOKEN_SYNC_MAX_ATTEMPTS:-60}"
  sleep_seconds="${ARTIFACTORY_TOKEN_SYNC_SLEEP_SECONDS:-5}"
  attempt=0

  echo "Waiting for Artifactory token federation sync at $check_url (up to $((max_attempts * sleep_seconds))s)"

  while true; do
    attempt=$((attempt + 1))
    http_code="$(check_artifactory_token "$check_url")"

    if [[ "$http_code" == "200" ]]; then
      echo "Artifactory accepted credentials after ${attempt} attempt(s) (HTTP 200)"
      return 0
    fi

    if (( attempt >= max_attempts )); then
      echo "::error title=Artifactory token sync timeout::Credentials were not accepted by $check_url" \
        "within $((max_attempts * sleep_seconds))s (last HTTP ${http_code})" >&2
      return 1
    fi

    echo "Attempt ${attempt}/${max_attempts}: HTTP ${http_code}, retrying in ${sleep_seconds}s..."
    sleep "$sleep_seconds"
  done
}

main() {
  wait_for_artifactory_token_sync
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
