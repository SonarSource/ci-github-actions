#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock jf
  echo "jf $*"
End

Describe 'shared/generate-jfrog-summary.sh'
  setup() {
    JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR=$(mktemp -d)
    export JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR
    GITHUB_STEP_SUMMARY=$(mktemp)
    export GITHUB_STEP_SUMMARY
    return 0
  }
  cleanup() {
    rm -rf "$JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR"
    rm -f "$GITHUB_STEP_SUMMARY"
    return 0
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'does nothing when summary directory does not exist'
    When run script shared/generate-jfrog-summary.sh repox
    The status should be success
    The output should equal ""
    The contents of file "$GITHUB_STEP_SUMMARY" should equal ""
  End

  It 'does nothing when markdown.md is absent'
    mkdir -p "${JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR}/jfrog-command-summary"
    When run script shared/generate-jfrog-summary.sh repox
    The status should be success
    The line 1 should equal "jf config use repox"
    The line 2 should equal "jf generate-summary-markdown"
    The contents of file "$GITHUB_STEP_SUMMARY" should equal ""
  End

  It 'fails when server-id argument is missing'
    When run script shared/generate-jfrog-summary.sh
    The status should not be success
    The stderr should include "Usage: generate-jfrog-summary.sh"
  End

  Describe 'with markdown.md'
    setup_markdown() {
      jf_summary_dir="${JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR}/jfrog-command-summary"
      mkdir -p "$jf_summary_dir"
      cat > "${jf_summary_dir}/markdown.md" <<'EOF'
**sonarsource:my-lib:1.0.0**
<a href="url">link</a>
<pre>📦 my-repo-qa
└── 📁 my-lib
    └── 📄 my-lib-1.0.0.jar
</pre>
EOF
      return 0
    }
    Before 'setup_markdown'

    It 'uses the given server ID'
      When run script shared/generate-jfrog-summary.sh repox
      The status should be success
      The line 1 should equal "jf config use repox"
      The line 2 should equal "jf generate-summary-markdown"
    End

    It 'uses deploy server ID when specified'
      When run script shared/generate-jfrog-summary.sh deploy
      The status should be success
      The line 1 should equal "jf config use deploy"
    End

    It 'appends Published Modules details block to GITHUB_STEP_SUMMARY'
      When run script shared/generate-jfrog-summary.sh repox
      The status should be success
      The line 1 should equal "jf config use repox"
      The line 2 should equal "jf generate-summary-markdown"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "<details>"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "<summary>Published Modules</summary>"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "</details>"
    End

    It 'extracts bold module names as backtick list items'
      When run script shared/generate-jfrog-summary.sh repox
      The status should be success
      The line 1 should equal "jf config use repox"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "- \`sonarsource:my-lib:1.0.0\`"
    End

    It 'extracts multi-line pre blocks'
      When run script shared/generate-jfrog-summary.sh repox
      The status should be success
      The line 1 should equal "jf config use repox"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "<pre>"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "my-lib-1.0.0.jar"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "</pre>"
    End

    It 'skips inline pre tags'
      jf_summary_dir="${JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR}/jfrog-command-summary"
      printf '**mod:art:1.0**\n<pre>inline</pre>\n<pre>\nmulti\n</pre>\n' > "${jf_summary_dir}/markdown.md"
      When run script shared/generate-jfrog-summary.sh repox
      The status should be success
      The line 1 should equal "jf config use repox"
      The contents of file "$GITHUB_STEP_SUMMARY" should not include "<pre>inline</pre>"
      The contents of file "$GITHUB_STEP_SUMMARY" should include "multi"
    End
  End
End
