#!/usr/bin/env bash

set -euo pipefail

: "${JIRA_KEY:?JIRA_KEY is required}"
: "${JIRA_USER:?JIRA_USER is required}"
: "${JIRA_TOKEN:?JIRA_TOKEN is required}"
: "${INSTRUCTIONS_FILE:=}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

if [[ ! "$JIRA_KEY" =~ ^[A-Z][A-Z0-9]+-[1-9][0-9]*$ ]]; then
  echo "jira-key must look like PROJECT-123" >&2
  exit 1
fi

if [[ -n "$INSTRUCTIONS_FILE" ]]; then
  if [[ "$INSTRUCTIONS_FILE" = /* || "$INSTRUCTIONS_FILE" == *".."* || ! -f "$INSTRUCTIONS_FILE" ]]; then
    echo "instructions-file must be a checked-in file inside the repository" >&2
    exit 1
  fi
  repository_instructions="$(<"$INSTRUCTIONS_FILE")"
else
  repository_instructions="No additional repository-specific instructions were supplied."
fi

work_dir="${RUNNER_TEMP:-/tmp}/dev-agent/${GITHUB_RUN_ID:-local}"
mkdir -p "$work_dir"

ticket_file="$work_dir/ticket.json"
curl --fail --silent --show-error \
  --user "$JIRA_USER:$JIRA_TOKEN" \
  --header 'Accept: application/json' \
  "https://sonarsource.atlassian.net/rest/api/3/issue/$JIRA_KEY?fields=summary,description&expand=renderedFields" \
  > "$ticket_file"

ticket_title="$(jq -r '.fields.summary // ""' "$ticket_file" | tr '\r\n' '  ')"
ticket_description="$(jq -r '.renderedFields.description // .fields.description // ""' "$ticket_file")"
branch="codex/$JIRA_KEY"
prompt_file="$work_dir/prompt.md"

while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    '{{JIRA_TICKET}}')
      printf '%s\n\n%s\n' "$ticket_title" "$ticket_description"
      ;;
    '{{REPOSITORY_INSTRUCTIONS}}')
      printf '%s\n' "$repository_instructions"
      ;;
    *)
      printf '%s\n' "$line"
      ;;
  esac
done < "${ACTION_PATH}/prompt.md" > "$prompt_file"

{
  echo "branch=$branch"
  echo "prompt-file=$prompt_file"
  echo "ticket-title=$ticket_title"
  echo "ticket-url=https://sonarsource.atlassian.net/browse/$JIRA_KEY"
} >> "$GITHUB_OUTPUT"
