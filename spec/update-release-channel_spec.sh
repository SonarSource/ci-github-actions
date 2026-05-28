#!/bin/bash
eval "$(shellspec - -c) exit 1"

export VERSION="0.9.0.977"
export CHANNEL="latest"
export PREFIX="Distribution"
export PRODUCT="sonarqube-cli"
export DRY_RUN="true"

setup() {
  GITHUB_OUTPUT=$(mktemp)
  GITHUB_STEP_SUMMARY=$(mktemp)
  export GITHUB_OUTPUT GITHUB_STEP_SUMMARY
  return 0
}

extract_body() {
  # The dry-run body line includes the generated JSON payload.
  local stdout_file="$1"
  sed -n 's/^Dry-run body: //p' "$stdout_file"
  return 0
}

Describe 'update-release-channel/update-release-channel.sh'
  BeforeEach 'setup'

  Describe 'dry-run happy path'
    It 'prints the planned PutObject and writes outputs'
      When run script update-release-channel/update-release-channel.sh
      The status should be success
      The output should include "Dry-run: aws s3api put-object"
      The output should include "--cache-control max-age=60"
      The output should include "--content-type application/json"
      The contents of file "$GITHUB_OUTPUT" should include "bucket=downloads-cdn-eu-central-1-prod"
      The contents of file "$GITHUB_OUTPUT" should include "key=Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "body={"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "update-release-channel"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "Distribution/sonarqube-cli/latest.json"
    End

    # Requires `check-jsonschema` on PATH (installed by the CI workflow).
    It 'produces a JSON body that validates against schema/v1.json'
      stdout_file=$(mktemp)
      bash update-release-channel/update-release-channel.sh > "$stdout_file"
      body_file=$(mktemp --suffix=.json)
      extract_body "$stdout_file" > "$body_file"
      When call check-jsonschema --schemafile update-release-channel/schema/v1.json "$body_file"
      The status should be success
      The output should include "ok"
    End
  End

  Describe 'validation failures'
    It 'rejects an invalid channel'
      export CHANNEL="foo"
      When run script update-release-channel/update-release-channel.sh
      The status should be failure
      The stderr should include "::error::Invalid channel 'foo'"
    End

    It 'rejects an invalid product (path traversal)'
      export PRODUCT="../escape"
      When run script update-release-channel/update-release-channel.sh
      The status should be failure
      The stderr should include "::error::Invalid product '../escape'"
    End

    It 'rejects an uppercase product'
      export PRODUCT="SonarQubeCLI"
      When run script update-release-channel/update-release-channel.sh
      The status should be failure
      The stderr should include "::error::Invalid product 'SonarQubeCLI'"
    End

    It 'rejects a prefix path-traversal attempt'
      export PREFIX="../sensitive"
      When run script update-release-channel/update-release-channel.sh
      The status should be failure
      The stderr should include "::error::Invalid prefix '../sensitive'"
    End
  End

  Describe 'custom prefix'
    It 'warns but succeeds when prefix is not Distribution'
      export PREFIX="NotDistribution"
      When run script update-release-channel/update-release-channel.sh
      The status should be success
      The stderr should include "::warning::Custom prefix 'NotDistribution'"
      The output should include "--key NotDistribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "key=NotDistribution/sonarqube-cli/latest.json"
    End
  End

  Describe 'non-dry-run path'
    Mock aws
      body_file=""
      while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == "--body" ]]; then
          body_file="$2"
          break
        fi
        shift
      done
      [[ -n "$body_file" ]] || exit 1
      [[ "$body_file" != "/dev/stdin" ]] || exit 1
      [[ -f "$body_file" ]] || exit 1
      grep -q '"version":"0.9.0.977"' "$body_file" || exit 1
      echo '{"ServerSideEncryption":"AES256"}'
    End

    It 'invokes aws s3api put-object and reports the URL'
      export DRY_RUN="false"
      When run script update-release-channel/update-release-channel.sh
      The status should be success
      The output should include "Wrote https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "body={"
    End
  End
End
