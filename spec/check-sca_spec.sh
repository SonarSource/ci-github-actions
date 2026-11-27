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
  export GITHUB_WORKSPACE="$TEST_DIR"
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

  It 'falls back to GITHUB_REPOSITORY when sonar-project.properties lacks sonar.projectKey'
    export PROJECT_KEY_INPUT=""
    export GITHUB_REPOSITORY="SonarSource/my-repo"
    echo "sonar.python.version=3.13" > "$TEST_DIR/sonar-project.properties"
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

Describe 'main() timeout diagnosis'
  # One poll round (timeout 1s, interval 1s) then time out, so the diagnosis
  # reflects what the probes observed.
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  Describe 'when the project is found but has no SCA data (HTTP 200, empty measures)'
    Mock curl
      printf '{"component":{"measures":[]}}\n200'
    End

    It 'reports that the project was found but no SCA data was published'
      export PROJECT_KEY_INPUT="my-project"
      export GITHUB_REPOSITORY="SonarSource/diag-test"
      export POLL_TIMEOUT="1"
      export POLL_INTERVAL="1"
      When run script check-sca/check-sca.sh
      The status should be failure
      The stderr should include "::error title=SCA check timeout"
      The stderr should include "project found but no SCA data"
      The output should include "Diagnosis:"
      The output should include "my-project"
      The contents of file "$GITHUB_OUTPUT" should include "sca-verified=false"
    End
  End

  Describe 'when no matching project is found (HTTP 404)'
    Mock curl
      printf '{"errors":[{"msg":"Component not found"}]}\n404'
    End

    It 'reports a missing project and points to the project-key config'
      export PROJECT_KEY_INPUT="wrong-key"
      export GITHUB_REPOSITORY="SonarSource/diag-test"
      export POLL_TIMEOUT="1"
      export POLL_INTERVAL="1"
      When run script check-sca/check-sca.sh
      The status should be failure
      The stderr should include "no matching SonarQube project was found"
      The output should include "repo-metadata.yaml"
      The output should include "wrong-key"
      The contents of file "$GITHUB_OUTPUT" should include "sca-verified=false"
    End
  End

  Describe 'when the API is unreachable or errors (HTTP 5xx)'
    Mock curl
      printf '{"errors":[{"msg":"server error"}]}\n500'
    End

    It 'reports that the SonarQube API was unreachable or returned errors'
      export PROJECT_KEY_INPUT="my-project"
      export GITHUB_REPOSITORY="SonarSource/diag-test"
      export POLL_TIMEOUT="1"
      export POLL_INTERVAL="1"
      When run script check-sca/check-sca.sh
      The status should be failure
      The stderr should include "API was unreachable or returned errors"
      The output should include "Diagnosis:"
      The contents of file "$GITHUB_OUTPUT" should include "sca-verified=false"
    End
  End

  Describe 'when only the hosting platform errors (API_ERROR mixed with routine 404s)'
    # A project lives on one platform: the hosting platform (next) errors with a
    # 5xx while the other two return their routine 404 (NOT_FOUND). The real error
    # must not be masked by that expected 404 noise.
    Mock curl
      for arg; do :; done
      if echo "$arg" | grep -q 'next.sonarqube.com'; then
        printf '{"errors":[{"msg":"server error"}]}\n503'
      else
        printf '{"errors":[{"msg":"Component not found"}]}\n404'
      fi
    End

    It 'surfaces the API error rather than "no matching project"'
      export PROJECT_KEY_INPUT="my-project"
      export GITHUB_REPOSITORY="SonarSource/diag-test"
      export POLL_TIMEOUT="1"
      export POLL_INTERVAL="1"
      When run script check-sca/check-sca.sh
      The status should be failure
      The stderr should include "API was unreachable or returned errors"
      The stderr should not include "no matching SonarQube project"
      The output should include "Diagnosis:"
      The contents of file "$GITHUB_OUTPUT" should include "sca-verified=false"
    End
  End
End

