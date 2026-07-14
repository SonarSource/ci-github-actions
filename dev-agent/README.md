# Dev Agent

Dev Agent turns an explicitly supplied Jira ticket into a draft pull request using Codex.
The caller must check out its repository and grant `id-token: write`, `contents: write`, and
`pull-requests: write` permissions.

```yaml
- uses: SonarSource/ci-github-actions/dev-agent@<reviewed-sha>
  with:
    jira-key: ${{ inputs.jira-key }}
    instructions-file: .github/dev-agent-instructions.md
    slack-channel: test_jd
    openai-api-key: ${{ secrets.OPENAI_API_KEY_TEMP }}
    github-token: ${{ github.token }}
```

The Action uses `codex/<JIRA-KEY>` as the generated branch and reuses an existing open draft pull
request for that branch. Jira ticket text and repository instructions are treated as untrusted input.
It configures npm through Repox before starting Codex, and never merges, deploys, or transitions Jira
issues. Codex runs with the pinned `gpt-5.6-terra` model. The Slack bot must have `chat:write` and be
a member of the configured channel. Codex uses `danger-full-access` on the ephemeral runner while the
Action retains its default `drop-sudo` safety strategy.
