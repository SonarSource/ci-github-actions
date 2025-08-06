# ci-github-actions

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=SonarSource_ci-github-actions&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=SonarSource_ci-github-actions)

CI/CD GitHub Actions

## 📋 Standardization & Requirements

All actions in this repository follow standardized patterns for consistency and maintainability. Key standardizations include:

### Required Inputs

- **`repox-url`**: Required for all build actions (default: `https://repox.jfrog.io`)
- **`develocity-url`**: Required for Gradle and Maven build actions (default: `https://develocity.sonar.build/`)

### Standardized Environment Variables

All actions use consistent environment variables with safe fallback patterns (`|| ''` instead of `false` or `null`):

- `PULL_REQUEST`: Pull request number or empty string
- `PULL_REQUEST_SHA`: Pull request base SHA or empty string
- `DEFAULT_BRANCH`: Repository default branch name

### Event Detection

Actions use `$GITHUB_EVENT_NAME` environment variable for reliable pull request detection instead of legacy string comparison patterns.

---

## `get-build-number`

Manage the build number in GitHub Actions.

The GitHub status check is named `get-build-number`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: read`

#### Required Vault Permissions

- `build-number`: GitHub preset to read and write the build number property. This is built-in to the Vault `auth.github` permission.

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

### Inputs

No inputs are required for this action.

### Outputs

| Output | Description |
|--------|-------------|
| `BUILD_NUMBER` | The current build number |

### Features

- Automatic build number management with GitHub repository properties
- Build number uniqueness per workflow run ID
- No increment on workflow reruns
- Sets both environment variable and output variable

## `build-maven`

Build and deploy a Maven project with SonarQube analysis and Artifactory deployment.

The GitHub status check is named `Build`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.
- `public-deployer` or `qa-deployer`: Artifactory role for deployment.
- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on sonar-platform)
- `development/kv/data/sign`: Artifact signing credentials (key and passphrase).
- `development/kv/data/develocity`: Develocity access token (if using Develocity).

#### Other Dependencies

The Java and Maven tools must be pre-installed. Use of `mise` is recommended.

Maven configuration is required:

- JFrog Artifactory Maven plugin configuration for deployment
- Maven profiles for different build contexts (`deploy-sonarsource`, `sign`, `coverage`)
- Proper Maven settings.xml configuration for Artifactory authentication (provided by the action)

### Usage

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: SonarSource/ci-github-actions/build-maven@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `public` | Whether to build and deploy with/to public repositories | Auto-detected from repository visibility |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault | `qa-deployer` for private repos, `public-deployer` for public repos |
| `deploy-pull-request` | Whether to deploy pull request artifacts | `false` |
| `maven-local-repository-path` | Path to the Maven cache directory, relative to the user home directory | `.m2/repository` |
| `maven-opts` | Additional Maven options to pass to the build script (`MAVEN_OPTS`) | `-Xmx1536m -Xms128m` |
| `scanner-java-opts` | Additional Java options for the Sonar scanner (`SONAR_SCANNER_JAVA_OPTS`) | `-Xmx512m` |
| `use-develocity` | Whether to use Develocity for build tracking | `false` |
| `repox-url` | URL for Repox | `https://repox.jfrog.io` |
| `develocity-url` | URL for Develocity | `https://develocity.sonar.build/` |
| `sonar-platform` | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us' | `next` |

### Outputs

No outputs are provided by this action.

### Features

- Build context detection with automatic deployment strategies
- SonarQube analysis with credentials from Vault
- Artifact signing with GPG keys from Vault
- Conditional deployment based on branch patterns
- Maven local repository caching
- Develocity integration for build optimization (optional)
- Support for different branch types:
  - **master**: Deploy + SonarQube analysis with full profiles
  - **maintenance** (`branch-*`): Deploy with full profiles + separate SonarQube analysis
  - **pr**: Conditional deployment with SonarQube analysis
  - **dogfood** (`dogfood-on-*`): Deploy only with dogfood profiles
  - **feature** (`feature/long/*`): Verify + SonarQube analysis only
  - **default**: Basic verify goal only

## `build-poetry`

Build and publish a Python project using Poetry.

The GitHub status check is named `Build`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on sonar-platform)
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

#### Other Dependencies

The Python and Poetry tools must be pre-installed. Use of `mise` is recommended.

### Usage

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: SonarSource/ci-github-actions/build-poetry@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `public` | Whether to build and deploy with/to public repositories | Auto-detected from repository visibility |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault | `qa-deployer` for private repos, `public-deployer` for public repos |
| `deploy-pull-request` | Whether to deploy pull request artifacts | `false` |
| `poetry-virtualenvs-path` | Path to the Poetry virtual environments, relative to GitHub workspace | `.cache/pypoetry/virtualenvs` |
| `poetry-cache-dir` | Path to the Poetry cache directory, relative to GitHub workspace | `.cache/pypoetry` |
| `repox-url` | URL for Repox | `https://repox.jfrog.io` |
| `sonar-platform` | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us' | `next` |

