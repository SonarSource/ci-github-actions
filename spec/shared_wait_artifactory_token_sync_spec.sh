#!/usr/bin/env bash
# shellcheck disable=SC2317  # ShellSpec DSL (Describe/It/Mock/End) is invoked indirectly
eval "$(shellspec - -c) exit 1"

Describe 'shared/wait_artifactory_token_sync.sh'
  It 'does not run main when sourced'
    When run source shared/wait_artifactory_token_sync.sh
    The status should be success
    The lines of output should equal 0
    The lines of error should equal 0
  End
End

Include shared/wait_artifactory_token_sync.sh

Describe 'is_saas_repox()'
  It 'detects jfrog.io SaaS URLs'
    When call is_saas_repox 'https://repox.jfrog.io'
    The status should be success
  End

  It 'does not treat edge URLs as SaaS'
    When call is_saas_repox 'https://repox-internal.dev.sonar.build'
    The status should be failure
  End
End

Describe 'require_artifactory_credentials()'
  It 'fails when credentials are missing'
    unset ARTIFACTORY_URL ARTIFACTORY_USERNAME ARTIFACTORY_ACCESS_TOKEN
    When call require_artifactory_credentials
    The status should be failure
    The stderr should include 'Missing Artifactory credentials'
  End

  It 'succeeds when credentials are set'
    export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
    export ARTIFACTORY_USERNAME='user'
    export ARTIFACTORY_ACCESS_TOKEN='token'
    When call require_artifactory_credentials
    The status should be success
  End
End

Describe 'check_artifactory_token()'
  Mock curl
    echo -n '200'
  End

  It 'returns the curl http code'
    export ARTIFACTORY_USERNAME='user'
    export ARTIFACTORY_ACCESS_TOKEN='token'
    When call check_artifactory_token 'https://example/artifactory/api/storage/sonarsource-qa'
    The status should be success
    The output should equal '200'
  End
End

Describe 'wait_for_artifactory_token_sync()'
  Describe 'SaaS skip'
    It 'skips when REPOX_URL is jfrog.io'
      export REPOX_URL='https://repox.jfrog.io'
      unset ARTIFACTORY_URL ARTIFACTORY_USERNAME ARTIFACTORY_ACCESS_TOKEN
      When call wait_for_artifactory_token_sync
      The status should be success
      The output should include 'Skipping token sync wait for SaaS Repox'
    End
  End

  Describe 'missing credentials on edge'
    It 'fails when edge URL has no credentials'
      export REPOX_URL='https://repox-internal.dev.sonar.build'
      unset ARTIFACTORY_URL ARTIFACTORY_USERNAME ARTIFACTORY_ACCESS_TOKEN
      When call wait_for_artifactory_token_sync
      The status should be failure
      The stderr should include 'Missing Artifactory credentials'
    End
  End

  Describe 'successful sync'
    Mock curl
      echo -n '200'
    End
    Mock sleep
      :
    End

    It 'returns success on first HTTP 200'
      export REPOX_URL='https://repox-internal.dev.sonar.build'
      export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
      export ARTIFACTORY_USERNAME='user'
      export ARTIFACTORY_ACCESS_TOKEN='token'
      When call wait_for_artifactory_token_sync
      The status should be success
      The output should include 'Artifactory accepted credentials after 1 attempt(s)'
    End
  End

  Describe 'retry then success'
    setup_retry() {
      CURL_ATTEMPT_FILE=$(mktemp)
      echo 0 > "$CURL_ATTEMPT_FILE"
      export CURL_ATTEMPT_FILE
      return 0
    }
    cleanup_retry() {
      rm -f "$CURL_ATTEMPT_FILE"
      return 0
    }
    Before 'setup_retry'
    After 'cleanup_retry'

    Mock curl
      count=$(cat "$CURL_ATTEMPT_FILE")
      count=$((count + 1))
      echo "$count" > "$CURL_ATTEMPT_FILE"
      if (( count < 2 )); then
        echo -n '401'
      else
        echo -n '200'
      fi
    End
    Mock sleep
      :
    End

    It 'retries until HTTP 200'
      export REPOX_URL='https://repox-internal.dev.sonar.build'
      export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
      export ARTIFACTORY_USERNAME='user'
      export ARTIFACTORY_ACCESS_TOKEN='token'
      export ARTIFACTORY_TOKEN_SYNC_MAX_ATTEMPTS=5
      export ARTIFACTORY_TOKEN_SYNC_SLEEP_SECONDS=0
      When call wait_for_artifactory_token_sync
      The status should be success
      The output should include 'HTTP 401'
      The output should include 'Artifactory accepted credentials after 2 attempt(s)'
    End
  End

  Describe 'timeout'
    Mock curl
      echo -n '401'
    End
    Mock sleep
      :
    End

    It 'fails after max attempts'
      export REPOX_URL='https://repox-internal.dev.sonar.build'
      export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
      export ARTIFACTORY_USERNAME='user'
      export ARTIFACTORY_ACCESS_TOKEN='token'
      export ARTIFACTORY_TOKEN_SYNC_MAX_ATTEMPTS=2
      export ARTIFACTORY_TOKEN_SYNC_SLEEP_SECONDS=0
      When call wait_for_artifactory_token_sync
      The status should be failure
      The stderr should include 'Artifactory token sync timeout'
      The output should include 'HTTP 401'
    End
  End
End

Describe 'main()'
  Mock curl
    echo -n '200'
  End

  It 'delegates to wait_for_artifactory_token_sync'
    export REPOX_URL='https://repox-internal.dev.sonar.build'
    export ARTIFACTORY_URL='https://repox-internal.dev.sonar.build/artifactory'
    export ARTIFACTORY_USERNAME='user'
    export ARTIFACTORY_ACCESS_TOKEN='token'
    When call main
    The status should be success
    The output should include 'Artifactory accepted credentials'
  End
End

Describe 'script execution'
  Mock curl
    echo -n '200'
  End

  It 'runs successfully as a script'
    export REPOX_URL='https://repox.jfrog.io'
    When run script shared/wait_artifactory_token_sync.sh
    The status should be success
    The output should include 'Skipping token sync wait for SaaS Repox'
  End
End
