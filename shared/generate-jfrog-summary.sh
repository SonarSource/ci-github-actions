#!/bin/bash
# Generate JFrog CLI build summary and append Published Modules to GitHub step summary.
#
# Usage: generate-jfrog-summary.sh <jf-server-id>
# Arguments:
#   jf-server-id: JFrog CLI server ID to use (e.g. 'repox' or 'deploy')
# GitHub Actions auto-provided:
#   JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR: directory where JFrog CLI writes summary data
#   GITHUB_STEP_SUMMARY: path to the GitHub step summary file

set -euo pipefail

: "${JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR:?}" "${GITHUB_STEP_SUMMARY:?}"

jf_server_id="${1:?Usage: generate-jfrog-summary.sh <jf-server-id>}"
jf_summary_dir="${JFROG_CLI_COMMAND_SUMMARY_OUTPUT_DIR}/jfrog-command-summary"

if [[ -d "$jf_summary_dir" ]]; then
  jf config use "$jf_server_id"
  jf generate-summary-markdown || true
  if [[ -f "${jf_summary_dir}/markdown.md" ]]; then
    # shellcheck disable=SC2129  # individual redirects needed for kcov instrumentation
    printf '\n<details>\n<summary>Published Modules</summary>\n\n' >> "$GITHUB_STEP_SUMMARY"
    # shellcheck disable=SC2016  # backticks in sed replacement are literal, not shell expansion
    sed -n 's/^\*\*\([^*][^*]*\)\*\*$/- `\1`/p' "${jf_summary_dir}/markdown.md" >> "$GITHUB_STEP_SUMMARY"
    printf '\n' >> "$GITHUB_STEP_SUMMARY"
    awk 'index($0,"<pre>") && !index($0,"</pre>"){p=1} p{print} index($0,"</pre>"){p=0}' "${jf_summary_dir}/markdown.md" >> "$GITHUB_STEP_SUMMARY"
    echo "</details>" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
