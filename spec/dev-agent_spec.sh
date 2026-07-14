#!/bin/bash
eval "$(shellspec - -c) exit 1"

export ACTION_PATH="$SHELLSPEC_PROJECT_ROOT/dev-agent"
export GITHUB_OUTPUT="$SHELLSPEC_TMPBASE/output"
export INSTRUCTIONS_FILE=''
export JIRA_KEY='not-a-jira-key'
export JIRA_TOKEN='token'
export JIRA_USER='user'

Describe 'Dev Agent'
  It 'rejects an invalid Jira key before requesting a ticket'
    When run script dev-agent/prepare.sh
    The status should be failure
    The stderr should include 'jira-key must look like PROJECT-123'
  End
End
