# ci-github-actions

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=SonarSource_ci-github-actions&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=SonarSource_ci-github-actions)

CI/CD GitHub Actions

## `get-build-number`

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

## `build-poetry`

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

## `pr-cleanup`

Automatically clean up caches and artifacts associated with a pull request when it is closed.

Features:

- Remove GitHub Actions caches associated with the PR
- Clean up artifacts created during PR workflows
- Provide detailed output of the deleted resources
- Show before/after state of caches and artifacts

### Usage

```yaml
name: Cleanup PR Resources
on:
  pull_request:
    types:
      - closed

jobs:
  cleanup:
    runs-on: ubuntu-24.04
    permissions:
      actions: write  # Required for deleting caches and artifacts
    steps:
      - uses: SonarSource/ci-github-actions/pr_cleanup@v1
```

⚠️ Required GitHub permissions:

- `actions: write`: Required to delete caches and artifacts.

## `cache`

Adaptive cache action that automatically chooses the appropriate caching backend based on repository visibility and ownership.

Features:

- Automatically uses GitHub Actions cache for public repositories
- Uses SonarSource S3 cache for private/internal SonarSource repositories
- Seamless API compatibility with standard GitHub Actions cache
- Supports all standard cache inputs and outputs

### Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: SonarSource/ci-github-actions/cache@v1
        with:
          path: |
            ~/.cache/pip
            ~/.cache/maven
          key: ${{ runner.os }}-cache-${{ hashFiles('**/requirements.txt', '**/pom.xml') }}
          restore-keys: |
            cache-${{ runner.os }}
```

### Inputs

- `path`: **Required** - A list of files, directories, and wildcard patterns to cache and restore
- `key`: **Required** - An explicit key for restoring and saving the cache
- `restore-keys`: An ordered list of prefix-matched keys to use for restoring stale cache if no cache hit occurred for key
- `upload-chunk-size`: The chunk size used to split up large files during upload, in bytes
- `enableCrossOsArchive`: When enabled, allows to save or restore caches that can be restored or saved respectively on other platforms
- `fail-on-cache-miss`: Fail the workflow if cache entry is not found
- `lookup-only`: Check if a cache entry exists for the given input(s) without downloading the cache

### Outputs

- `cache-hit`: A boolean value to indicate an exact match was found for the primary key

⚠️ **Note**: This action automatically detects repository visibility and ownership. External repositories will always use GitHub Actions cache.
SonarSource private repositories will use the internal S3 cache when available.
