#!/usr/bin/env bash

set -euo pipefail

: "${JIRA_KEY:?JIRA_KEY is required}"
: "${BRANCH:?BRANCH is required}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${TICKET_TITLE:=$JIRA_KEY}"

pr_url=''
outcome='failed'

existing_pr="$(GH_TOKEN="$GITHUB_TOKEN" gh pr list --head "$BRANCH" --base "$DEFAULT_BRANCH" --state open --json url --jq '.[0].url // empty')"

if [[ -z "$(git status --porcelain)" ]]; then
  pr_url="$existing_pr"
  if [[ -n "$existing_pr" ]]; then
    outcome='success'
  else
    outcome='no_changes'
  fi
else
  git config user.name 'github-actions[bot]'
  git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
  git add -A
  git restore --staged .actions 2>/dev/null || true
  git commit -m "$JIRA_KEY: $TICKET_TITLE"
  git push origin "HEAD:$BRANCH"

  if [[ -n "$existing_pr" ]]; then
    pr_url="$existing_pr"
  else
    pr_url="$(GH_TOKEN="$GITHUB_TOKEN" gh pr create --draft --base "$DEFAULT_BRANCH" --head "$BRANCH" \
      --title "$JIRA_KEY: $TICKET_TITLE" \
      --body "Created by the Dev Agent workflow for $JIRA_KEY.")"
  fi
  outcome='success'
fi

{
  echo "pull-request-url=$pr_url"
  echo "outcome=$outcome"
} >> "$GITHUB_OUTPUT"