### Outputs

No outputs are provided by this action.

### Features

- Automated dependency management with Poetry
- Conditional deployment based on branch patterns
- Python virtual environment caching for faster builds
- SonarQube analysis integration (configurable)
- Comprehensive build logging and error handling

## `build-gradle`

Build and publish a Gradle project with SonarQube analysis and Artifactory deployment.

The GitHub status check is named `Build`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on sonar-platform)
- `development/kv/data/sign`: Artifact signing credentials (key, passphrase, and key_id)
- `development/kv/data/develocity`: Develocity access token
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

#### Other Dependencies

The Java and Gradle tools must be pre-installed. Use of `mise` is recommended.

Gradle Artifactory plugin configuration is required in your `build.gradle` file.

### Usage

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: SonarSource/ci-github-actions/build-gradle@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `public` | Whether to build and deploy with/to public repositories | Auto-detected from repository visibility |
| `artifactory-deploy-repo` | Name of deployment repository | Auto-detected based on repository visibility |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault | `qa-deployer` for private repos, `public-deployer` for public repos |
| `deploy-pull-request` | Whether to deploy pull request artifacts | `false` |
| `skip-tests` | Whether to skip running tests | `false` |
| `gradle-args` | Additional arguments to pass to Gradle | (optional) |
| `gradle-version` | Gradle version to use for setup-gradle action | (optional) |
| `gradle-wrapper-validation` | Whether to validate Gradle wrapper | `true` |
| `develocity-url` | URL for Develocity | `https://develocity.sonar.build/` |
| `repox-url` | URL for Repox | `https://repox.jfrog.io` |
| `sonar-platform` | SonarQube variant - 'next', 'sqc-eu', or 'sqc-us' | `next` |

### Outputs

| Output | Description |
|--------|-------------|
| `project-version` | The project version from gradle.properties |

### Features

- Automated version management with build numbers
- SonarQube analysis for code quality
- Conditional deployment based on branch patterns
- Automatic artifact signing with credentials from Vault
- Pull request support with optional deployment
- Develocity integration for build optimization
- Gradle wrapper validation
- Comprehensive build logging and error handling

## `build-npm`

Build, test, analyze, and deploy an NPM project with SonarQube integration and JFrog Artifactory deployment.

The GitHub status check is named `Build`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on sonar-platform)
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

#### Other Dependencies

The Node.js and NPM tools must be pre-installed. Use of `mise` is recommended.

### Usage

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: SonarSource/ci-github-actions/build-npm@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `public` | Whether to build and deploy with/to public repositories | Auto-detected from repository visibility |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault | `qa-deployer` for private repos, `public-deployer` for public repos |
| `artifactory-deploy-repo` | Name of deployment repository | (optional) |
| `artifactory-deploy-access-token` | Access token to deploy to Artifactory | (optional) |
| `deploy-pull-request` | Whether to deploy pull request artifacts | `false` |
| `skip-tests` | Whether to skip running tests | `false` |
| `cache-npm` | Whether to cache NPM dependencies | `true` |
| `repox-url` | URL for Repox | `https://repox.jfrog.io` |
| `sonar-platform` | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us' | `next` |

### Outputs

| Output | Description |
|--------|-------------|
| `project-version` | The project version from package.json |
| `build-info-url` | The JFrog build info UI URL |

### Features

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality
- Conditional deployment based on branch patterns
- NPM dependency caching for faster builds (configurable)
- Pull request support with optional deployment
- JFrog build info publishing with UI links
- Support for different branch types (default, maintenance, PR, dogfood, long-lived feature)
- Comprehensive build logging and error handling

## `build-yarn`

Build, test, analyze, and deploy a Yarn project with SonarQube integration and Artifactory deployment.

The GitHub status check is named `Build`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on sonar-platform)
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

#### Other Dependencies

The Node.js and Yarn tools must be pre-installed. Use of `mise` is recommended.

### Usage

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
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: SonarSource/ci-github-actions/build-yarn@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `public` | Whether to build and deploy with/to public repositories | Auto-detected from repository visibility |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault | `qa-deployer` for private repos, `public-deployer` for public repos |
| `artifactory-deploy-repo` | Name of deployment repository | (optional) |
| `deploy-pull-request` | Whether to deploy pull request artifacts | `false` |
| `skip-tests` | Whether to skip running tests | `false` |
| `cache-yarn` | Whether to cache Yarn dependencies | `true` |
| `repox-url` | URL for Repox | `https://repox.jfrog.io` |
| `sonar-platform` | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us' | `next` |

