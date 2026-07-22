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
      The output should include "--cache-control 'no-cache, no-store, max-age=0'"
      The output should include "--content-type application/json"
      The output should include "--key Distribution/sonarqube-cli/latest.version"
      The output should include "--content-type text/plain"
      The output should include "Dry-run version body: 0.9.0.977"
      The contents of file "$GITHUB_OUTPUT" should include "bucket=downloads-cdn-eu-central-1-prod"
      The contents of file "$GITHUB_OUTPUT" should include "key=Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "body={"
      The contents of file "$GITHUB_OUTPUT" should include "version-key=Distribution/sonarqube-cli/latest.version"
      The contents of file "$GITHUB_OUTPUT" should include "version-url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.version"
      The contents of file "$GITHUB_OUTPUT" should include "version=0.9.0.977"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "update-release-channel"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_STEP_SUMMARY" should not include "Distribution/sonarqube-cli/latest.version"
    End

    # Requires `check-jsonschema` on PATH (installed by the CI workflow).
    It 'produces a JSON body that validates against schema/v1.json'
      stdout_file=$(mktemp)
      bash update-release-channel/update-release-channel.sh > "$stdout_file"
      body_file=$(mktemp)
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
      The contents of file "$GITHUB_OUTPUT" should include "version-key=NotDistribution/sonarqube-cli/latest.version"
    End
  End

  Describe 'non-dry-run path'
    Mock aws
      body_file=""
      content_type=""
      key=""
      while [[ "$#" -gt 0 ]]; do
        case "$1" in
          --body)
            body_file="$2"
            shift 2
            ;;
          --content-type)
            content_type="$2"
            shift 2
            ;;
          --key)
            key="$2"
            shift 2
            ;;
          *)
            shift
            ;;
        esac
      done
      [[ -n "$body_file" ]] || exit 1
      [[ -n "$content_type" ]] || exit 1
      [[ -n "$key" ]] || exit 1
      [[ "$body_file" != "/dev/stdin" ]] || exit 1
      [[ -f "$body_file" ]] || exit 1
      case "$key" in
        "Distribution/sonarqube-cli/latest.json")
          [[ "$content_type" == "application/json" ]] || exit 1
          grep -q '"version":"0.9.0.977"' "$body_file" || exit 1
          ;;
        "Distribution/sonarqube-cli/latest.version")
          [[ "$content_type" == "text/plain" ]] || exit 1
          [[ "$(cat "$body_file")" == "0.9.0.977" ]] || exit 1
          ;;
        *)
          exit 1
          ;;
      esac
      echo '{"ServerSideEncryption":"AES256"}'
    End

    It 'invokes aws s3api put-object and reports the URL'
      export DRY_RUN="false"
      When run script update-release-channel/update-release-channel.sh
      The status should be success
      The output should include "Wrote https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The output should include "Wrote https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.version"
      The contents of file "$GITHUB_OUTPUT" should include "url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.json"
      The contents of file "$GITHUB_OUTPUT" should include "body={"
      The contents of file "$GITHUB_OUTPUT" should include "version-url=https://binaries.sonarsource.com/Distribution/sonarqube-cli/latest.version"
      The contents of file "$GITHUB_OUTPUT" should include "version=0.9.0.977"
    End
  End
End
