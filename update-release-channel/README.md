# Update release channel

GitHub Action that maintains per-channel JSON pointer files on `binaries.sonarsource.com` so consumers can discover the
currently published version for each release channel of a product.

For example, a release pipeline can call this action after publishing `Distribution/sonarqube-cli/0.9.0.977/` to
update `Distribution/sonarqube-cli/latest.json` so install scripts, homebrew formulas, and the CLI's own auto-update
check can resolve the current version with a single HTTP GET.

The action writes one JSON file per channel (atomic per channel, single S3 `PutObject`). Lifecycle operations like
rollback, delayed promotion, and backfill are first-class — they're a single `workflow_dispatch` invocation away,
without re-running the release pipeline.

The JSON body follows the [v1 schema](./schema/v1.json); see [schema/README.md](./schema/README.md) for the field
contract.

## Inputs

| Input     | Required | Default                                  | Description                                                                |
| --------- | -------- | ---------------------------------------- | -------------------------------------------------------------------------- |
| `version` | yes      | —                                        | Version the channel should point at (e.g. `0.9.0.977`).                    |
| `channel` | no       | `latest`                                 | Release channel name. One of `latest`, `stable`, `beta`, `rc`, `dogfood`.  |
| `prefix`  | no       | `Distribution`                           | S3 key prefix under the bucket. Other values warn but are accepted.        |
| `product` | no       | `${{ github.event.repository.name }}`    | Product folder name on S3.                                                 |
| `dryRun`  | no       | `false`                                  | Resolve and validate inputs, print the planned `PutObject`, skip the call. |

### When to set `product:` explicitly

The default (`${{ github.event.repository.name }}`) works whenever the GitHub repository name matches the product
folder on S3. Set `product:` explicitly when they differ — for example, `sonar-dummy-gradle-oss` publishes to
`Distribution/sonar-dummy-gradle-oss-plugin/` and must pass `product: sonar-dummy-gradle-oss-plugin`.

## Outputs

| Output   | Description                                                                                 |
| -------- | ------------------------------------------------------------------------------------------- |
| `bucket` | S3 bucket the channel pointer was (or would be) written to.                                 |
| `key`    | S3 key of the channel pointer (e.g. `Distribution/<product>/<channel>.json`).               |
| `url`    | Public URL of the channel pointer.                                                          |
| `body`   | JSON body written (or that would be written) to S3. Useful for schema validation in tests.  |

## Usage

### Release-workflow follow-up job (automated)

The standard pattern: append an `update-channel` job to the release workflow so the `latest` channel is promoted
automatically after a successful publish. No environment gate — the gate is the release itself.

```yaml
# .github/workflows/release.yml
jobs:
  release:
    uses: SonarSource/gh-action_release/.github/workflows/main.yaml@7.0.1
    with: { ... }

  update-channel:
    needs: release
    if: ${{ !inputs.dryRun }}
    runs-on: sonar-xs
    permissions:
      id-token: write   # OIDC → Vault
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/update-release-channel@v1
        with:
          version: ${{ inputs.version }}
          # channel defaults to "latest"; prefix to "Distribution"; product to the repo name.
```

### Standalone `workflow_dispatch` (manual ops)

A separate workflow for rollback, delayed promotion, backfill, and channel migration. Gated by a GitHub Environment
with required reviewers so every manual write is an approved action.

```yaml
# .github/workflows/update-release-channel.yml
on:
  workflow_dispatch:
    inputs:
      version: { required: true, type: string }
      channel: { required: true, type: choice, options: [stable, beta, rc] }

jobs:
  update-channel:
    runs-on: sonar-xs
    environment: release-channel-admin   # required reviewers — see below
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/update-release-channel@v1
        with:
          version: ${{ inputs.version }}
          channel: ${{ inputs.channel }}
```

The `latest` channel is intentionally omitted from the manual choices — promote `latest` only via the automated
release follow-up job.

## Required GitHub Environment

