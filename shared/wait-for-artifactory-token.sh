#!/bin/bash
# Wait until a SaaS-issued Artifactory access token is accepted by a JFrog Edge node.
#
# Access Federation propagates the tokens issued by SaaS Repox to the Edge a few seconds later; until then the Edge
# answers HTTP 401. Retries on HTTP 401 or when the Edge does not answer, fails on any other status or after the
# timeout. Returns immediately for jfrog.io hosts.
#
# Required environment variables:
#   ARTIFACTORY_URL: Artifactory base URL (ending with /artifactory)
#   ARTIFACTORY_ACCESS_TOKEN: Artifactory access token to verify
# Optional environment variables:
#   ARTIFACTORY_TOKEN_PROBE_PATH: authenticated endpoint, relative to ARTIFACTORY_URL (default: api/system/version)
#   ARTIFACTORY_TOKEN_TIMEOUT_SECONDS: maximum time to wait (default: 300)
#   ARTIFACTORY_TOKEN_INTERVAL_SECONDS: time between two probes (default: 10)

set -euo pipefail

: "${ARTIFACTORY_URL:?}"

host="${ARTIFACTORY_URL#*://}"
host="${host%%/*}"
host="${host%%:*}"
if [[ "$host" == "jfrog.io" || "$host" == *.jfrog.io ]]; then
  echo "Skipping token federation wait for SaaS Artifactory ($ARTIFACTORY_URL)"
  exit 0
fi

: "${ARTIFACTORY_ACCESS_TOKEN:?}"
probe_url="${ARTIFACTORY_URL%/}/${ARTIFACTORY_TOKEN_PROBE_PATH:-api/system/version}"
timeout="${ARTIFACTORY_TOKEN_TIMEOUT_SECONDS:-300}"
interval="${ARTIFACTORY_TOKEN_INTERVAL_SECONDS:-10}"
max_attempts=$((timeout / interval))
if ((max_attempts < 1)); then
  max_attempts=1
fi

deadline=$((SECONDS + timeout))

echo "Waiting for Artifactory token federation at $probe_url (up to ${timeout}s, probing every ${interval}s)"
status=000
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  # Bound each probe by the time left so the whole wait never exceeds the timeout.
  request_timeout=$((deadline - SECONDS))
  request_timeout=$((request_timeout < 1 ? 1 : request_timeout > 30 ? 30 : request_timeout))
  status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout "$((request_timeout < 10 ? request_timeout : 10))" --max-time "$request_timeout" \
    --header "Authorization: Bearer ${ARTIFACTORY_ACCESS_TOKEN}" "$probe_url" || true)
  status="${status:-000}"
  if [[ "$status" == "200" ]]; then
    echo "Artifactory token accepted after $attempt attempt(s)"
    exit 0
  fi
  if [[ "$status" != "401" && "$status" != "000" ]]; then
    echo "::error title=Artifactory token federation::Unexpected response from $probe_url: HTTP $status" >&2
    exit 1
  fi
  if ((attempt == max_attempts || SECONDS + interval >= deadline)); then
    break
  fi
  echo "Attempt $attempt: HTTP $status, retrying in ${interval}s"
  sleep "$interval"
done

echo "::error title=Artifactory token federation::Artifactory token was not accepted by $probe_url" \
  "within ${timeout}s (last: HTTP $status)" >&2
exit 1
