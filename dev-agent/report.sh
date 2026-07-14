#!/usr/bin/env bash

set -euo pipefail

: "${JIRA_KEY:?JIRA_KEY is required}"
: "${JIRA_USER:?JIRA_USER is required}"
: "${JIRA_TOKEN:?JIRA_TOKEN is required}"
: "${SLACK_TOKEN:?SLACK_TOKEN is required}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL is required}"

case "${OUTCOME:-failed}" in
  success) status='created or updated a draft pull request' ;;
  no_changes) status='completed without a new change to publish' ;;
  *) status='did not complete successfully' ;;
esac

message="Dev Agent $status for $JIRA_KEY. Workflow: $WORKFLOW_URL"
if [[ -n "${PULL_REQUEST_URL:-}" ]]; then
  message="$message Pull request: $PULL_REQUEST_URL"
fi

jira_body="$(jq -n --arg message "$message" '{body: {type: "doc", version: 1, content: [{type: "paragraph", content: [{type: "text", text: $message}]}]}}')"
slack_body="$(jq -n --arg channel "$SLACK_CHANNEL" --arg text "$message" '{channel: $channel, text: $text}')"

curl --fail --silent --show-error \
  --user "$JIRA_USER:$JIRA_TOKEN" \
  --header 'Content-Type: application/json' \
  --request POST \
  --data "$jira_body" \
  "https://sonarsource.atlassian.net/rest/api/3/issue/$JIRA_KEY/comment"

slack_response="$(mktemp)"
slack_status="$(curl --silent --show-error --output "$slack_response" --write-out '%{http_code}' \
  --header "Authorization: Bearer $SLACK_TOKEN" \
  --header 'Content-Type: application/json; charset=utf-8' \
  --data "$slack_body" \
  https://slack.com/api/chat.postMessage)"

if ! jq -e '.ok == true' "$slack_response" >/dev/null; then
  slack_error="$(jq -r '.error // "unknown_error"' "$slack_response")"
  echo "::error title=Slack notification failed::HTTP $slack_status: $slack_error" >&2
  exit 1
fi