The manual-ops workflow MUST be gated by a GitHub Environment configured with **required reviewers**. Without that
gate, anyone with write access to the repo could re-point a production channel.

### How to create the environment

1. In the repo, go to **Settings → Environments → New environment**.
2. Name it `release-channel-admin`.
3. Under **Deployment protection rules**, enable **Required reviewers** and add the reviewer allowlist (see below).
4. Save.

Optional: restrict the environment to specific branches under **Deployment branches** if your manual-ops workflow
should only be dispatchable from `master` / `main`.

### Recommended reviewer allowlist

- Release captains / squad leads of the consuming product
- Plus a backup from the platform / release engineering team for breakglass

### Rationale

The action's STS credentials are broadly scoped (the Vault preset `development/aws/sts/downloads` can write anywhere
under `downloads-cdn-eu-central-1-prod`). The in-action destination-prefix guardrail mitigates path traversal, but a
mistaken `version` or `channel` in a manual dispatch can still corrupt a production pointer. Requiring an approver
ensures a second pair of eyes on every non-automated write, and ensures no Vault token is even fetched until the
dispatch is approved in the GitHub UI.

## Operational recipes

All manual operations use the standalone `workflow_dispatch` workflow above. Dispatch from **Actions → Update release
channel → Run workflow**, fill the inputs, and wait for the environment approver to click **Approve**.

### Rollback

To re-point a channel at the previously-known-good version:

1. Identify the prior version (from release notes, `git tag`, or the previous `<channel>.json` body cached locally).
2. Dispatch with `version: <prior-version>` and `channel: <affected-channel>`.

Because writes are atomic per channel (single `PutObject`), rollback affects only the targeted channel; other
channels are untouched. The `max-age=60` cache header ensures consumers pick up the rollback within a minute.

### Delayed promotion

To promote `stable` (or any non-`latest` channel) some time after the release published `latest`:

- Dispatch with `version: <released-version>` and `channel: stable` whenever the team is ready.

This is just the manual-ops workflow's normal use — no special handling required.

### Backfill

When onboarding the action against an existing product that has prior releases, backfill the channel pointer for the
currently-published version with one dispatch (`version: <current>`, `channel: <channel>`). Repeat per channel.

### Channel migration

To deprecate a channel name (e.g. retire `rc` in favour of `beta`), backfill `beta.json` to match `rc.json`'s current
value via one dispatch. The action does not delete channel files; if you need a channel JSON removed, do it
out-of-band via the AWS console / CLI.

## Limitations

### Publish and channel update are not transactional

The release pipeline (publish to `Distribution/<product>/<version>/`) and the `update-release-channel` job run as
separate steps. If publish succeeds but the channel update fails (for example, transient AWS error, expired Vault
token), the artifacts are live at the versioned URL but `<channel>.json` still points at the previous version.

Consumers reading `<channel>.json` keep seeing the old version until the channel update is retried — they don't see
a half-promoted state, just the previous one.

### Recovery

Re-run the channel update via the manual-ops workflow:

1. Dispatch with the same `version` and `channel` that the failed automated job tried.
2. Approve the environment gate.

Because the JSON body is regenerated on each invocation, repeating the operation is idempotent. The artifacts at
`Distribution/<product>/<version>/` are already published; only the pointer needs to catch up.

## Implementation details

- **Bucket:** `downloads-cdn-eu-central-1-prod` (served at `https://binaries.sonarsource.com/`)
- **Vault preset:** `development/aws/sts/downloads` (the same preset used by `gh-action_release`)
- **Cache-Control:** `max-age=60` on every write — short enough that rollbacks propagate quickly, long enough to keep
  the CDN happy.
- **Destination guardrail:** the script refuses to write outside `<prefix>/<product>/<channel>.json` and validates
  `<product>` against `^[a-z0-9][a-z0-9._-]*$`. A custom `prefix` other than `Distribution` is accepted with a loud
  warning.
