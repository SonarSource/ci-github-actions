# ci-github-actions

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=SonarSource_ci-github-actions&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=SonarSource_ci-github-actions)

## Using AI for Cirrus CI to GitHub Actions Migration

It is recommended to use AI tools like Cursor or Claude code to assist with Cirrus CI to GitHub actions migration.
This repository contains a comprehensive guide to be passed as a context to AI. The guide is shared with Sonar developers using Cursor,
accessible using `@Doc` tag.

See the [documentation](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/4232970266/Migration+From+Cirrus+CI+-+GitHub)
for details on how to use it.

---

## Actions provided in this repository

- [`get-build-number`](#get-build-number)
- [`config-maven`](#config-maven)
- [`build-maven`](#build-maven)
- [`build-poetry`](#build-poetry)
- [`config-gradle`](#config-gradle)
- [`build-gradle`](#build-gradle)
- [`config-npm`](#config-npm)
- [`build-npm`](#build-npm)
- [`build-yarn`](#build-yarn)
- [`config-pip`](#config-pip)
- [`promote`](#promote)
- [`pr_cleanup`](#pr_cleanup)
- [`code-signing`](#code-signing)

## `get-build-number`

Manage the build number in GitHub Actions.

The build number is stored in the GitHub repository property named `build_number`. This action will reuse or increment the build number,
and set it as an environment variable named `BUILD_NUMBER`, and as a GitHub Actions output variable also named `BUILD_NUMBER`.

The build number is unique per workflow run ID. It is not incremented on workflow reruns.

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
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: SonarSource/ci-github-actions/get-build-number@v1
```

### Input Environment Variables

| Environment Variable | Description                                                          |
|----------------------|----------------------------------------------------------------------|
| `BUILD_NUMBER`       | If present in the environment, it will be reused as the build number |

### Inputs

No inputs are required for this action.

### Outputs

| Output         | Description              |
|----------------|--------------------------|
| `BUILD_NUMBER` | The current build number |

### Output Environment Variables

| Environment Variable | Description              |
|----------------------|--------------------------|
| `BUILD_NUMBER`       | The current build number |

### Features

- Automatic build number management with GitHub repository properties
- Build number uniqueness per workflow run ID
- No increment on workflow reruns
- Sets both environment variable and output variable

## `config-maven`

Configure Maven build environment with build number, authentication, and default settings.

> **Note:** This action automatically calls [`get-build-number`](#get-build-number) to manage the build number.

This action sets up the complete Maven environment for SonarSource projects, including:

- Build number management
- Artifactory authentication and repository setup
- Maven settings configuration for Repox
- Maven local repository caching
- Common Maven flags and JVM options
- Project version management: Automatically replaces `-SNAPSHOT` versions with the build number (skipped if both `CURRENT_VERSION` and
  `PROJECT_VERSION` environment variables are set)

### Caching Configuration

By default, Maven caches `~/.m2/repository`. You can customize this behavior:

**Cache custom directories:**

```yaml
- uses: SonarSource/ci-github-actions/config-maven@v1
  with:
    cache-paths: |
      ~/.m2/repository
      .custom-cache
      target/cache
```

**Disable caching entirely:**

```yaml
- uses: SonarSource/ci-github-actions/config-maven@v1
  with:
    disable-caching: 'true'
```

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: read`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.

#### Other Dependencies

The Maven tool must be pre-installed. Use of `mise` is recommended.

### Usage

```yaml
permissions:
  id-token: write
  contents: write
steps:
  - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  - uses: SonarSource/ci-github-actions/config-maven@v1
  - run: mvn verify
```

### Input Environment Variables

| Environment Variable                    | Description                                                                       |
|-----------------------------------------|-----------------------------------------------------------------------------------|
| `BUILD_NUMBER`                          | If present, it will be reused by the [`get-build-number`](#get-build-number) action. |
| `CURRENT_VERSION` and `PROJECT_VERSION` | If both are set, they will be used as-is and no version update will be performed. |
| `MAVEN_OPTS`                            | JVM options for Maven execution. Defaults to `-Xmx1536m -Xms128m`.                |
| `JAVA_TOOL_OPTIONS`                     | JVM options. Defaults to `-XX:-UseContainerSupport`.                              |
| `CONFIG_MAVEN_COMPLETED`                | For internal use. If set, the action is skipped                                   |

### Inputs

| Input                     | Description                                                                 | Default                                                                                                                 |
|---------------------------|-----------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `working-directory`       | Relative path under github.workspace to execute the build in                | `.`                                                                                                                     |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault                             | `private-reader` for private repos, `public-reader` for public repos                                                    |
| `common-mvn-flags`        | Maven flags for all subsequent mvn calls                                    | `--batch-mode --no-transfer-progress --errors --fail-at-end --show-version -Dmaven.test.redirectTestOutputToFile=false` |
| `repox-url`               | URL for Repox                                                               | `https://repox.jfrog.io`                                                                                                |
| `repox-artifactory-url`   | URL for Repox Artifactory API (overrides repox-url/artifactory if provided) | (optional)                                                                                                              |
| `use-develocity`          | Whether to use Develocity for build tracking                                | `false`                                                                                                                 |
| `develocity-url`          | URL for Develocity                                                          | `https://develocity.sonar.build/`                                                                                                         |
| `cache-paths`             | Custom cache paths (multiline).                                             | (optional)                                                  |
| `disable-caching`         | Whether to disable Maven caching entirely                                   | `false`                                                                                                                 |

### Outputs

| Output            | Description                                                                                                     |
|-------------------|-----------------------------------------------------------------------------------------------------------------|
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER`                                       |
| `current-version` | The project version set in the pom.xml (before replacement). Also set as environment variable `CURRENT_VERSION` |
| `project-version` | The project version with build number (after replacement). Also set as environment variable `PROJECT_VERSION`   |

### Output Environment Variables

| Environment Variable          | Description                                                                                                                                                                                                                               |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ARTIFACTORY_ACCESS_TOKEN`    | Access token for Artifactory authentication                                                                                                                                                                                               |
| `ARTIFACTORY_ACCESS_USERNAME` | Deprecated alias for `ARTIFACTORY_USERNAME`                                                                                                                                                                                               |
| `ARTIFACTORY_USERNAME`        | Username for Artifactory authentication                                                                                                                                                                                                   |
| `ARTIFACTORY_PASSWORD`        | Deprecated alias for `ARTIFACTORY_ACCESS_TOKEN`                                                                                                                                                                                           |
| `ARTIFACTORY_URL`             | Artifactory (Repox) URL. E.x.: `https://repox.jfrog.io/artifactory`                                                                                                                                                                       |
| `BASH_ENV`                    | Path to the bash profile with mvn function for adding common flags to Maven calls                                                                                                                                                         |
| `CURRENT_VERSION`             | The original project version from pom.xml                                                                                                                                                                                                 |
| `DEVELOCITY_ACCESS_KEY`       | The Develocity access key when `use-develocity` is true                                                                                                                                                                                   |
| `MAVEN_OPTS`                  | JVM options for Maven execution.                                                                                                                                                                                                          |
| `PROJECT_VERSION`             | The project version with build number (after replacement)                                                                                                                                                                                 |
| `SONARSOURCE_REPOSITORY_URL`  | URL for SonarSource Artifactory root virtual repository (i.e.: [`sonarsource`](https://repox.jfrog.io/artifactory/sonarsource) for release builds or [`sonarsource-qa`](https://repox.jfrog.io/artifactory/sonarsource-qa) for QA builds) |
| `CONFIG_MAVEN_COMPLETED`      | For internal use. If set, the action is skipped                                                                                                                                                                                           |
| `MAVEN_CONFIG`                | Path to m2 root `$HOME/.m2`                                                                                                                                                                                                               |

See also [`get-build-number`](#get-build-number) output environment variables.

## `build-maven`

Build and deploy a Maven project with SonarQube analysis and Artifactory deployment.

> **Note:** This action automatically calls [`config-maven`](#config-maven) to set up the Maven environment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.
- `public-deployer` or `qa-deployer`: Artifactory role for deployment.
- `development/kv/data/develocity`: Develocity access token (only fetched when `use-develocity: true`).

#### Other Dependencies

- The Java and Maven tools must be pre-installed. Use of `mise` is recommended.
- The "Sonar parent POM" (`[org|com].sonarsource.parent:parent`) must be used. There's a public POM (org) and a private POM (com),
  respectively for public or private code.
- **Develocity**: In order to access Develocity from GitHub hosted runner e.g. `github-ubuntu-latest-s` you need to adjust your
  Develocity plugin configuration to use the following URL:

```yaml
  <develocity>
    <server>
      <url>https://develocity-public.sonar.build</url>
    </server>
  </develocity>
```

**You also need to provide the same url in `develocity-url` parameter.**

### Usage

```yaml
permissions:
  id-token: write
  contents: write
steps:
  - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  - uses: SonarSource/ci-github-actions/config-maven@v1
  - uses: SonarSource/ci-github-actions/build-maven@v1
```

### Input Environment Variables

| Environment Variable                | Description                                                                                 | Default                  |
|-------------------------------------|---------------------------------------------------------------------------------------------|--------------------------|
| `ARTIFACTORY_PRIVATE_DEPLOY_REPO`   | Only if `mixed-privacy == true`. Repository to deploy private artifacts.                    | `sonarsource-private-qa` |
| `ARTIFACTORY_PRIVATE_DEPLOYER_ROLE` | Only if `mixed-privacy == true`. Suffix for the Artifactory private deployer role in Vault. | `qa-deployer`            |

See also [`config-maven`](#config-maven) input environment variables.

### Inputs

| Input                       | Description                                                                                                                  | Default                                                                                     |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `artifactory-deploy-repo`   | Deployment repository                                                                                                        | `sonarsource-private-qa` for private repositories, `sonarsource-public-qa` for public repos |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                                                              | `private-reader` for private repos, `public-reader` for public repos                        |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                                                            | `qa-deployer` for private repos, `public-deployer` for public repos                         |
| `deploy`                    | Whether to deploy on master, maintenance, dogfood and long-lived branches                                                    | `true`                                                                                      |
| `deploy-pull-request`       | Whether to also deploy for pull requests. If deploy is false, this has no effect.                                            | `false`                                                                                     |
| `maven-args`                | Additional arguments to pass to Maven                                                                                        | (optional)                                                                                  |
| `scanner-java-opts`         | Additional Java options for the Sonar scanner (`SONAR_SCANNER_JAVA_OPTS`)                                                    | `-Xmx512m`                                                                                  |
| `repox-url`                 | URL for Repox                                                                                                                | `https://repox.jfrog.io`                                                                    |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                  | (optional)                                                                                  |
| `use-develocity`            | Whether to use Develocity for build tracking                                                                                 | `false`                                                                                     |
| `develocity-url`            | URL for Develocity                                                                                                           | `https://develocity.sonar.build/`                                                           |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', 'sqc-us', or 'none'. Use 'none' to skip sonar scans                           | `next`                                                                                      |
| `working-directory`         | Relative path under github.workspace to execute the build in                                                                 | `.`                                                                                         |
| `run-shadow-scans`          | If true, run SonarQube analysis on all 3 platforms (next, sqc-eu, sqc-us); if false, only on the selected `sonar-platform`   | `false`                                                                                     |
| `cache-paths`               | Custom cache paths (multiline). Overrides default `~/.m2/repository`.                                                        | (optional)                                                                                  |
| `cache-cleanup`             | Whether to clean up the cache before saving it.                                                                              | `true`                                                                                      |
| `disable-caching`           | Whether to disable Maven caching entirely                                                                                    | `false`                                                                                     |
| `provenance`                | Whether to generate provenance attestation for built artifacts                                                               | `false`                                                                                     |
| `provenance-artifact-paths` | Relative paths of artifacts for provenance attestation (glob pattern). See [Provenance Attestation](#provenance-attestation) | (optional)                                                                                  |
| `mixed-privacy`             | Whether the repository contains both public and private code                                                                 | `false`                                                                                     |

#### `cache-cleanup`

Adds an extra step to delete the `<org|com>/sonarsource` artifacts from the cache before saving it.

This is useful for avoiding the caching of Sonar artifacts which are built in the same repository and will not be reused. However, they may
need to be kept, or deleted later in the workflow, if other steps depend on them.

#### `mixed-privacy`

When set to `true`, this input option configures the build to handle both public and private artifacts.

- The Maven Artifactory plugin will not publish the artifacts.
- The artifacts are individually deployed after the build with the JFrog CLI to their respective repositories.
- This feature relies on Maven install being enabled (`maven.install.skip=false`).

It is possible to customize the target public and private repository names and the roles used for deployment by setting the input parameters
for the public values, and by setting the environment variables for the private values:

- `artifactory-deploy-repo` input
- `artifactory-deployer-role` input
- `ARTIFACTORY_PRIVATE_DEPLOY_REPO` environment variable
- `ARTIFACTORY_PRIVATE_DEPLOYER_ROLE` environment variable

### Outputs

| Output            | Description                                                                                                   |
|-------------------|---------------------------------------------------------------------------------------------------------------|
| `project-version` | The project version with build number (after replacement). Also set as environment variable `PROJECT_VERSION` |
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER`                                     |
| `deployed`        | `true` if the build succeed and was supposed to deploy                                                        |

### Output Environment Variables

- `SONARSOURCE_REPOSITORY_URL`: URL for SonarSource Artifactory root virtual repository is set to [`sonarsource`](https://repox.jfrog.io/artifactory/sonarsource)

See also [`config-maven`](#config-maven) output environment variables.

### Features

- Build context detection with automatic deployment strategies
- SonarQube analysis for code quality
- Artifact signing with GPG keys
- Conditional deployment based on branch patterns
- Develocity integration for build optimization (optional)
- Maven local repository caching with customization options
- Support for different branch types:
  - **master**: Deploy + SonarQube analysis with full profiles
  - **maintenance** (`branch-*`): Deploy with full profiles + separate SonarQube analysis
  - **pr**: Conditional deployment with SonarQube analysis
  - **dogfood** (`dogfood-on-*`): Deploy only with dogfood profiles
  - **feature** (`feature/long/*`): Verify + SonarQube analysis only
  - **default**: Basic verify goal only
- Mixed privacy repository support for combined public and private artifacts

## `build-poetry`

Build, analyze, and publish a Python project using Poetry with SonarQube integration and Artifactory deployment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

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

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true # or ${{ github.ref_name != github.event.repository.default_branch }}

jobs:
  build:
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: SonarSource/ci-github-actions/build-poetry@v1
        with:
          public: false                                        # Defaults to `true` if the repository is public
          artifactory-reader-role: private-reader              # or public-reader if `public` is `true`
          artifactory-deployer-role: qa-deployer               # or public-deployer if `public` is `true`
          deploy-pull-request: false                           # Deploy pull request artifacts
          poetry-virtualenvs-path: .cache/pypoetry/virtualenvs # Poetry virtual environment path
          poetry-cache-dir: .cache/pypoetry                    # Poetry cache directory
          repox-url: https://repox.jfrog.io                    # Repox URL
          sonar-platform: next                                 # SonarQube platform (next, sqc-eu, or sqc-us)
          run-shadow-scans: false                              # Run SonarQube scans on all 3 platforms (next, sqc-eu, sqc-us)
```

**Disable caching entirely:**

```yaml
- uses: SonarSource/ci-github-actions/build-poetry@v1
  with:
    disable-caching: 'true'
```

### Inputs

| Input                       | Description                                                                                                                                                                                   | Default                                                                                               |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `public`                    | Deprecated                                                                                                                                                                                    | Repository visibility                                                                                 |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                                                                                                                               | `private-reader` for private repos, `public-reader` for public repos                                  |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                                                                                                                             | `qa-deployer` for private repos, `public-deployer` for public repos                                   |
| `artifactory-deploy-repo`   | Deployment repository                                                                                                                                                                         | `sonarsource-pypi-private-qa` for private repositories, `sonarsource-pypi-public-qa` for public repos |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                                                                                                                                      | `false`                                                                                               |
| `poetry-virtualenvs-path`   | Path to the Poetry virtual environments, relative to GitHub workspace                                                                                                                         | `.cache/pypoetry/virtualenvs`                                                                         |
| `poetry-cache-dir`          | Path to the Poetry cache directory, relative to GitHub workspace                                                                                                                              | `.cache/pypoetry`                                                                                     |
| `repox-url`                 | URL for Repox                                                                                                                                                                                 | `https://repox.jfrog.io`                                                                              |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                                                                                   | (optional)                                                                                            |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', sqc-us, or 'none'. Use 'none' to skip sonar scans                                                                                              | `next`                                                                                                |
| `run-shadow-scans`          | If true, run sonar scanner on all 3 platforms using the provided URL and token. If false, run on the platform provided by sonar-platform. When enabled, the sonar-platform setting is ignored | `false`                                                                                               |
| `working-directory`         | Relative path under github.workspace to execute the build in                                                                                                                                  | `.`                                                                                                   |
| `disable-caching`           | Whether to disable Poetry caching entirely                                                                                                                                                    | `false`                                                                                               |
| `provenance`                | Whether to generate provenance attestation for built artifacts                                                                                                                                | `false`                                                                                               |
| `provenance-artifact-paths` | Relative paths of artifacts for provenance attestation (glob pattern). See [Provenance Attestation](#provenance-attestation)                                                                  | (optional)                                                                                            |

### Outputs

| Output           | Description                                                                                                  |
|------------------|--------------------------------------------------------------------------------------------------------------|
| `BUILD_NUMBER`   | The current build number. Also set as environment variable `BUILD_NUMBER`                                    |
| `project-version`| The project version from pyproject.toml with build number. Also set as environment variable `PROJECT_VERSION`|
| `deployed`       | `true` if the build succeed and was supposed to deploy                                                       |

## `config-gradle`

Configure Gradle build environment with build number, authentication, and default settings.

> **Note:** This action automatically calls [`get-build-number`](#get-build-number) to manage the build number.

This action sets up the complete Gradle environment for SonarSource projects, including:

- Build number management
- Artifactory authentication and repository setup
- Gradle authentication configuration for Repox
- Gradle caching (caches and wrapper directories)
- JVM options configuration
- Develocity integration for build tracking (optional)
- Project version management: Automatically replaces `-SNAPSHOT` versions with the build number (skipped if both `CURRENT_VERSION` and
  `PROJECT_VERSION` environment variables are set)

### Caching Configuration

By default, Gradle caches `~/.gradle/caches` and `~/.gradle/wrapper`. You can customize this behavior:

**Cache custom directories:**

```yaml
- uses: SonarSource/ci-github-actions/config-gradle@v1
  with:
    cache-paths: |
      ~/.gradle/caches
      ~/.gradle/wrapper
      ~/custom/directory
```

**Disable caching entirely:**

```yaml
- uses: SonarSource/ci-github-actions/config-gradle@v1
  with:
    disable-caching: 'true'
```

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.
- `development/kv/data/develocity`: Develocity access token (only fetched when `use-develocity: true`).

#### Other Dependencies

**Java**: Must be pre-installed in the runner image. We recommend using `mise` to install and manage Java versions.

**Gradle**: Must be pre-installed in the runner image. We recommend including the Gradle wrapper (`gradlew`) in your repository,
which will be used automatically. If the Gradle wrapper is not available, you can install Gradle using `mise` in your pipeline.

### Usage

```yaml
permissions:
  id-token: write
  contents: write
steps:
  - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  - uses: SonarSource/ci-github-actions/config-gradle@v1
  - run: ./gradlew build
```

### Input Environment Variables

| Environment Variable                    | Description                                                                          |
|-----------------------------------------|--------------------------------------------------------------------------------------|
| `BUILD_NUMBER`                          | If present, it will be reused by the [`get-build-number`](#get-build-number) action. |
| `CURRENT_VERSION` and `PROJECT_VERSION` | If both are set, they will be used as-is and no version update will be performed.    |
| `ARTIFACTORY_URL`                       | Artifactory (Repox) URL. Default: `https://repox.jfrog.io/artifactory`               |
| `SONARSOURCE_REPOSITORY`                | SonarSource Repox repository (e.x.: `sonarsource` (default) or `sonarsource-qa`)     |

If provided, `ARTIFACTORY_URL` is used at runtime by the Gradle init script to configure the Artifactory URL. `artifactoryUrl` Gradle
property can also be used instead.

If provided, `SONARSOURCE_REPOSITORY` is used at runtime by the Gradle init script to configure the source repository for artifacts.

### Inputs

| Input                     | Description                                                                 | Default                                                              |
|---------------------------|-----------------------------------------------------------------------------|----------------------------------------------------------------------|
| `working-directory`       | Relative path under github.workspace to execute the build in                | `.`                                                                                                                     |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault                             | `private-reader` for private repos, `public-reader` for public repos |
| `use-develocity`          | Whether to use Develocity for build tracking                                | `false`                                                              |
| `develocity-url`          | URL for Develocity                                                          | `https://develocity.sonar.build/`                                    |
| `repox-url`               | URL for Repox                                                               | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`   | URL for Repox Artifactory API (overrides repox-url/artifactory if provided) | (optional)                                                           |
| `cache-paths`             | Custom cache paths (multiline).                                             | `~/.gradle/caches`<br>`~/.gradle/wrapper`                            |
| `disable-caching`         | Whether to disable Gradle caching entirely                                  | `false`                                                              |

### Outputs

| Output            | Description                                                                                                           |
|-------------------|-----------------------------------------------------------------------------------------------------------------------|
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER`                                             |
| `current-version` | The project version set in gradle.properties (before replacement). Also set as environment variable `CURRENT_VERSION` |
| `project-version` | The project version with build number (after replacement). Also set as environment variable `PROJECT_VERSION`         |

### Output Environment Variables

| Environment Variable          | Description                                                         |
|-------------------------------|---------------------------------------------------------------------|
| `BUILD_NUMBER`                | The current build number.                                           |
| `CURRENT_VERSION`             | The original project version from gradle.properties                 |
| `PROJECT_VERSION`             | The project version with build number (after replacement)           |
| `ARTIFACTORY_READER_ROLE`     | Reader role for Artifactory authentication                          |
| `ARTIFACTORY_USERNAME`        | Username for Artifactory authentication                             |
| `ARTIFACTORY_ACCESS_TOKEN`    | Access token for Artifactory authentication                         |
| `ARTIFACTORY_URL`             | Artifactory (Repox) URL. E.x.: `https://repox.jfrog.io/artifactory` |
| `ARTIFACTORY_ACCESS_USERNAME` | Deprecated alias for `ARTIFACTORY_USERNAME`                         |
| `ARTIFACTORY_PASSWORD`        | Deprecated alias for `ARTIFACTORY_ACCESS_TOKEN`                     |
| `DEVELOCITY_ACCESS_KEY`       | The Develocity access key when `use-develocity` is true             |
| `GRADLE_CACHE_KEY`            | The Gradle cache key generated from all gradle files                |

See also [`get-build-number`](#get-build-number) output environment variables.

## `build-gradle`

Build and publish a Gradle project with SonarQube analysis and Artifactory deployment.

> **Note:** This action automatically calls [`config-gradle`](#config-gradle) to set up the Gradle environment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/develocity`: Develocity access token (only fetched when `use-develocity: true`)
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

#### Other Dependencies

**Java**: Not pre-installed in the runner image. We recommend using `mise` to install and manage Java versions.

**Gradle**: Not pre-installed in the runner image. We recommend including the Gradle wrapper (`gradlew`) in your repository, which will be
used automatically. If the Gradle wrapper is not available, you can install Gradle using `mise` in your pipeline.

**Develocity**: In order to access Develocity from GitHub hosted runner e.g. `github-ubuntu-latest-s` you need to adjust your
Develocity plugin configuration to use the following URL:

```yaml
  develocity {
    server = "https://develocity-public.sonar.build"
    ...
  }
```

**You also need to provide the same url in `develocity-url` parameter.**

**Additional Configuration**: The Gradle Artifactory plugin configuration is required in `build.gradle` file.

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

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true # or ${{ github.ref_name != github.event.repository.default_branch }}

jobs:
  build:
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: SonarSource/ci-github-actions/build-gradle@v1
        with:
          # Enable shadow scans for unified platform dogfooding (optional)
          run-shadow-scans: 'true'
          # Primary platform when shadow scans disabled (optional)
          sonar-platform: 'next'
```

### Input Environment Variables

| Environment Variable | Description                                          |
|----------------------|------------------------------------------------------|
| `JAVA_TOOL_OPTIONS`  | JVM options. Defaults to `-XX:-UseContainerSupport`. |

See also [`config-gradle`](#config-gradle) input environment variables.

### Inputs

| Input                       | Description                                                                               | Default                                                                                     |
|-----------------------------|-------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `artifactory-deploy-repo`   | Deployment repository                                                                     | `sonarsource-private-qa` for private repositories, `sonarsource-public-qa` for public repos |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                           | `private-reader` for private repos, `public-reader` for public repos                        |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                         | `qa-deployer` for private repos, `public-deployer` for public repos                         |
| `deploy`                    | Whether to deploy on master, maintenance, dogfood and long-lived branches                 | `true`                                                                                      |
| `deploy-pull-request`       | Whether to also deploy for pull requests. If deploy is false, this has no effect.         | `false`                                                                                     |
| `skip-tests`                | Whether to skip running tests                                                             | `false`                                                                                     |
| `use-develocity`            | Whether to use Develocity for build tracking                                              | `false`                                                                                     |
| `gradle-args`               | Additional arguments to pass to Gradle                                                    | (optional)                                                                                  |
| `develocity-url`            | URL for Develocity                                                                        | `https://develocity.sonar.build/`                                                           |
| `repox-url`                 | URL for Repox                                                                             | `https://repox.jfrog.io`                                                                    |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)               | (optional)                                                                                  |
| `sonar-platform`            | SonarQube variant - 'next', 'sqc-eu', 'sqc-us', or 'none'. Use 'none' to skip sonar scans | `next`                                                                                      |
| `working-directory`         | Relative path under github.workspace to execute the build in                              | `.`                                                                                         |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding)            | `false`                                                                                     |
| `cache-paths`               | Custom cache paths (multiline).                                                           | `~/.gradle/caches`<br>`~/.gradle/wrapper`                                                   |
| `disable-caching`           | Whether to disable Gradle caching entirely                                                | `false`                                                                                     |
| `provenance`                | Whether to generate provenance attestation for built artifacts                            | `false`                                                                                     |
| `provenance-artifact-paths` | Relative paths of artifacts for provenance attestation (glob pattern). See [Provenance Attestation](#provenance-attestation) | (optional)                                                                                  |

> [!TIP]
> When using `working-directory`, Java must be available at root due to a limitation
> of [setup-gradle](https://github.com/gradle/actions/tree/main/setup-gradle).
> For instance, if the `mise.toml` file is in the working directory, and not at root.
>
> ```yaml
>      - name: Workaround for setup-gradle which has no working-directory input
>        run: |
>          cp <working-directory>/mise.toml mise.toml
>      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
>        with:
>          version: 2025.11.1
>      - uses: SonarSource/ci-github-actions/build-gradle@v1
>        with:
>          working-directory: <working-directory>
> ```

### Outputs

| Output            | Description                                                               |
|-------------------|---------------------------------------------------------------------------|
| `project-version` | The project version from gradle.properties                                |
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER` |
| `deployed`        | `true` if the build succeed and was supposed to deploy                    |

### Features

- Uses the gradle wrapper (`./gradlew`) by default and falls back to the `gradle` binary in case it is not found
- Automated version management with build numbers
- SonarQube analysis for code quality with multi-platform support
- Unified platform dogfooding - analyze across all 3 SonarQube platforms (next, sqc-eu, sqc-us)
- Automatic deployment prevention during shadow scans to avoid duplicate artifacts
- Conditional deployment based on branch patterns
- Automatic artifact signing with credentials from Vault
- Pull request support with optional deployment
- Develocity integration for build scans
- Gradle caching with customization options
- Comprehensive build logging and error handling

### Caching Configuration

By default, Gradle caches `~/.gradle/caches` and `~/.gradle/wrapper`. You can customize this behavior:

**Cache custom directories:**

```yaml
- uses: SonarSource/ci-github-actions/build-gradle@v1
  with:
    cache-paths: |
      ~/.gradle/caches
      ~/.gradle/wrapper
      ~/custom/directory
```

**Disable caching entirely:**

```yaml
- uses: SonarSource/ci-github-actions/build-gradle@v1
  with:
    disable-caching: 'true'
```

### Repox Authentication

The action configures Repox authentication using [repoxAuth.init.gradle.kts](build-gradle/resources/repoxAuth.init.gradle.kts) Gradle hook.

Follow [the xtranet/Developer Box documentation](https://xtranet-sonarsource.atlassian.net/wiki/spaces/DEV/pages/776711/Developer+Box) for
the developer local setup.

The Gradle project must be configured to use Repox for dependency resolution and deployment.

See for instance the configuration in <https://github.com/SonarSource/sonar-dummy-gradle-oss>.

`gradle.properties`:

```properties
group=org.sonarsource.dummy
version=2.8-SNAPSHOT
projectType=application
org.gradle.caching=true
```

`build.gradle`:

```groovy
// Replaces the version defined in sources, usually x.y-SNAPSHOT, by a version identifying the build.
def buildNumber = System.getProperty("buildNumber")
if (version.endsWith('-SNAPSHOT') && buildNumber != null) {
  version = version.replace('-SNAPSHOT', ".0.$buildNumber")
}

repositories {
  mavenLocal()
  mavenCentral()
  maven {
    url System.env.'ARTIFACTORY_URL' + '/sonarsource'
  }
}

artifactory {
  clientConfig.setIncludeEnvVars(true)
  clientConfig.setEnvVarsExcludePatterns('*password*,*PASSWORD*,*secret*,*MAVEN_CMD_LINE_ARGS*,sun.java.command,*token*,*TOKEN*,*LOGIN*,*login*,*signing*')
  contextUrl = System.getenv('ARTIFACTORY_URL')
  publish {
    repository {
      repoKey = System.getenv('ARTIFACTORY_DEPLOY_REPO')
      username = System.getenv('ARTIFACTORY_DEPLOY_USERNAME')
      password = System.getenv('ARTIFACTORY_DEPLOY_ACCESS_TOKEN')
    }
    defaults {
      properties = [
        'build.name'      : 'sonar-dummy-gradle-oss',
        'build.number'    : System.getenv('BUILD_NUMBER'),
        'pr.branch.target': System.getenv('PULL_REQUEST_BRANCH_TARGET'),
        'pr.number'       : System.getenv('PULL_REQUEST_NUMBER'),
        'vcs.branch'      : System.getenv('GIT_BRANCH'),
        'vcs.revision'    : System.getenv('GIT_COMMIT'),
        'version'         : version
      ]
      publications('mavenJava')
      publishPom = true
      publishIvy = false
    }
    clientConfig.info.addEnvironmentProperty('ARTIFACTS_TO_PUBLISH', 'org.sonarsource.dummy:sonar-dummy-gradle-oss-plugin:jar,org.sonarsource.dummy:sonar-dummy-gradle-oss-plugin:json:cyclonedx')
  }

  clientConfig.info.setBuildName('sonar-dummy-gradle-oss')
  clientConfig.info.setBuildNumber(System.getenv('BUILD_NUMBER'))
  clientConfig.info.addEnvironmentProperty('PROJECT_VERSION', "${version}")
}
```

## `config-npm`

Configure NPM and JFrog build environment with build number, authentication, and settings.

Set the project version in `package.json` with the build number if the file exists.

> **Note:** This action automatically calls [`get-build-number`](#get-build-number) to manage the build number.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies

#### Other Dependencies

The Node.js and NPM tools must be pre-installed. Use of `mise` is recommended.

### Usage

```yaml
config:
  runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
  name: Build
  permissions:
    id-token: write
    contents: write
  steps:
    - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
    - uses: jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac # v2.4.4
      with:
        version: 2025.11.1
    - uses: SonarSource/ci-github-actions/config-npm@v1
```

### Input Environment Variables

| Environment Variable                    | Description                                                                          |
|-----------------------------------------|--------------------------------------------------------------------------------------|
| `BUILD_NUMBER`                          | If present, it will be reused by the [`get-build-number`](#get-build-number) action. |
| `CURRENT_VERSION` and `PROJECT_VERSION` | If both are set, they will be used as-is and no version update will be performed.    |

See also [`get-build-number`](#get-build-number) input environment variables.

### Inputs

| Input                     | Description                                                                 | Default                                                              |
|---------------------------|-----------------------------------------------------------------------------|----------------------------------------------------------------------|
| `working-directory`       | Relative path under github.workspace to execute the build in                | `.`                                                                  |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault                             | `private-reader` for private repos, `public-reader` for public repos |
| `cache-npm`               | Whether to cache NPM dependencies                                           | `true`                                                               |
| `repox-url`               | URL for Repox                                                               | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`   | URL for Repox Artifactory API (overrides repox-url/artifactory if provided) | (optional)                                                           |

### Outputs

| Output            | Description                                               |
|-------------------|-----------------------------------------------------------|
| `current-version` | The project version from package.json                     |
| `project-version` | The project version with build number (after replacement) |
| `BUILD_NUMBER`    | The current build number                                  |

### Output Environment Variables

| Environment Variable | Description                                               |
|----------------------|-----------------------------------------------------------|
| `CURRENT_VERSION`    | The project version from package.json                     |
| `PROJECT_VERSION`    | The project version with build number (after replacement) |

See also [`get-build-number`](#get-build-number) output environment variables.

## `build-npm`

Build, test, analyze with SonarQube, and deploy an NPM project to JFrog Artifactory.

> **Note:** This action automatically calls [`config-npm`](#config-npm) to set up the NPM environment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

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

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true # or ${{ github.ref_name != github.event.repository.default_branch }}

jobs:
  build:
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: SonarSource/ci-github-actions/build-npm@v1
        with:
          # Enable shadow scans for unified platform dogfooding (optional)
          run-shadow-scans: 'true'
          # Primary platform when shadow scans disabled (optional)
          sonar-platform: 'next'
```

### Input Environment Variables

| Environment Variable                    | Description                                                                       | Default |
|-----------------------------------------|-----------------------------------------------------------------------------------|---------|
| `SQ_SCANNER_VERSION`                    | SonarQube scanner version.                                                        | '4.3.0' |

See also [`config-npm`](#config-npm) input environment variables.

### Inputs

| Input                       | Description                                                                    | Default                                                                                      |
|-----------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `working-directory`         | Relative path under github.workspace to execute the build in                   | `.`                                                                                          |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                | `private-reader` for private repos, `public-reader` for public repos                         |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                              | `qa-deployer` for private repos, `public-deployer` for public repos                          |
| `artifactory-deploy-repo`   | Deployment repository                                                          | `sonarsource-private-qa` for private repositories, `sonarsource-public-qa` for public repos  |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                | `private-reader` for private repos, `public-reader` for public repos                         |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                              | `sonarsource-npm-private-qa` for private repos, `sonarsource-npm-public-qa` for public repos |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                       | `false`                                                                                      |
| `skip-tests`                | Whether to skip running tests                                                  | `false`                                                                                      |
| `cache-npm`                 | Whether to cache NPM dependencies                                              | `true`                                                                                       |
| `repox-url`                 | URL for Repox                                                                  | `https://repox.jfrog.io`                                                                     |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)    | (optional)                                                                                   |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us'                     | `next`                                                                                       |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding) | `false`                                                                                      |
| `build-name`                | Name of the JFrog build to publish.                                            | `<Repository name>`                                                                          |
| `provenance`                | Whether to generate provenance attestation for built artifacts                 | `false`                                                                                      |
| `provenance-artifact-paths` | Relative paths of artifacts for provenance attestation (glob pattern). See [Provenance Attestation](#provenance-attestation) | (optional)                                                                                   |

### Outputs

| Output            | Description                                               |
|-------------------|-----------------------------------------------------------|
| `current-version` | The project version from package.json                     |
| `project-version` | The project version with build number (after replacement) |
| `BUILD_NUMBER`    | The current build number                                  |
| `deployed`        | `true` if the build succeed and was supposed to deploy    |

### Output Environment Variables

| Environment Variable | Description              |
|----------------------|--------------------------|
| `BUILD_NUMBER`       | The current build number |

See also [`config-npm`](#config-npm) output environment variables.

### Features

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality with multi-platform support
- Unified platform dogfooding - analyze across all 3 SonarQube platforms (next, sqc-eu, sqc-us)
- Automatic deployment prevention during shadow scans to avoid duplicate artifacts
- Conditional deployment based on branch patterns
- NPM dependency caching for faster builds (configurable)
- Pull request support with optional deployment
- JFrog build info publishing with UI links
- Support for different branch types (default, maintenance, PR, dogfood, long-lived feature)
- Comprehensive build logging and error handling

## `build-yarn`

Build, test, analyze, and deploy a Yarn project with SonarQube integration and Artifactory deployment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

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

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true # or ${{ github.ref_name != github.event.repository.default_branch }}

jobs:
  build:
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: SonarSource/ci-github-actions/build-yarn@v1
        with:
          # Enable shadow scans for unified platform dogfooding (optional)
          run-shadow-scans: 'true'
          # Primary platform when shadow scans disabled (optional)
          sonar-platform: 'next'
```

### Input Environment Variables

| Environment Variable                    | Description                                                                       | Default |
|-----------------------------------------|-----------------------------------------------------------------------------------|---------|
| `SQ_SCANNER_VERSION`                    | SonarQube scanner version.                                                        | '4.3.0' |

### Inputs

| Input                       | Description                                                                                                                  | Default                                                                                     |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `working-directory`         | Relative path under github.workspace to execute the build in                                                                 | `.`                                                                                         |
| `public`                    | Deprecated                                                                                                                   | Repository visibility                                                                       |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                                                              | `private-reader` for private repos, `public-reader` for public repos                        |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                                                            | `qa-deployer` for private repos, `public-deployer` for public repos                         |
| `artifactory-deploy-repo`   | Deployment repository                                                                                                        | `sonarsource-private-qa` for private repositories, `sonarsource-public-qa` for public repos |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                                                                     | `false`                                                                                     |
| `skip-tests`                | Whether to skip running tests                                                                                                | `false`                                                                                     |
| `cache-yarn`                | Whether to cache Yarn dependencies                                                                                           | `true`                                                                                      |
| `repox-url`                 | URL for Repox                                                                                                                | `https://repox.jfrog.io`                                                                    |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                  | (optional)                                                                                  |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', 'sqc-us', or 'none'. Use 'none' to skip sonar scans                           | `next`                                                                                      |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding)                                               | `false`                                                                                     |
| `provenance`                | Whether to generate provenance attestation for built artifacts                                                               | `false`                                                                                     |
| `provenance-artifact-paths` | Relative paths of artifacts for provenance attestation (glob pattern). See [Provenance Attestation](#provenance-attestation) | (optional)                                                                                  |

### Outputs

| Output            | Description                                               |
|-------------------|-----------------------------------------------------------|
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER` |
| `project-version` | The project version from package.json                     |
| `deployed`        | `true` if the build succeed and was supposed to deploy    |

### Features

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality with multi-platform support
- Unified platform dogfooding - analyze across all 3 SonarQube platforms (next, sqc-eu, sqc-us)
- Automatic deployment prevention during shadow scans to avoid duplicate artifacts
- Conditional deployment based on branch patterns
- Yarn dependency caching for faster builds (configurable)
- Pull request support with optional deployment
- JFrog build info publishing with UI links
- Support for different branch types (default, maintenance, PR, dogfood, long-lived feature)
- Comprehensive build logging and error handling

## `config-pip`

Configure pip build environment with build number, authentication, and default settings.

This action configures pip to pull packages from the internal JFrog Artifactory registry instead of the default PyPI.

> **Note:** This action automatically calls [`get-build-number`](#get-build-number) to manage the build number.
> **Note:** This action replaces the deprecated `configure-pipx-repox` action from `sonarqube-cloud-github-actions` repository.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: read`

#### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.

### Usage

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  - uses: actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065 # v5.6.0
    with:
      python-version: 3.12
  - uses: SonarSource/ci-github-actions/config-pip@v1
  - run: pip install pipenv
```

### With Custom Artifactory Reader Role

```yaml
steps:
  - uses: SonarSource/ci-github-actions/config-pip@v1
    with:
      artifactory-reader-role: custom-reader
```

### With Working Directory and Caching Options

```yaml
steps:
  - uses: SonarSource/ci-github-actions/config-pip@v1
    with:
      working-directory: ./python-project
      disable-caching: false
```

### Inputs

| Input                     | Description                                                                 | Default                                                              |
|---------------------------|-----------------------------------------------------------------------------|----------------------------------------------------------------------|
| `working-directory`       | Relative path under github.workspace to execute the build in                | `.`                                                                  |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault                             | `private-reader` for private repos, `public-reader` for public repos |
| `repox-url`               | URL for Repox                                                               | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`   | URL for Repox Artifactory API (overrides repox-url/artifactory if provided) | (optional)                                                           |
| `cache-paths`             | Cache paths to use (multiline)                                              | `~/.cache/pip`                                                       |
| `disable-caching`         | Whether to disable pip caching entirely                                     | `false`                                                              |

### Outputs

| Output         | Description                                                               |
|----------------|---------------------------------------------------------------------------|
| `BUILD_NUMBER` | The current build number. Also set as environment variable `BUILD_NUMBER` |

### Output Environment Variables

| Environment Variable | Description              |
|----------------------|--------------------------|
| `BUILD_NUMBER`       | The current build number |

See also [`get-build-number`](#get-build-number) output environment variables.

### Features

- Build number management via [`get-build-number`](#get-build-number)
- Automatic Artifactory authentication via Vault
- Auto-detection of reader role based on repository visibility
- Pip dependency caching with customization options
- Global pip configuration for all subsequent `pip install` commands

### Migration from configure-pipx-repox

If you're currently using `SonarSource/sonarqube-cloud-github-actions/configure-pipx-repox@master`, you can replace it with:

```yaml
# Old
- uses: SonarSource/sonarqube-cloud-github-actions/configure-pipx-repox@master

# New
- uses: SonarSource/ci-github-actions/config-pip@v1
```

Both actions produce the same configuration and are functionally equivalent.

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
- `buildInfo.env.PROJECT_VERSION`: Version of the project (e.g. 1.2.3). Can also be set as an environment variable to override the build
  info value.

### Usage

**Basic usage (version from JFrog build info):**

```yaml
promote:
  needs:
    - build
  runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
  name: Promote
  permissions:
    id-token: write
    contents: write
  steps:
    - uses: SonarSource/ci-github-actions/promote@v1
```

**With custom project version:**

```yaml
promote:
  needs:
    - build
  runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
  name: Promote
  permissions:
    id-token: write
    contents: write
  env:
    PROJECT_VERSION: '2.0.0-custom'  # Override version from JFrog build info
  steps:
    - uses: SonarSource/ci-github-actions/promote@v1
```

### Input Environment Variables

| Environment Variable | Description                                                                                                               |
|----------------------|---------------------------------------------------------------------------------------------------------------------------|
| `PROJECT_VERSION`    | Version of the project (e.g. 1.2.3). If set, it takes precedence over the version from JFrog build info.                 |

### Inputs

| Input                     | Description                                                                                                               | Default             |
|---------------------------|---------------------------------------------------------------------------------------------------------------------------|---------------------|
| `promote-pull-request`    | Whether to promote pull request artifacts. Requires `deploy-pull-request` input to be set to `true` in the build action   | `false`             |
| `multi-repo`              | If true, promotes to public and private repositories. For projects with both public and private artifacts                 | (optional)          |
| `artifactory-deploy-repo` | Repository to deploy to. If not set, it will be retrieved from the build info                                             | (optional)          |
| `artifactory-target-repo` | Target repository for the promotion. If not set, it will be determined based on the branch type and the deploy repository | (optional)          |
| `build-name`              | Name of the JFrog build to promote.                                                                                       | `<Repository name>` |

### Outputs

This action does not provide any outputs.

### Features

- Automatic promotion of build artifacts in JFrog Artifactory
- GitHub status check updates with promotion status
- Support for both single and multi-repository promotions
- Automatic target repository determination based on branch type
- Pull request artifact promotion support

---

## `pr_cleanup`

Automatically clean up caches and artifacts associated with a pull request when it is closed.

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
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
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

## `code-signing`

Install and configure DigiCert smctl and jsign tools for code signing with caching support.

This action provides a complete setup for DigiCert's SigningManager tools (smctl) and jsign with intelligent caching
to avoid re-downloading tools on every run. It handles all DigiCert authentication setup and environment configuration.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: read`

#### Required Vault Permissions

- `development/kv/data/sign/digicert`: DigiCert signing credentials including:
  - `apikey`: DigiCert API key for downloading tools
  - `client_cert_file_base64`: Base64-encoded client certificate
  - `cert_fp`: Certificate fingerprint (SHA1 hash)
  - `client_cert_password`: Client certificate password
  - `host`: DigiCert SigningManager host URL

#### Other Dependencies

- Linux runner
- Java installed

### Usage

```yaml
    steps:
      - build:
        # Build artifacts
      - name: Setup DigiCert Client Tools
        uses: SonarSource/ci-github-actions/code-signing@v1
      - name: Sign artifacts
        run: |
          # smctl and jsign are now available and configured, use them in run block or in your custom scripts
          smctl sign --keypair-alias=key_525594307 --config-file "${SMTOOLS_PATH}/pkcs11properties.cfg" --input ${fileToSign}.dll --tool jsign
```

### Inputs

| Input                  | Description                                                     | Default |
|------------------------|-----------------------------------------------------------------|---------|
| `jsign-version`        | Version of jsign to install                                     | `7.2`   |
| `force-download-tools` | Force download both DigiCert and jsign tools (disables caching) | `false` |

### Environment Variables Set

After running this action, the following environment variables are available:

- `SM_HOST`: DigiCert SigningManager host URL
- `SM_API_KEY`: DigiCert API key
- `SM_CLIENT_CERT_FILE`: Path to the decoded client certificate file
- `SM_CLIENT_CERT_PASSWORD`: Client certificate password
- `SM_CODE_SIGNING_CERT_SHA1_HASH`: Certificate fingerprint for signing
- `SMTOOLS_PATH`: Path where SMTools are installed, certificate and `.cfg` file is stored.

### Features

- **Official DigiCert Integration**: Uses the official DigiCert `ssm-code-signing` action for reliable smctl installation
- **Unified Caching Strategy**: Single cache key for both smctl and jsign tools to optimize cache efficiency
- **Smart Cache Management**: Caches smctl installation directory and jsign .deb package for faster subsequent runs
- **Automatic Setup**: Handles all DigiCert authentication and environment configuration

## Provenance Attestation

The build actions in this repository can automatically generate SLSA build provenance
attestations for produced artifacts when the build is considered deployable. This feature is
powered by [`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance).

Attestations identify the artifact(s) that serve as the subject of the attestation. The `build-*` actions
attempt to discover these subjects automatically using conventional build output locations and
common file types for each ecosystem. Automatic discovery runs only when deployment is enabled.
The attestation step runs when `provenance` parameter is enabled and artifact paths are available (either via
`provenance-artifact-paths` or from the build output); otherwise, it is skipped.

### Ecosystem assumptions (automatic discovery)

- Gradle
  - Locations: `**/build/libs/**`, `**/build/distributions/**`, `**/build/reports/**` (for SBOM JSONs)
  - File types: `*.jar`, `*.war`, `*.ear`, `*.zip`, `*.tar.gz`, `*.tar`, `*.json`
  - Exclusions: `*-sources.jar`, `*-javadoc.jar`, `*-tests.jar`

- Maven
  - Location: `**/<project.build.directory>/**` (queried via Maven); falls back to `target/`
  - File types: `*.jar`, `*.war`, `*.ear`, `*.zip`, `*.tar.gz`, `*.tar`, `*.pom`, `*.json`
  - Exclusions: `*-sources.jar`, `*-javadoc.jar`, `*-tests.jar`
  - Skip rule: if `maven.deploy.skip=true` is effective, attestation is skipped for that module

- Poetry (Python)
  - Location: `dist/`
  - File types: `*.whl`, `*.tar.gz`, `*.json`

- NPM
  - Location: `.attestation-artifacts/`
  - File types: `*.tgz`

- Yarn
  - Location: `.attestation-artifacts/`
  - File types: `*.tgz`

These assumptions are based on widely-used industry conventions and on how artifacts are currently
published to our Artifactory. They should cover most repositories, but they are not exhaustive. If
needed, you can customize the paths via the `provenance-artifact-paths` input.

### Manually specify subjects when needed

For complete accuracy, we recommend explicitly specifying the artifacts to attest using the
`provenance-artifact-paths` input. Repository owners know best what their build produces, so
providing explicit paths might be sometimes preferable. `provenance-artifact-paths` is passed to
`actions/attest-build-provenance` as the `subject-path` input. It may be a glob pattern or a
newline-separated list of paths (total subject count cannot exceed 1024). See upstream docs for
details and more examples: [`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance).

Example with a build action (same idea applies to other actions):

```yaml
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    provenance-artifact-paths: |
      target/*.jar
      target/*bom.json
```

---

## Release

1. Create a new GitHub release on <https://github.com/SonarSource/ci-github-actions/releases>

    Increase the **patch** number for **fixes**, the **minor** number for **new features**, and the **major** number for **breaking changes**.

    Edit the generated release notes to curate the highlights and key fixes. Make sure that the notes are clear and informative.

    ```markdown
    ## What's Changed
    ### New Features
    * BUILD-... by @username in https://github.com/SonarSource/ci-github-actions/pull/...

    ### Improvements
    * ...

    ### Bug Fixes
    * ...

    ### Documentation
    * ...

    ## New Contributors
    * ...

   ---

   Additional notes, examples, or references if applicable.

    **Full Changelog**: https://github.com/SonarSource/ci-github-actions/compare/...
   ```

   Make sure to include any **breaking changes** in the notes.

2. After release, the `v*` branch must be updated for pointing to the new tag.

    ```shell
    git fetch --tags
    git update-ref -m "reset: update branch v1 to tag 1.y.z" refs/heads/v1 1.y.z
    git push origin v1
    ```

3. Communicate the new release on the Slack [#ask-github-migration](https://sonarsource.enterprise.slack.com/archives/C09791CRUKF) channel.
   > 🚀 **New release `1.y.z` of `ci-github-actions` is live!** 🚀
   >
   > The v1 branch has been updated, so workflows using `@v1` will automatically receive these improvements.
   >
   > ---
   >
   > ### ✨ What's New
   >
   > - _Curated highlights from release notes: new features, important new options_
   >
   > ### 🚀 Improvements
   >
   > - _Curated highlights from release notes: improvement and upgrades_
   >
   > ### 🐛 Bug Fixes
   >
   > - _Curated highlights from release notes_
   >
   > ### 📚 Documentation
   >
   > - _Curated highlights from release notes_
   >
   >
   > For all the details, you can
   > [read the full release notes on GitHub](https://github.com/SonarSource/ci-github-actions/releases/tag/1.y.z).
