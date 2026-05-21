#!/bin/bash
# shellcheck disable=SC2317  # ShellSpec DSL (Describe/It/Mock/End) is invoked indirectly
eval "$(shellspec - -c) exit 1"

# Minimal environment variables
export NEXT_URL="https://next.sonarqube.com"
export NEXT_TOKEN="next-token"
export SQC_US_URL="https://sonarqube-us.example.com"
export SQC_US_TOKEN="sqc-us-token"
export SQC_EU_URL="https://sonarcloud.io"
export SQC_EU_TOKEN="sqc-eu-token"
export GITHUB_REPOSITORY="SonarSource/test-repo"
export GITHUB_OUTPUT=/dev/null
export POLL_TIMEOUT="300"
export POLL_INTERVAL="15"
export WORKING_DIRECTORY="."
export PROJECT_KEY_INPUT=""

# shellcheck disable=SC2329  # Functions invoked indirectly by BeforeEach/AfterEach
setup_main() {
  TEST_DIR=$(mktemp -d)
  export WORKING_DIRECTORY="$TEST_DIR"
  GITHUB_OUTPUT=$(mktemp)
  export GITHUB_OUTPUT
  return 0
}
# shellcheck disable=SC2329  # Functions invoked indirectly by BeforeEach/AfterEach
teardown_main() {
  rm -rf "$TEST_DIR"
  rm -f "$GITHUB_OUTPUT"
  return 0
}

Describe 'check-sca/check-sca.sh'
  It 'does not run main when sourced'
    When run source check-sca/check-sca.sh
    The status should be success
    The output should equal ""
  End
End