Describe 'explicit monorepo configuration'
  Include check-sca/check-sca.sh
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'trims and deduplicates comma- and newline-separated input'
    PROJECT_KEY_INPUT=$' first ,second\n\nfirst , second '
    PROJECT_KEY_MODE_INPUT=all
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond'
    The variable PROJECT_KEY_MODE should equal all
  End

  It 'uses metadata lists and options when action inputs are empty'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key:\n    - "first"\n    - second\n    - third\n  project-key-mode: all\n  repository-key-fallback: false\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond\nthird'
    The variable REPOSITORY_KEY_FALLBACK should equal false
    The variable PROJECT_KEY_MODE should equal all
  End

  It 'lets action keys and settings override metadata'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key:\n    - ignored\n  project-key-mode: all\n  repository-key-fallback: false\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    PROJECT_KEY_INPUT=selected,scalar
    PROJECT_KEY_MODE_INPUT=any
    export REPOSITORY_KEY_FALLBACK_INPUT=true
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'selected\nscalar'
    The variable REPOSITORY_KEY_FALLBACK should equal true
    The variable PROJECT_KEY_MODE should equal any
  End

  It 'rejects an invalid mode before polling'
    PROJECT_KEY_MODE_INPUT=every
    When call resolve_configuration
    The status should be failure
    The stderr should include 'project-key-mode must be any or all'
  End

  It 'rejects an invalid fallback option'
    export REPOSITORY_KEY_FALLBACK_INPUT=no
    When call resolve_configuration
    The status should be failure
    The stderr should include 'repository-key-fallback must be true or false'
  End

  It 'requires explicit keys for all mode'
    PROJECT_KEY_MODE_INPUT=all
    When call resolve_configuration
    The status should be failure
    The stderr should include 'Explicit project keys are required'
  End

  It 'requires explicit keys when repository fallback is disabled'
    export REPOSITORY_KEY_FALLBACK_INPUT=false
    When call resolve_configuration
    The status should be failure
    The stderr should include 'Explicit project keys are required'
  End

  It 'does not discover aliases in all mode'
    export PROJECT_KEY_MODE=all
    export EXPLICIT_KEYS=$'first\nsecond'
    echo 'sonar.projectKey=alias' > "$TEST_DIR/sonar-project.properties"
    When call discover_project_keys
    The output should equal $'first\nsecond'
  End

  It 'omits the repository-name key when fallback is disabled'
    export REPOSITORY_KEY_FALLBACK=false
    PROJECT_KEY_INPUT=explicit
    When call discover_project_keys
    The output should equal explicit
  End
End

Describe 'monorepo polling'
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  Mock curl
    for arg; do :; done
    if [[ "$arg" == *component=first\&* && "$arg" == *next.sonarqube.com* ]] ||
       [[ "$arg" == *component=second\&* && "$arg" == *sonarcloud.io* && "${SECOND_READY:-true}" == true ]]; then
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"0"}]}}\n200'
    else
      printf '{"component":{"measures":[]}}\n200'
    fi
  End

  It 'requires all keys and reports different platforms with zero measures'
    export PROJECT_KEY_INPUT=$'first\nsecond'
    export PROJECT_KEY_MODE_INPUT=all
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include 'for project key: first'
    The output should include 'for project key: second'
    The contents of file "$GITHUB_OUTPUT" should include 'sca-verified=true'
    The contents of file "$GITHUB_OUTPUT" should include 'verified-projects=[{"project-key":"first","platform":"next"},{"project-key":"second","platform":"sqc-eu"}]'
    The contents of file "$GITHUB_OUTPUT" should not include $'\nproject-key='
  End

  It 'fails on partial success and diagnoses only the unresolved key'
    export PROJECT_KEY_INPUT=$'first\nsecond'
    export PROJECT_KEY_MODE_INPUT=all
    export SECOND_READY=false POLL_TIMEOUT=2 POLL_INTERVAL=2
    When run script check-sca/check-sca.sh
    The status should be failure
    The stderr should include 'project found but no SCA data'
    The output should include 'Unresolved project: second'
    The output should not include 'Unresolved project: first'
    The contents of file "$GITHUB_OUTPUT" should include 'unresolved-projects=["second"]'
    The contents of file "$GITHUB_OUTPUT" should not include 'sca-verified=true'
  End

  It 'keeps legacy any success with a partial explicit list'
    export PROJECT_KEY_INPUT=$'first\nsecond'
    export SECOND_READY=false
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include 'SCA verified on next'
    The contents of file "$GITHUB_OUTPUT" should include 'project-key=first'
    The contents of file "$GITHUB_OUTPUT" should include 'unresolved-projects=[]'
    The contents of file "$GITHUB_OUTPUT" should include 'project-diagnoses=[]'
  End
End

Describe 'monorepo successes across polling rounds'
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'
  Mock curl
    for arg; do :; done
    if [[ "$arg" == *component=first\&* && ! -f "$WORKING_DIRECTORY/round-two" ]] ||
       [[ "$arg" == *component=second\&* && -f "$WORKING_DIRECTORY/round-two" ]]; then
      printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"1"}]}}\n200'
    else
      printf '{"component":{"measures":[]}}\n200'
    fi
  End
  Mock sleep
    touch "$WORKING_DIRECTORY/round-two"
  End
  It 'retains first-round successes when only the second key succeeds later'
    export PROJECT_KEY_INPUT=$'first\nsecond'
    export PROJECT_KEY_MODE_INPUT=all
    export POLL_TIMEOUT=30
    When run script check-sca/check-sca.sh
    The status should be success
    The output should include 'Poll attempt 2'
    The contents of file "$GITHUB_OUTPUT" should include 'sca-verified=true'
    The contents of file "$GITHUB_OUTPUT" should include 'unresolved-projects=[]'
  End
End

