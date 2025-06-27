# ci-github-actions

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=SonarSource_ci-github-actions&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=SonarSource_ci-github-actions)

CI/CD GitHub Actions

## get-build-number

Manage the build number in GitHub Actions.

The build number is stored in the GitHub repository property named `build_number`. This action will reuse or increment the build number, and
set it as an environment variable named `BUILD_NUMBER`, and as a GitHub Actions output variable also named `BUILD_NUMBER`.

The build number is unique per workflow run ID. It is not incremented on workflow reruns.

Usage:

```yaml
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - run: echo "Build number: ${BUILD_NUMBER}"
```

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