Describe 'discover_project_keys()'
  Include check-sca/check-sca.sh

  # shellcheck disable=SC2329  # Function invoked indirectly by BeforeEach
  setup() {
    TEST_DIR=$(mktemp -d)
    export WORKING_DIRECTORY="$TEST_DIR"
    export GITHUB_WORKSPACE="$TEST_DIR"
    return 0
  }
  # shellcheck disable=SC2329  # Function invoked indirectly by AfterEach
  teardown() {
    rm -rf "$TEST_DIR"
    unset GITHUB_WORKSPACE
    return 0
  }

  BeforeEach 'setup'
  AfterEach 'teardown'

  It 'uses explicit PROJECT_KEY_INPUT when provided'
    export PROJECT_KEY_INPUT="my-explicit-key"
    When call discover_project_keys
    The line 1 should equal "my-explicit-key"
  End

  It 'reads from .sonarlint/connectedMode.json'
    export PROJECT_KEY_INPUT=""
    mkdir -p "$TEST_DIR/.sonarlint"
    echo '{"projectKey": "FromSonarlint"}' > "$TEST_DIR/.sonarlint/connectedMode.json"
    Mock jq
      echo "FromSonarlint"
    End
    When call discover_project_keys
    The output should include "FromSonarlint"
  End

  It 'reads from .github/repo-metadata.yaml'
    export PROJECT_KEY_INPUT=""
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: FromMetadata\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call discover_project_keys
    The output should include "FromMetadata"
  End

  It 'reads from .github/repo-metadata.yml'
    export PROJECT_KEY_INPUT=""
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: FromYml\n' > "$TEST_DIR/.github/repo-metadata.yml"
    When call discover_project_keys
    The output should include "FromYml"
  End

  It 'prefers .yaml over .yml when both exist'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: FromYaml\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    printf 'check-sca:\n  project-key: FromYml\n' > "$TEST_DIR/.github/repo-metadata.yml"
    When call discover_project_keys
    The line 1 should equal "FromYaml"
  End

  It 'reads quoted values from .github/repo-metadata.yaml'
    export PROJECT_KEY_INPUT=""
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: "QuotedKey"\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call discover_project_keys
    The output should include "QuotedKey"
  End

  It 'ignores .github/repo-metadata.yaml when check-sca section is missing'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    mkdir -p "$TEST_DIR/.github"
    printf 'jira:\n  project-key: BUILD\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call discover_project_keys
    The output should equal ""
  End

  It 'prioritizes .github/repo-metadata.yaml over sonar-project.properties'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: FromMetadata\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    echo "sonar.projectKey=FromProperties" > "$TEST_DIR/sonar-project.properties"
    When call discover_project_keys
    The line 1 should equal "FromMetadata"
    The line 2 should equal "FromProperties"
  End

  It 'keeps both explicit input and .github/repo-metadata.yaml keys'
    export PROJECT_KEY_INPUT="explicit-key"
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: FromMetadata\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call discover_project_keys
    The line 1 should equal "explicit-key"
    The line 2 should equal "FromMetadata"
  End

  It 'reads .github/repo-metadata.yaml from repo root when working-directory is a subdirectory'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    export GITHUB_WORKSPACE="$TEST_DIR"
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: RootKey\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    mkdir -p "$TEST_DIR/services/my-app"
    export WORKING_DIRECTORY="$TEST_DIR/services/my-app"
    When call discover_project_keys
    The output should include "RootKey"
  End

  It 'reads from sonar-project.properties'
    export PROJECT_KEY_INPUT=""
    echo "sonar.projectKey=FromProperties" > "$TEST_DIR/sonar-project.properties"
    When call discover_project_keys
    The output should include "FromProperties"
  End

  It 'reads from pom.xml'
    export PROJECT_KEY_INPUT=""
    printf '<project>\n  <properties>\n    <sonar.projectKey>FromPom</sonar.projectKey>\n  </properties>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The output should include "FromPom"
  End

  It 'derives groupId:artifactId from pom.xml with project-level groupId'
    export PROJECT_KEY_INPUT=""
    printf '<project>\n  <parent>\n    <groupId>org.sonarsource.parent</groupId>\n    <artifactId>parent</artifactId>\n    <version>1.0</version>\n  </parent>\n  <groupId>org.sonarsource.plugins.cayc</groupId>\n  <artifactId>sonar-cayc-plugin</artifactId>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The output should include "org.sonarsource.plugins.cayc:sonar-cayc-plugin"
  End

  It 'derives groupId:artifactId from pom.xml with inherited parent groupId'
    export PROJECT_KEY_INPUT=""
    printf '<project>\n  <parent>\n    <groupId>org.jenkins-ci.plugins</groupId>\n    <artifactId>plugin</artifactId>\n    <version>4.0</version>\n  </parent>\n  <artifactId>sonar</artifactId>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The output should include "org.jenkins-ci.plugins:sonar"
  End

  It 'prefers sonar.projectKey over groupId:artifactId from pom.xml'
    export PROJECT_KEY_INPUT=""
    printf '<project>\n  <groupId>com.example</groupId>\n  <artifactId>my-app</artifactId>\n  <properties>\n    <sonar.projectKey>ExplicitKey</sonar.projectKey>\n  </properties>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The line 1 should equal "ExplicitKey"
    The line 2 should equal "com.example:my-app"
  End

  It 'trims whitespace when reading pom.xml project keys'
    export PROJECT_KEY_INPUT=""
    printf '<project>\n  <groupId>\n    com.example\n  </groupId>\n  <artifactId>\n    my-app\n  </artifactId>\n  <properties>\n    <sonar.projectKey>\n      ExplicitKey\n    </sonar.projectKey>\n  </properties>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The line 1 should equal "ExplicitKey"
    The line 2 should equal "com.example:my-app"
  End

  It 'does not derive Maven key when pom.xml has only parent block'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    printf '<project>\n  <parent>\n    <groupId>org.sonarsource.parent</groupId>\n    <artifactId>parent</artifactId>\n    <version>1.0</version>\n  </parent>\n</project>\n' \
      > "$TEST_DIR/pom.xml"
    When call discover_project_keys
    The output should not include "org.sonarsource.parent:parent"
    The output should equal ""
  End

  It 'reads from build.gradle'
    export PROJECT_KEY_INPUT=""
    printf 'sonar.projectKey = "FromGradle"\n' > "$TEST_DIR/build.gradle"
    When call discover_project_keys
    The output should include "FromGradle"
  End

  It 'reads from build.gradle.kts property syntax'
    export PROJECT_KEY_INPUT=""
    printf 'property("sonar.projectKey", "org.sonarsource.php:php")\n' > "$TEST_DIR/build.gradle.kts"
    When call discover_project_keys
    The output should include "org.sonarsource.php:php"
  End

  It 'derives key from GITHUB_REPOSITORY as fallback'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY="SonarSource/my-repo"
    When call discover_project_keys
    The output should include "SonarSource_my-repo"
  End

  It 'deduplicates keys'
    export PROJECT_KEY_INPUT="SonarSource_test-repo"
    export GITHUB_REPOSITORY="SonarSource/test-repo"
    When call discover_project_keys
    The lines of output should equal 1
    The line 1 should equal "SonarSource_test-repo"
  End

  It 'returns keys from multiple sources in priority order'
    export PROJECT_KEY_INPUT="explicit-key"
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: metadata-key\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    mkdir -p "$TEST_DIR/.sonarlint"
    echo '{"projectKey": "sonarlint-key"}' > "$TEST_DIR/.sonarlint/connectedMode.json"
    echo "sonar.projectKey=props-key" > "$TEST_DIR/sonar-project.properties"
    export GITHUB_REPOSITORY="SonarSource/test-repo"
    When call discover_project_keys
    The line 1 should equal "explicit-key"
    The line 2 should equal "metadata-key"
    The line 3 should equal "sonarlint-key"
    The line 4 should equal "props-key"
    The line 5 should equal "SonarSource_test-repo"
  End

  It 'returns empty when no sources available'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY=""
    When call discover_project_keys
    The output should equal ""
  End
End

