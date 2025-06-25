# ci-github-actions

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=SonarSource_ci-github-actions&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=SonarSource_ci-github-actions)

CI/CD GitHub Actions

## get-build-number

Manage the build number in GitHub Actions.

The build number is stored in the GitHub repository property named `build_number`. This action will reuse or increment the build number, and
set it as an environment variable named `BUILD_NUMBER`, and as a GitHub Actions output variable also named `BUILD_NUMBER`.

The build number is unique per workflow run ID. It is not incremented on workflow reruns.

### Usage

```yaml
jobs:
  get-build-number:
    runs-on: ubuntu-24.04-large
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/get-build-number@v1
```

⚠️ Required GitHub permissions:

- `id-token: write`
- `contents: read`

⚠️ Required Vault permissions:

- `build-number`: GitHub preset to read and write the build number property. This is built-in to the Vault `auth.github` permission.

### Outputs

- `BUILD_NUMBER`: The current build number.

## build-poetry

Build and publish a Python project using Poetry.

### Usage

_All the `with` parameters are optional and have default values which are shown below._

```yaml
name: Build
on:
  push:
    branches:
      - master
      - branch-*
  pull_request:
  merge_group:
  workflow_dispatch:

jobs:
  build:
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: ubuntu-24.04-large
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/build-poetry@v1
        with:
          public: false                                         # Defaults to `true` if the repository is public
          artifactory-reader-role: private-reader               # or public-reader if `public` is `true`
          artifactory-deployer-role: qa-deployer                # or public-deployer if `public` is `true`
          deploy-pull-request: true
          poetry-virtualenvs-path: .cache/pypoetry/virtualenvs
          poetry-cache-dir: .cache/pypoetry
```

⚠️ Required GitHub permissions:

- `id-token: write`
- `contents: write`

⚠️ Required Vault permissions:

- `public-reader` or `private-reader` Artifactory roles for the build.
- `public-deployer` or `qa-deployer` Artifactory roles for the deployment.
- `qa-deployer` Artifactory role for the QA deploy.

## pr-cleanup

Automatically clean up caches and artifacts associated with a pull request when it's closed.

Features:

- Removes GitHub Actions caches associated with the PR
- Cleans up artifacts created during PR workflows
- Provides detailed output of deleted resources
- Shows before/after state of caches and artifacts

⚠️ **Important note:** the calling workflow needs a token with `actions:write` permission for cache and artifact deletion

Usage:

```yaml
name: Cleanup PR Resources
on:
  pull_request:
    types:
      - closed

jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions:
      actions: write  # Required for deleting caches and artifacts
    steps:
      - uses: SonarSource/ci-github-actions/pr_cleanup@master
```

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GH_TOKEN` | GitHub token with actions:write permission for cache and artifact deletion | `${{ github.token }}` |
| `CACHE_REF` | Cache reference in the format "refs/pull/<pr_number>/merge" | `refs/pull/123/merge` |
| `GITHUB_REPOSITORY` | Repository name with owner | `owner/repo` |
| `GITHUB_HEAD_REF` | Head branch reference of the pull request | `feature-branch` |

### Permissions

The workflow requires the following permissions:

- `actions: write` - Required for deleting caches and artifacts

This permission must be explicitly set in the workflow as shown in the example above.