### Outputs

| Output | Description |
|--------|-------------|
| `project-version` | The project version from package.json |
| `build-info-url` | The JFrog build info UI URL |

### Features

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality
- Conditional deployment based on branch patterns
- Yarn dependency caching for faster builds (configurable)
- Pull request support with optional deployment
- JFrog build info publishing with UI links
- Support for different branch types (default, maintenance, PR, dogfood, long-lived feature)
- Comprehensive build logging and error handling

---

## `promote`

This action promotes a build in JFrog Artifactory and updates the GitHub status check accordingly.

The GitHub status check is named `repox-${GITHUB_REF_NAME}`.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `promoter`: Artifactory role for the promotion.
- `promotion`: custom GitHub token for promotion.

#### Other Dependencies

Required properties in the build info:

- `buildInfo.env.ARTIFACTORY_DEPLOY_REPO`: Repository to deploy to (e.g. `sonarsource-deploy-qa`). It can also be set as an input.
- `buildInfo.env.PROJECT_VERSION`: Version of the project (e.g. 1.2.3).

### Usage

```yaml
promote:
  needs:
    - build
  concurrency:
    group: ${{ github.workflow }}-promote-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
  runs-on: ubuntu-24.04-large
  name: Promote
  permissions:
    id-token: write
    contents: write
  steps:
    - uses: SonarSource/ci-github-actions/promote@v1
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `promote-pull-request` | Whether to promote pull request artifacts. Requires `deploy-pull-request` input to be set to `true` in the build action | `false` |
| `multi-repo` | If true, promotes to public and private repositories. For projects with both public and private artifacts | (optional) |
| `artifactory-deploy-repo` | Repository to deploy to. If not set, it will be retrieved from the build info | (optional) |
| `artifactory-target-repo` | Target repository for the promotion. If not set, it will be determined based on the branch type and the deploy repository | (optional) |

### Outputs

No outputs are provided by this action.

### Features

- Automatic promotion of build artifacts in JFrog Artifactory
- GitHub status check updates with promotion status
- Support for both single and multi-repository promotions
- Automatic target repository determination based on branch type
- Pull request artifact promotion support

---

## `pr-cleanup`

Automatically clean up caches and artifacts associated with a pull request when it is closed.

The GitHub status check is named `cleanup`.

### Requirements

#### Required GitHub Permissions

- `actions: write`: Required to delete caches and artifacts.

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
      actions: write
    steps:
      - uses: SonarSource/ci-github-actions/pr_cleanup@v1
```

### Inputs

No inputs are required for this action.

### Outputs

No outputs are provided by this action.

### Features

- Remove GitHub Actions caches associated with the PR
- Clean up artifacts created during PR workflows
- Provide detailed output of the deleted resources
- Show before/after state of caches and artifacts
- Automatic triggering on PR closure

## `cache`

Adaptive cache action that automatically chooses the appropriate caching backend based on repository visibility and ownership.

The GitHub status check is named `Adaptive Cache Action`.

### Requirements

#### Required Vault Permissions

No Vault permissions required for this action.

#### Other Dependencies

The only requirement for the action is `jq` installed.

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

| Input | Description | Default |
|-------|-------------|---------|
| `path` | A list of files, directories, and wildcard patterns to cache and restore | (required) |
| `key` | An explicit key for restoring and saving the cache | (required) |
| `restore-keys` | An ordered list of prefix-matched keys to use for restoring stale cache if no cache hit occurred for key | (optional) |
| `upload-chunk-size` | The chunk size used to split up large files during upload, in bytes | (optional) |
| `enableCrossOsArchive` | When enabled, allows to save or restore caches that can be restored or saved respectively on other platforms | `false` |
| `fail-on-cache-miss` | Fail the workflow if cache entry is not found | `false` |
| `lookup-only` | Check if a cache entry exists for the given input(s) without downloading the cache | `false` |

### Outputs

| Output | Description |
|--------|-------------|
| `cache-hit` | A boolean value to indicate an exact match was found for the primary key |

### Features

- Automatically uses GitHub Actions cache for public repositories
- Uses SonarSource S3 cache for private/internal SonarSource repositories
- Seamless API compatibility with standard GitHub Actions cache
- Supports all standard cache inputs and outputs
- Automatic repository visibility detection

## Using AI for Cirrus CI to GitHub Actions Migration

It is recommended to use AI tools like Cursor or Claude code to assist with Cirrus CI to GitHub actions migration.
This repository contains a comprehensive guide to be passed as a context to AI. The guide is shared with Sonar developers using Cursor,
accessible using `@Doc` tag.

See the [documentation](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/2639560710/Migration+From+Cirrus+CI+-+GitHub)
for details on how to use it.
