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

set -euo pipefail

REPOX_URL="${REPOX_URL:-${ARTIFACTORY_URL:-}}"
if [[ "$REPOX_URL" == *jfrog.io* ]]; then
  echo "Skipping token sync wait for SaaS Repox ($REPOX_URL)"
  exit 0
fi

if [[ -z "${ARTIFACTORY_URL:-}" || -z "${ARTIFACTORY_USERNAME:-}" || -z "${ARTIFACTORY_ACCESS_TOKEN:-}" ]]; then
  echo "::error title=Missing Artifactory credentials::Cannot wait for token sync without credentials"
  exit 1
fi

check_url="${ARTIFACTORY_URL%/}/api/storage/sonarsource-qa"
max_attempts=60
sleep_seconds=5
attempt=0

echo "Waiting for Artifactory token federation sync at $check_url (up to $((max_attempts * sleep_seconds))s)"

while true; do
  attempt=$((attempt + 1))
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -u "${ARTIFACTORY_USERNAME}:${ARTIFACTORY_ACCESS_TOKEN}" \
    "$check_url" || echo "000")"

  if [[ "$http_code" == "200" ]]; then
    echo "Artifactory accepted credentials after ${attempt} attempt(s) (HTTP 200)"
    exit 0
  fi

  if (( attempt >= max_attempts )); then
    echo "::error title=Artifactory token sync timeout::Credentials were not accepted by $check_url" \
      "within $((max_attempts * sleep_seconds))s (last HTTP ${http_code})"
    exit 1
  fi

  echo "Attempt ${attempt}/${max_attempts}: HTTP ${http_code}, retrying in ${sleep_seconds}s..."
  sleep "$sleep_seconds"
done
