#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Replays the space-separated statuses of CURL_STATUSES, one per call (the last one repeats), and records the calls.
Mock curl
  count=$(($(cat "$CURL_CALLS" 2>/dev/null | wc -l) + 1))
  echo "$*" >> "$CURL_CALLS"
  read -ra statuses <<< "$CURL_STATUSES"
  index=$((count <= ${#statuses[@]} ? count - 1 : ${#statuses[@]} - 1))
  echo -n "${statuses[$index]}"
End

Mock sleep
  echo "sleep $*" >> "$SLEEP_CALLS"
End

Describe 'shared/wait-for-artifactory-token.sh'
  setup() {
    CURL_CALLS=$(mktemp)
    SLEEP_CALLS=$(mktemp)
    export CURL_CALLS SLEEP_CALLS
    export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
    export ARTIFACTORY_ACCESS_TOKEN='federated-token'
    export ARTIFACTORY_TOKEN_TIMEOUT_SECONDS=30
    export ARTIFACTORY_TOKEN_INTERVAL_SECONDS=10
    return 0
  }
  cleanup() {
    rm -f "$CURL_CALLS" "$SLEEP_CALLS"
    return 0
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'skips SaaS without probing or requiring a token'
    export ARTIFACTORY_URL='https://repox.jfrog.io/artifactory'
    unset ARTIFACTORY_ACCESS_TOKEN
    When run script shared/wait-for-artifactory-token.sh
    The status should be success
    The output should equal 'Skipping token federation wait for SaaS Artifactory (https://repox.jfrog.io/artifactory)'
    The contents of file "$CURL_CALLS" should equal ''
  End

  It 'does not treat look-alike hosts as SaaS'
    export ARTIFACTORY_URL='https://jfrog.io.example.com/artifactory'
    export CURL_STATUSES='200'
    When run script shared/wait-for-artifactory-token.sh
    The status should be success
    The output should include 'Artifactory token accepted after 1 attempt(s)'
  End

  It 'fails without an access token'
    unset ARTIFACTORY_ACCESS_TOKEN
    When run script shared/wait-for-artifactory-token.sh
    The status should be failure
    The stderr should include 'ARTIFACTORY_ACCESS_TOKEN'
  End

  It 'fails without an Artifactory URL'
    unset ARTIFACTORY_URL
    When run script shared/wait-for-artifactory-token.sh
    The status should be failure
    The stderr should include 'ARTIFACTORY_URL'
  End

  It 'waits until the token is accepted, sending it as a bearer token'
    export CURL_STATUSES='401 000 200'
    When run script shared/wait-for-artifactory-token.sh
    The status should be success
    The line 1 of output should equal 'Waiting for Artifactory token federation at https://repox-internal.dev.sonar.build/artifactory/api/system/version (up to 30s, probing every 10s)'
    The line 2 of output should equal 'Attempt 1: HTTP 401, retrying in 10s'
    The line 3 of output should equal 'Attempt 2: HTTP 000, retrying in 10s'
    The line 4 of output should equal 'Artifactory token accepted after 3 attempt(s)'
    The line 1 of contents of file "$CURL_CALLS" should include '--connect-timeout 10 --max-time 30 --header Authorization: Bearer federated-token https://repox-internal.dev.sonar.build/artifactory/api/system/version'
    The lines of contents of file "$CURL_CALLS" should equal 3
    The contents of file "$SLEEP_CALLS" should equal "sleep 10
sleep 10"
  End

  It 'uses a custom probe path'
    export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory/'
    export ARTIFACTORY_TOKEN_PROBE_PATH='api/storage/sonarsource-qa'
    export CURL_STATUSES='200'
    When run script shared/wait-for-artifactory-token.sh
    The status should be success
    The output should include 'at https://repox-internal.dev.sonar.build/artifactory/api/storage/sonarsource-qa'
  End

  It 'fails immediately on an unexpected status'
    export CURL_STATUSES='403'
    When run script shared/wait-for-artifactory-token.sh
    The status should be failure
    The line 2 of output should equal '::error title=Artifactory token federation::Unexpected response from https://repox-internal.dev.sonar.build/artifactory/api/system/version: HTTP 403'
    The lines of contents of file "$CURL_CALLS" should equal 1
  End

  It 'gives up after timeout / interval attempts'
    export CURL_STATUSES='401'
    When run script shared/wait-for-artifactory-token.sh
    The status should be failure
    The output should include '::error title=Artifactory token federation::Artifactory token was not accepted by https://repox-internal.dev.sonar.build/artifactory/api/system/version within 30s (last: HTTP 401)'
    The lines of contents of file "$CURL_CALLS" should equal 3
    The lines of contents of file "$SLEEP_CALLS" should equal 2
  End

  It 'probes at least once when the interval exceeds the timeout'
    export ARTIFACTORY_TOKEN_TIMEOUT_SECONDS=5
    export CURL_STATUSES='200'
    When run script shared/wait-for-artifactory-token.sh
    The status should be success
    The output should include 'up to 5s, probing every 10s'
    The line 1 of contents of file "$CURL_CALLS" should include '--connect-timeout 5 --max-time 5'
  End
End
