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
- [`build-gradle`](#build-gradle)
- [`config-npm`](#config-npm)
- [`build-npm`](#build-npm)
- [`build-yarn`](#build-yarn)
- [`promote`](#promote)
- [`pr_cleanup`](#pr_cleanup)
- [`cache`](#cache)
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
    runs-on: github-ubuntu-latest-s
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

Call [`get-build-number`](#get-build-number).

Configure Maven build environment with build number, authentication, and default settings.

This action sets up the complete Maven environment for SonarSource projects, including:

- Build number management and project version configuration
- Artifactory authentication and repository setup
- Maven settings configuration for Repox
- Maven local repository caching
- Common Maven flags and JVM options
- Sets the project version by replacing `-SNAPSHOT` with the build number

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
  - uses: actions/checkout@v5
  - uses: SonarSource/ci-github-actions/config-maven@v1
  - run: mvn verify
```

### Input Environment Variables

| Environment Variable                    | Description                                                                       |
|-----------------------------------------|-----------------------------------------------------------------------------------|
| `CURRENT_VERSION` and `PROJECT_VERSION` | If both are set, they will be used as-is and no version update will be performed. |
| `MAVEN_OPTS`                            | JVM options for Maven execution. Defaults to `-Xmx1536m -Xms128m` if not set.     |
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
| `develocity-url`          | URL for Develocity                                                          | `https://develocity.sonar.build/`                                                                                       |

### Outputs

| Output            | Description                                                                                                     |
|-------------------|-----------------------------------------------------------------------------------------------------------------|
| `BUILD_NUMBER`    | The current build number. Also set as environment variable `BUILD_NUMBER`                                       |
| `current-version` | The project version set in the pom.xml (before replacement). Also set as environment variable `CURRENT_VERSION` |
| `project-version` | The project version with build number (after replacement). Also set as environment variable `PROJECT_VERSION`   |

### Output Environment Variables

| Environment Variable          | Description                                                                                                                               |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `ARTIFACTORY_ACCESS_TOKEN`    | Access token for Artifactory authentication                                                                                               |
| `ARTIFACTORY_ACCESS_USERNAME` | Deprecated alias for `ARTIFACTORY_USERNAME`                                                                                               |
| `ARTIFACTORY_USERNAME`        | Username for Artifactory authentication                                                                                                   |
| `ARTIFACTORY_PASSWORD`        | Deprecated alias for `ARTIFACTORY_ACCESS_TOKEN`                                                                                           |
| `ARTIFACTORY_URL`             | Artifactory (Repox) URL. E.x.: `https://repox.jfrog.io/artifactory`                                                                       |
| `BASH_ENV`                    | Path to the bash profile with mvn function for adding common flags to Maven calls                                                         |
| `CURRENT_VERSION`             | The original project version from pom.xml                                                                                                 |
| `DEVELOCITY_ACCESS_KEY`       | The Develocity access key when `use-develicty` is true                                                                                    |
| `MAVEN_OPTS`                  | JVM options for Maven execution.                                                                                                          |
| `PROJECT_VERSION`             | The project version with build number (after replacement)                                                                                 |
| `SONARSOURCE_REPOSITORY_URL`  | URL for SonarSource Artifactory root virtual repository (i.e.: `sonarsource-qa` for public builds or `sonarsource-qa` for private builds) |
| `CONFIG_MAVEN_COMPLETED`      | For internal use. If set, the action is skipped                                                                                           |

See also [`get-build-number`](#get-build-number) output environment variables.

### Environment Variables Set

After running this action, the following environment variables are available:

- `ARTIFACTORY_ACCESS_TOKEN`: Access token for Artifactory authentication
- `ARTIFACTORY_ACCESS_USERNAME`: Deprecated alias for `ARTIFACTORY_USERNAME`
- `ARTIFACTORY_PASSWORD`: Deprecated alias for `ARTIFACTORY_ACCESS_TOKEN`
- `ARTIFACTORY_URL`: Artifactory (Repox) URL. E.x.: `https://repox.jfrog.io/artifactory`
- `ARTIFACTORY_USERNAME`: Username for Artifactory authentication
- `BASH_ENV`: Path to the bash profile with mvn function for adding common flags to Maven calls
- `BUILD_NUMBER`: The current build number
- `CURRENT_VERSION`: The original project version from pom.xml
- `DEVELOCITY_ACCESS_KEY`: The Develocity access key when use-develicty is true
- `MAVEN_OPTS`: JVM options for Maven execution. Defaults to `-Xmx1536m -Xms128m` by default
- `PROJECT_VERSION`: The project version with build number appended
- `SONARSOURCE_REPOSITORY_URL`: URL for SonarSource Artifactory root virtual repository (i.e.: sonarsource-qa for public builds or
  sonarsource-qa for private builds)

## `build-maven`

Call [`config-maven`](#config-maven).

Build and deploy a Maven project with SonarQube analysis and Artifactory deployment.

### Required GitHub Permissions

- `id-token: write`
- `contents: write`

### Required Vault Permissions

- `public-reader` or `private-reader`: Artifactory role for reading dependencies.
- `public-deployer` or `qa-deployer`: Artifactory role for deployment.
- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on
  sonar-platform)
- `development/kv/data/sign`: Artifact signing credentials (key and passphrase).
- `development/kv/data/develocity`: Develocity access token (if using Develocity).

### Other Dependencies

- The Java and Maven tools must be pre-installed. Use of `mise` is recommended.
- The "Sonar parent POM" (`[org|com].sonarsource.parent:parent`) must be used. There's a public POM (org) and a private POM (com),
  respectively for public or private code.

### Usage

```yaml
permissions:
  id-token: write
  contents: write
steps:
  - uses: actions/checkout@v5
  - uses: SonarSource/ci-github-actions/config-maven@v1
  - uses: SonarSource/ci-github-actions/build-maven@v1
```

### Input Environment Variables

See also [`config-maven`](#config-maven) input environment variables.

### Inputs

| Input                         | Description                                                                                                                | Default                                                              |
|-------------------------------|----------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `artifactory-reader-role`     | Suffix for the Artifactory reader role in Vault                                                                            | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role`   | Suffix for the Artifactory deployer role in Vault                                                                          | `qa-deployer` for private repos, `public-deployer` for public repos  |
| `deploy-pull-request`         | Whether to deploy pull request artifacts                                                                                   | `false`                                                              |
| `maven-args`                  | Additional arguments to pass to Maven                                                                                      | (optional)                                                           |
| `scanner-java-opts`           | Additional Java options for the Sonar scanner (`SONAR_SCANNER_JAVA_OPTS`)                                                  | `-Xmx512m`                                                           |
| `repox-url`                   | URL for Repox                                                                                                              | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`       | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                | (optional)                                                           |
| `use-develocity`              | Whether to use Develocity for build tracking                                                                               | `false`                                                              |
| `develocity-url`              | URL for Develocity                                                                                                         | `https://develocity.sonar.build/`                                    |
| `sonar-platform`              | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us'                                                                 | `next`                                                               |
| `working-directory`           | Relative path under github.workspace to execute the build in                                                               | `.`                                                                  |
| `run-shadow-scans`            | If true, run SonarQube analysis on all 3 platforms (next, sqc-eu, sqc-us); if false, only on the selected `sonar-platform` | `false`                                                              |

### Outputs

| Output         | Description                                                               |
|----------------|---------------------------------------------------------------------------|
| `BUILD_NUMBER` | The current build number. Also set as environment variable `BUILD_NUMBER` |

### Output Environment Variables

See also [`config-maven`](#config-maven) output environment variables.

### Features

- Build context detection with automatic deployment strategies
- SonarQube analysis with credentials from Vault
- Artifact signing with GPG keys from Vault
- Conditional deployment based on branch patterns
- Develocity integration for build optimization (optional)
- Support for different branch types:
  - **master**: Deploy + SonarQube analysis with full profiles
  - **maintenance** (`branch-*`): Deploy with full profiles + separate SonarQube analysis
  - **pr**: Conditional deployment with SonarQube analysis
  - **dogfood** (`dogfood-on-*`): Deploy only with dogfood profiles
  - **feature** (`feature/long/*`): Verify + SonarQube analysis only
  - **default**: Basic verify goal only

## `build-poetry`

Build, analyze, and publish a Python project using Poetry with SonarQube integration and Artifactory deployment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`, `development/kv/data/sonarcloud`, or `development/kv/data/sonarqube-us`: SonarQube credentials (based on
  sonar-platform)
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
    runs-on: github-ubuntu-latest-s
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0
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

### Inputs

| Input                       | Description                                                                                                                                                                                   | Default                                                              |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `public`                    | Whether to build and deploy with/to public repositories                                                                                                                                       | Auto-detected from repository visibility                             |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                                                                                                                               | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                                                                                                                             | `qa-deployer` for private repos, `public-deployer` for public repos  |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                                                                                                                                      | `false`                                                              |
| `poetry-virtualenvs-path`   | Path to the Poetry virtual environments, relative to GitHub workspace                                                                                                                         | `.cache/pypoetry/virtualenvs`                                        |
| `poetry-cache-dir`          | Path to the Poetry cache directory, relative to GitHub workspace                                                                                                                              | `.cache/pypoetry`                                                    |
| `repox-url`                 | URL for Repox                                                                                                                                                                                 | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                                                                                   | (optional)                                                           |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', sqc-us, or 'none'. Use 'none' to skip sonar scans                                                                                              | `next`                                                               |
| `run-shadow-scans`          | If true, run sonar scanner on all 3 platforms using the provided URL and token. If false, run on the platform provided by sonar-platform. When enabled, the sonar-platform setting is ignored | `false`                                                              |
| `working-directory`         | Relative path under github.workspace to execute the build in                                                                                                                                  | `.`                                                                  |

### Outputs

- `project-version`: The project version from pyproject.toml with build number. The same is also exposed as `PROJECT_VERSION` environment
  variable.

## `build-gradle`

Build and publish a Gradle project with SonarQube analysis and Artifactory deployment.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`: SonarQube credentials for next platform
- `development/kv/data/sonarcloud`: SonarQube credentials for sqc-eu platform
- `development/kv/data/sonarqube-us`: SonarQube credentials for sqc-us platform
- `development/kv/data/sign`: Artifact signing credentials (key, passphrase, and key_id)
- `development/kv/data/develocity`: Develocity access token if `use-develocity: true`
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

**Note**: Credentials for all three SonarQube platforms are always required, regardless of the `run-shadow-scans` setting.

#### Other Dependencies

**Java**: Not pre-installed in the runner image. We recommend using `mise` to install and manage Java versions.

**Gradle**: Not pre-installed in the runner image. We recommend including the Gradle wrapper (`gradlew`) in your repository, which will be
used automatically. If the Gradle wrapper is not available, you can install Gradle using `mise` in your pipeline.

**Additional Configuration**: The Gradle Artifactory plugin configuration is required in your `build.gradle` file.

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
    runs-on: github-ubuntu-latest-s
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0
      - uses: SonarSource/ci-github-actions/build-gradle@v1
        with:
          # Enable shadow scans for unified platform dogfooding (optional)
          run-shadow-scans: 'true'
          # Primary platform when shadow scans disabled (optional)
          sonar-platform: 'next'
```

### Inputs

| Input                       | Description                                                                    | Default                                                              |
|-----------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `public`                    | Whether to build and deploy with/to public repositories                        | Auto-detected from repository visibility                             |
| `artifactory-deploy-repo`   | Name of deployment repository                                                  | Auto-detected based on repository visibility                         |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                              | `qa-deployer` for private repos, `public-deployer` for public repos  |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                       | `false`                                                              |
| `skip-tests`                | Whether to skip running tests                                                  | `false`                                                              |
| `use-develocity`            | Whether to use Develocity for build tracking                                   | `false`                                                              |
| `gradle-args`               | Additional arguments to pass to Gradle                                         | (optional)                                                           |
| `develocity-url`            | URL for Develocity                                                             | `https://develocity.sonar.build/`                                    |
| `repox-url`                 | URL for Repox                                                                  | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)    | (optional)                                                           |
| `sonar-platform`            | SonarQube variant - 'next', 'sqc-eu', or 'sqc-us'                              | `next`                                                               |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding) | `false`                                                              |

### Outputs

| Output            | Description                                |
|-------------------|--------------------------------------------|
| `project-version` | The project version from gradle.properties |

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
- Comprehensive build logging and error handling

## `config-npm`

Call [`get-build-number`](#get-build-number).

Configure NPM and JFrog build environment with build number, authentication, and settings.
Set the project version in `package.json` with the build number.

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
  concurrency:
    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
  runs-on: github-ubuntu-latest-s
  name: Build
  permissions:
    id-token: write
    contents: write
  steps:
    - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
    - uses: jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac # v2.4.4
      with:
        version: 2025.7.12
    - uses: SonarSource/ci-github-actions/config-npm@v1
```

### Input Environment Variables

| Environment Variable                    | Description                                                                       |
|-----------------------------------------|-----------------------------------------------------------------------------------|
| `CURRENT_VERSION` and `PROJECT_VERSION` | If both are set, they will be used as-is and no version update will be performed. |

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

Call [`config-npm`](#config-npm).

Then build, test, analyze with SonarQube, and deploy an NPM project to JFrog Artifactory.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: write`

#### Required Vault Permissions

- `development/kv/data/next`: SonarQube credentials for next platform
- `development/kv/data/sonarcloud`: SonarQube credentials for sqc-eu platform
- `development/kv/data/sonarqube-us`: SonarQube credentials for sqc-us platform
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

**Note**: Credentials for all three SonarQube platforms are always required, regardless of the `run-shadow-scans` setting.

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
    runs-on: github-ubuntu-latest-s
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0
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

| Input                       | Description                                                                    | Default                                                              |
|-----------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `working-directory`         | Relative path under github.workspace to execute the build in                   | `.`                                                                  |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                              | `qa-deployer` for private repos, `public-deployer` for public repos  |
| `artifactory-deploy-repo`   | Name of deployment repository                                                  | Auto-detected based on repository visibility                         |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                       | `false`                                                              |
| `skip-tests`                | Whether to skip running tests                                                  | `false`                                                              |
| `cache-npm`                 | Whether to cache NPM dependencies                                              | `true`                                                               |
| `repox-url`                 | URL for Repox                                                                  | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)    | (optional)                                                           |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', or 'sqc-us'                     | `next`                                                               |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding) | `false`                                                              |
| `build-name`                | Name of the JFrog build to publish.                                            | `<Repository name>`                                                  |

### Outputs

| Output            | Description                                               |
|-------------------|-----------------------------------------------------------|
| `current-version` | The project version from package.json                     |
| `project-version` | The project version with build number (after replacement) |
| `BUILD_NUMBER`    | The current build number                                  |
| `build-info-url`  | The JFrog build info UI URL                               |

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

- `development/kv/data/next`: SonarQube credentials for next platform
- `development/kv/data/sonarcloud`: SonarQube credentials for sqc-eu platform
- `development/kv/data/sonarqube-us`: SonarQube credentials for sqc-us platform
- `public-reader` or `private-reader`: Artifactory role for reading dependencies
- `public-deployer` or `qa-deployer`: Artifactory role for deployment

**Note**: Credentials for all three SonarQube platforms are always required, regardless of the `run-shadow-scans` setting.

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
    runs-on: github-ubuntu-latest-s
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0
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

| Input                       | Description                                                                                        | Default                                                              |
|-----------------------------|----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `public`                    | Whether to build and deploy with/to public repositories                                            | Auto-detected from repository visibility                             |
| `artifactory-reader-role`   | Suffix for the Artifactory reader role in Vault                                                    | `private-reader` for private repos, `public-reader` for public repos |
| `artifactory-deployer-role` | Suffix for the Artifactory deployer role in Vault                                                  | `qa-deployer` for private repos, `public-deployer` for public repos  |
| `artifactory-deploy-repo`   | Name of deployment repository                                                                      | (optional)                                                           |
| `deploy-pull-request`       | Whether to deploy pull request artifacts                                                           | `false`                                                              |
| `skip-tests`                | Whether to skip running tests                                                                      | `false`                                                              |
| `cache-yarn`                | Whether to cache Yarn dependencies                                                                 | `true`                                                               |
| `repox-url`                 | URL for Repox                                                                                      | `https://repox.jfrog.io`                                             |
| `repox-artifactory-url`     | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                        | (optional)                                                           |
| `sonar-platform`            | SonarQube primary platform - 'next', 'sqc-eu', 'sqc-us', or 'none'. Use 'none' to skip sonar scans | `next`                                                               |
| `run-shadow-scans`          | Enable analysis across all 3 SonarQube platforms (unified platform dogfooding)                     | `false`                                                              |

### Outputs

| Output            | Description                           |
|-------------------|---------------------------------------|
| `project-version` | The project version from package.json |
| `build-info-url`  | The JFrog build info UI URL           |

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
  runs-on: github-ubuntu-latest-s
  name: Promote
  permissions:
    id-token: write
    contents: write
  steps:
    - uses: SonarSource/ci-github-actions/promote@v1
```

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
    runs-on: github-ubuntu-latest-s
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

### Requirements

#### Required Vault Permissions

No Vault permissions required for this action.

#### Other Dependencies

The only requirement for the action is `jq` installed.

### Usage

```yaml
jobs:
  build:
    runs-on: github-ubuntu-latest-s
    steps:
      - uses: SonarSource/ci-github-actions/cache@v1
        with:
          path: |
            ~/.cache/pip
            ~/.cache/maven
          key: cache-${{ runner.os }}-${{ hashFiles('**/requirements.txt', '**/pom.xml') }}
          restore-keys: cache-${{ runner.os }}-
```

### Inputs

| Input                  | Description                                                                                                  | Default    |
|------------------------|--------------------------------------------------------------------------------------------------------------|------------|
| `path`                 | A list of files, directories, and wildcard patterns to cache and restore                                     | (required) |
| `key`                  | An explicit key for restoring and saving the cache                                                           | (required) |
| `restore-keys`         | An ordered list of prefix-matched keys to use for restoring stale cache if no cache hit occurred for key     | (optional) |
| `upload-chunk-size`    | The chunk size used to split up large files during upload, in bytes                                          | (optional) |
| `enableCrossOsArchive` | When enabled, allows to save or restore caches that can be restored or saved respectively on other platforms | `false`    |
| `fail-on-cache-miss`   | Fail the workflow if cache entry is not found                                                                | `false`    |
| `lookup-only`          | Check if a cache entry exists for the given input(s) without downloading the cache                           | `false`    |

### Outputs

| Output      | Description                                                              |
|-------------|--------------------------------------------------------------------------|
| `cache-hit` | A boolean value to indicate an exact match was found for the primary key |

### Features

- Automatically uses GitHub Actions cache for public repositories
- Uses SonarSource S3 cache for private/internal SonarSource repositories
- Seamless API compatibility with standard GitHub Actions cache
- Supports all standard cache inputs and outputs
- Automatic repository visibility detection

### Cleanup Policy

The AWS S3 bucket lifecycle rules apply to delete the old files. The content from default branches expires in 60 days and for feature
branches in 30 days.

## `code-signing`

Install and configure DigiCert smctl and jsign tools for code signing with caching support.

This action provides a complete setup for DigiCert's SigningManager tools (smctl) and jsign with intelligent caching
to avoid re-downloading tools on every run. It handles all DigiCert authentication setup and environment configuration.

### Requirements

#### Required GitHub Permissions

- `id-token: write`
- `contents: read`

#### Required Vault Permissions

- `development/kv/data/sign/2023-2025`: DigiCert signing credentials including:
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