Describe 'any-mode timeout with discovered aliases'
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'
  Mock curl
    for arg; do :; done
    if [[ "$arg" == *component=explicit\&* ]]; then
      printf '{"component":{"measures":[]}}\n200'
    else
      printf '{"errors":[{"msg":"not found"}]}\n404'
    fi
  End
  It 'reports one combined diagnosis without a misleading alias error'
    export PROJECT_KEY_INPUT=explicit
    export POLL_TIMEOUT=3 POLL_INTERVAL=3
    When run script check-sca/check-sca.sh
    The status should be failure
    The stderr should include 'project found but no SCA data'
    The stderr should not include 'no matching SonarQube project'
    The lines of stderr should equal 1
    The output should include 'Diagnosis:'
    The contents of file "$GITHUB_OUTPUT" should include '"diagnosis":"MEASURE_MISSING"'
  End
End

Describe 'diagnosis retention across polling rounds'
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'
  Mock date
    if [[ -f "$WORKING_DIRECTORY/finished" ]]; then
      echo 3
    elif [[ -f "$WORKING_DIRECTORY/second-round" ]]; then
      echo 1
    else
      echo 0
    fi
  End
  Mock sleep
    if [[ -f "$WORKING_DIRECTORY/second-round" ]]; then
      touch "$WORKING_DIRECTORY/finished"
    else
      touch "$WORKING_DIRECTORY/second-round"
    fi
  End
  Mock curl
    if [[ -f "$WORKING_DIRECTORY/second-round" ]]; then
      printf '{"errors":[{"msg":"not found"}]}\n404'
    else
      printf '{"component":{"measures":[]}}\n200'
    fi
  End
  It 'keeps the most informative diagnosis after old probe files are discarded'
    export PROJECT_KEY_INPUT=explicit PROJECT_KEY_MODE_INPUT=all
    export POLL_TIMEOUT=3
    When run script check-sca/check-sca.sh
    The status should be failure
    The output should include 'Poll attempt 2'
    The stderr should include 'project found but no SCA data'
    The stderr should not include 'no matching SonarQube project'
    The contents of file "$GITHUB_OUTPUT" should include 'project-diagnoses=[{"project-key":"explicit","diagnosis":"MEASURE_MISSING"}]'
  End
End

Describe 'project-key metadata formats'
  Include check-sca/check-sca.sh
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  It 'ignores comments between metadata sequence entries'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key:\n    - first\n    # second capability\n    - second\n  project-key-mode: all\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond'
  End

  It 'accepts compact sequences and stops at the next metadata setting'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key:\n  - first\n  # second capability\n  - second\n  project-key-mode: all\n  unrelated:\n    - ignored\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond'
  End

  It 'accepts a comma-separated scalar'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: "first, second, first"\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond'
  End

  It 'accepts newline-separated literal metadata'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: |\n    first\n    second\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be success
    The variable EXPLICIT_KEYS should equal $'first\nsecond'
  End

  It 'rejects the removed plural metadata setting rather than falling back'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-keys: [first, second]\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be failure
    The stderr should include 'Use check-sca.project-key instead of project-keys'
  End

  It 'rejects unsupported flow-style metadata rather than falling back'
    mkdir -p "$TEST_DIR/.github"
    printf 'check-sca:\n  project-key: [first, second]\n' > "$TEST_DIR/.github/repo-metadata.yaml"
    When call resolve_configuration
    The status should be failure
    The stderr should include 'Use a scalar or block sequence'
  End
End

Describe 'atomic result publication failures'
  Include check-sca/check-sca.sh
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'
  Mock curl
    printf '{"component":{"measures":[{"metric":"sca_count_any_issue","value":"0"}]}}\n200'
  End
  Mock ln
    return 1
  End
  It 'reports a failed link when no complete match exists'
    When call check_sca_metric 'https://example.com' token explicit next "$TEST_DIR"
    The status should equal 2
    The stderr should include 'Could not publish the SCA result'
    The path "$TEST_DIR/match" should not be exist
  End
  It 'accepts a complete match published by another probe'
    printf '%s' 'next:explicit' > "$TEST_DIR/match"
    When call check_sca_metric 'https://example.com' token explicit next "$TEST_DIR"
    The status should be success
    The contents of file "$TEST_DIR/match" should equal 'next:explicit'
  End
End

Describe 'bounded concurrent probes'
  Include check-sca/check-sca.sh
  BeforeEach 'setup_main'
  AfterEach 'teardown_main'

  # shellcheck disable=SC2329  # Invoked by main in the test subprocess
  check_sca_metric() {
    local result_dir="$5" active
    touch "$TEST_DIR/active/$BASHPID"
    active=("$TEST_DIR/active/"*)
    if [[ ${#active[@]} -gt 16 ]]; then
      touch "$TEST_DIR/over-limit"
    fi
    sleep 0.1
    printf '%s' "next:$3" > "$result_dir/match"
    rm "$TEST_DIR/active/$BASHPID"
  }

  It 'limits active probes while completing every required project'
    export PROJECT_KEY_INPUT='first,second,third,fourth'
    export PROJECT_KEY_MODE_INPUT=all PULL_REQUEST=42 POLL_TIMEOUT=300
    mkdir "$TEST_DIR/active"
    When run main
    The status should be success
    The output should include 'SCA verified on next for project key: fourth'
    The path "$TEST_DIR/over-limit" should not be exist
    The contents of file "$GITHUB_OUTPUT" should include 'sca-verified=true'
  End
End
