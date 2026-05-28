# `update-release-channel`

Maintain per-channel JSON pointer files on `binaries.sonarsource.com` so consumers can discover the currently published
version for each release channel of a product.

The action writes one JSON file per channel (atomic per channel, single S3 `PutObject`) at
`<prefix>/<product>/<channel>.json`. The body follows the [v1 schema](./schema/v1.json); see
[schema/README.md](./schema/README.md) for the field contract.

Lifecycle operations like rollback, delayed promotion, and backfill are first-class — they're a single
`workflow_dispatch` invocation away, without re-running the release pipeline.

## Requirements

### Required GitHub Permissions

- `id-token: write`
- `contents: read`

### Required Vault Permissions

- `development/aws/sts/downloads`: STS credentials to write to `s3://downloads-cdn-eu-central-1-prod`. This is the same
  preset already provisioned for `SonarSource/gh-action_release`.

### Other Dependencies

The action installs the AWS CLI on demand via `mise` — no other tooling needs to be pre-installed on the runner.

## Usage

### As a release-workflow follow-up job (automated)

Append an `update-channel` job to the release workflow so the `latest` channel is promoted automatically after a
successful publish.

```yaml
jobs:
  release:
    uses: SonarSource/gh-action_release/.github/workflows/main.yaml@7.0.1
    with: { ... }

  update-channel:
    needs: release
    if: ${{ !inputs.dryRun }}
    runs-on: sonar-xs
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/update-release-channel@v1
        with:
          version: ${{ inputs.version }}
          # channel defaults to "latest"; prefix to "Distribution"; product to the repo name.
```

### As a standalone `workflow_dispatch` (manual ops)

Add a separate workflow for rollback, delayed promotion, backfill, and channel migration. Reference the
`release-channel-admin` GitHub Environment so every manual write is reviewed (see
[Required GitHub Environment](#required-github-environment)).

```yaml
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      channel: { required: true, type: choice, options: [stable, beta, rc, dogfood] }

jobs:
  update-channel:
    runs-on: sonar-xs
    environment: release-channel-admin
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/update-release-channel@v1
        with:
          version: ${{ inputs.version }}
          channel: ${{ inputs.channel }}
```

## Inputs

| Input     | Description                                                                                                | Default                               |
|-----------|------------------------------------------------------------------------------------------------------------|---------------------------------------|
| `version` | Version the channel should point at (e.g. `0.9.0.977`). Required.                                          | —                                     |
| `channel` | Release channel name. One of `latest`, `stable`, `beta`, `rc`, `dogfood`.                                  | `latest`                              |
| `prefix`  | S3 key prefix under the bucket. Other values warn but are accepted.                                        | `Distribution`                        |
| `product` | Product folder name on S3. Set explicitly when the S3 folder differs from the GitHub repo name.            | `${{ github.event.repository.name }}` |
| `dryRun`  | Resolve and validate inputs, print the planned `PutObject`, skip Vault + AWS calls.                        | `false`                               |

## Outputs

| Output   | Description                                                                                |
|----------|--------------------------------------------------------------------------------------------|
| `bucket` | S3 bucket the channel pointer was (or would be) written to.                                |
| `key`    | S3 key of the channel pointer (e.g. `Distribution/<product>/<channel>.json`).              |
| `url`    | Public URL of the channel pointer.                                                         |
| `body`   | JSON body written (or that would be written) to S3. Useful for schema validation in tests. |

## Required GitHub Environment

The manual-ops workflow MUST be gated by a GitHub Environment configured with **required reviewers**. Without that
gate, anyone with write access to the repo could re-point a production channel.

To create the environment:

1. In the repo, go to **Settings → Environments → New environment**.
2. Name it `release-channel-admin`.
3. Under **Deployment protection rules**, enable **Required reviewers** and add the reviewer allowlist.
4. Save.

Recommended reviewer allowlist:

- Release captains / squad leads of the consuming product
- Plus a backup from the platform / release engineering team for breakglass

The action's STS credentials are broadly scoped (the Vault preset can write anywhere under
`downloads-cdn-eu-central-1-prod`). The in-action destination-prefix guardrail mitigates path traversal, but a
mistaken `version` or `channel` in a manual dispatch can still corrupt a production pointer. Requiring an approver
ensures a second pair of eyes on every non-automated write, and ensures no Vault token is fetched until the dispatch
is approved.

## Operational recipes

All manual operations use the standalone `workflow_dispatch` workflow shown above. Dispatch from **Actions → Update
release channel → Run workflow**, fill the inputs, wait for the environment approver to click **Approve**.

### Rollback

1. Identify the prior version (release notes, `git tag`, or the previous `<channel>.json` body cached locally).
2. Dispatch with `version: <prior-version>` and `channel: <affected-channel>`.

Writes are atomic per channel; rollback affects only the targeted channel. `Cache-Control: max-age=60` means
consumers pick up the rollback within a minute.

### Delayed promotion

Dispatch with `version: <released-version>` and `channel: stable` (or any non-`latest` channel) whenever the team is
ready. No special handling — this is the manual-ops workflow's normal use.

### Backfill

When onboarding the action against an existing product, backfill the channel pointer for the currently-published
version with one dispatch (`version: <current>`, `channel: <channel>`). Repeat per channel.

### Channel migration

To deprecate a channel name (e.g. retire `rc` in favour of `beta`), backfill `beta.json` to match `rc.json`'s current
value via one dispatch. The action does not delete channel files; remove channel JSON out-of-band via the AWS console
or CLI.

## Limitations

### Publish and channel update are not transactional

The release pipeline (publish to `Distribution/<product>/<version>/`) and the `update-release-channel` job run as
separate steps. If publish succeeds but the channel update fails (transient AWS error, expired Vault token), the
artifacts are live at the versioned URL but `<channel>.json` still points at the previous version. Consumers see the
previous version until the channel update is retried — no half-promoted state.

### Recovery

Re-run the channel update via the manual-ops workflow with the same `version` and `channel`. The JSON body is
regenerated on each invocation, so repeating the operation is idempotent.

## Implementation details

- **Bucket:** `downloads-cdn-eu-central-1-prod` (served at `https://binaries.sonarsource.com/`)
- **Vault preset:** `development/aws/sts/downloads` (shared with `gh-action_release`)
- **Cache-Control:** `max-age=60` on every write — short enough that rollbacks propagate quickly, long enough to keep
  the CDN happy.
- **Destination guardrail:** the script refuses to write outside `<prefix>/<product>/<channel>.json` and validates
  `<product>` against `^[a-z0-9][a-z0-9._-]*$`. A custom `prefix` other than `Distribution` is accepted with a loud
  warning.