Describe 'check_sca_metric()'
  Include check-sca/check-sca.sh

  Mock jq
    input=$(cat)
    if echo "$input" | grep -q '"sca_count_any_issue"'; then
      echo "$input" | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4
    fi
  End

  # shellcheck disable=SC2329  # Function invoked indirectly by BeforeEach
  setup() {
    RESULT_DIR=$(mktemp -d)
    return 0
  }
  # shellcheck disable=SC2329  # Function invoked indirectly by AfterEach
  teardown() {
    rm -rf "$RESULT_DIR"
    return 0
  }

  # shellcheck disable=SC2329  # Function invoked indirectly by ShellSpec assertions
  first_match_contents() {
    [[ -f "${RESULT_DIR}/match" ]] && cat "${RESULT_DIR}/match"
    return 0
  }

  BeforeEach 'setup'
  AfterEach 'teardown'

  It 'returns success when sca_count_any_issue metric is present'
    Mock curl
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"3"}]}}\n200'
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "good-key" "next" "$RESULT_DIR"
    The status should be success
    The result of "first_match_contents()" should equal "next:good-key"
  End

  It 'returns success when sca_count_any_issue value is 0'
    Mock curl
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"0"}]}}\n200'
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "zero-key" "sqc-eu" "$RESULT_DIR"
    The status should be success
    The result of "first_match_contents()" should equal "sqc-eu:zero-key"
  End

  It 'returns failure when measures array is empty'
    Mock curl
      printf '{"component":{"measures":[]}}\n200'
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "no-sca-key" "next" "$RESULT_DIR"
    The status should be failure
  End

  It 'returns failure on HTTP 404'
    Mock curl
      printf '{"errors":[{"msg":"Component not found"}]}\n404'
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "not-found" "next" "$RESULT_DIR"
    The status should be failure
  End

  It 'returns failure when curl fails'
    Mock curl
      return 1
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "bad-key" "next" "$RESULT_DIR"
    The status should be failure
  End

  It 'passes qualifiers to the API URL'
    Mock curl
      # Capture the URL argument (last positional param to curl)
      for arg; do :; done
      if echo "$arg" | grep -q 'pullRequest=42'; then
        printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"1"}]}}\n200'
      else
        printf '{"component":{"measures":[]}}\n200'
      fi
    End
    When call check_sca_metric "https://next.sonarqube.com" "token" "pr-key" "next" "$RESULT_DIR" "&pullRequest=42"
    The status should be success
    The result of "first_match_contents()" should equal "next:pr-key"
  End
End

Describe 'main() success'
  Mock curl
    printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"5"}]}}\n200'
  End

  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'succeeds when SCA metric is found on first attempt'
    export PROJECT_KEY_INPUT="SonarSource_test-repo"
    export GITHUB_REPOSITORY="SonarSource/test-repo"
    export POLL_TIMEOUT="300"
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include "SCA verified on"
    The output should include "for project key: SonarSource_test-repo"
    The contents of file "$GITHUB_OUTPUT" should include "sca-verified=true"
    The contents of file "$GITHUB_OUTPUT" should include "project-key=SonarSource_test-repo"
  End
End

Describe 'main() success via branch analysis'
  Mock curl
    # Return SCA data only when branch=main is in the URL
    for arg; do :; done
    if echo "$arg" | grep -q 'branch=main'; then
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"4"}]}}\n200'
    else
      printf '{"component":{"measures":[]}}\n200'
    fi
  End

  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'succeeds when SCA metric is found on a named branch'
    export PROJECT_KEY_INPUT="SonarSource_test-repo"
    export GITHUB_REPOSITORY="SonarSource/test-repo"
    export POLL_TIMEOUT="300"
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include "SCA verified on"
    The contents of file "$GITHUB_OUTPUT" should include "sca-verified=true"
  End
End

Describe 'main() success via PR analysis'
  Mock curl
    # Return SCA data only when pullRequest= is in the URL
    for arg; do :; done
    if echo "$arg" | grep -q 'pullRequest='; then
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"2"}]}}\n200'
    else
      printf '{"component":{"measures":[]}}\n200'
    fi
  End

  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'succeeds when SCA metric is found only on PR analysis'
    export PROJECT_KEY_INPUT="SonarSource_test-repo"
    export GITHUB_REPOSITORY="SonarSource/test-repo"
    export PULL_REQUEST="42"
    export POLL_TIMEOUT="300"
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include "SCA verified on"
    The output should include "PR #42"
    The contents of file "$GITHUB_OUTPUT" should include "sca-verified=true"
  End
End

Describe 'main() timeout'
  Mock curl
    printf '{"component":{"measures":[]}}\n200'
  End

  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'fails immediately when timeout is 0 and SCA metric is not found'
    export PROJECT_KEY_INPUT="my-project"
    export POLL_TIMEOUT="0"
    When run script check-sca/check-sca.sh
    The status should be failure
    The output should include "::group::Poll for SCA data"
    The stderr should include "::error title=SCA check timeout"
    The contents of file "$GITHUB_OUTPUT" should include "sca-verified=false"
  End
End
