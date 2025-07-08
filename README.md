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

## `build-maven`

Build and deploy a Maven project.

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
      - uses: actions/checkout@v4
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/build-maven@v1
```

#### Configuration Options (`with` Parameters)

- `public`: Repository visibility (defaults to repository setting)
- `artifactory-reader-role`: Suffix for the Artifactory reader role in Vault. Defaults to `private-reader` for private repositories, and
  `public-reader` for public repositories.
- `artifactory-deployer-role`: Suffix for the Artifactory deployer role in Vault. Defaults to `qa-deployer` for private repositories, and
  `public-deployer` for public repositories.
- `deploy-pull-request`: Whether to deploy pull request artifacts. Defaults to `false`.
- `maven-local-repository-path`: Path to the Maven cache directory, relative to the user home directory. Defaults to `.m2/repository`.
- `maven-opts`: Additional Maven options to pass to the build script (`MAVEN_OPTS`). Defaults to `-Xmx1536m -Xms128m`.
- `scanner-java-opts`: Additional Java options for the Sonar scanner (`SONAR_SCANNER_JAVA_OPTS`). Defaults to `-Xmx512m`.
- `use-develocity`: Whether to use Develocity for build tracking. Defaults to `false`.

#### Required GitHub permissions

- `id-token: write`
- `contents: write`

#### Required Vault permissions

- `public-reader` or `private-reader` Artifactory roles for reading dependencies.
- `public-deployer` or `qa-deployer` Artifactory roles for deployment.
- `development/kv/data/next` for SonarQube analysis.
- `development/kv/data/sign`: for artifact signing.
- `development/kv/data/develocity`: if using Develocity (see
  [xtranet/Develocity/Maven Projects](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/3705372706/Maven+Projects+-+Develocity)).
- `licenses` preset when running QA with a licensed SonarQube. If needed, pass it as `GITHUB_TOKEN` environment variable.

### Features

- Build Context Detection: e.g., main, maintenance, PR, dogfood, feature branches.
- SonarQube analysis.
- Artifact Signing.
- Conditional Deployment based on branch patterns and configuration.

### Build Contexts

[//]: # (FIXME BUILD-8317)

The action automatically detects the build context and applies the appropriate strategy:

- **master**: Deploy + SonarQube analysis with full profiles (coverage, deploy-sonarsource, release, sign)
- **maintenance** (`branch-*`): Deploy with full profiles, followed by separate SonarQube analysis
- **pr**: Conditional deployment based on `deploy-pull-request` parameter, always includes SonarQube
  - With deploy: Uses deploy-sonarsource profiles
  - Without deploy: Uses coverage-only profiles with verify goal
- **dogfood** (`dogfood-on-*`): Deploy only with dogfood profiles (deploy-sonarsource, release)
- **feature** (`feature/long/*`): Verify + SonarQube analysis with coverage profile only
- **default**: Basic verify goal only, no deployment or analysis

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
          deploy-pull-request: false
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

## `build-gradle`

Build and publish a Gradle project with SonarQube analysis and Artifactory deployment.

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
      - uses: SonarSource/ci-github-actions/build-gradle@v1
        with:
          artifactory-deploy-repo: ""                               # Artifactory repository name
          artifactory-deploy-username: ""                           # Artifactory username
          artifactory-deploy-password: ""                           # Artifactory password
          deploy-pull-request: false                                # Deploy pull request artifacts
          skip-tests: false                                         # Skip running tests
          gradle-args: ""                                           # Additional Gradle arguments
          gradle-version: ""                                        # Gradle version for setup-gradle
          # if not provided Gradle Wrapper specified version will be used
          gradle-wrapper-validation: true                           # Validate Gradle wrapper
          develocity-url: https://develocity.sonar.build/           # Develocity URL
          repox-url: https://repox.jfrog.io                         # Repox URL
```

⚠️ Required GitHub permissions:

- `id-token: write`
- `contents: write`

⚠️ Required Vault permissions:

- `development/kv/data/next`: SonarQube credentials
- `development/kv/data/sign`: Artifact signing credentials
- `development/kv/data/develocity`: Develocity access token

### Inputs

- `artifactory-deploy-repo`: Name of deployment repository (optional)
- `artifactory-deploy-username`: Username to deploy to Artifactory (optional)
- `artifactory-deploy-password`: Password to deploy to Artifactory (optional)
- `deploy-pull-request`: Whether to deploy pull request artifacts (default: `false`)
- `skip-tests`: Whether to skip running tests (default: `false`)
- `gradle-args`: Additional arguments to pass to Gradle (optional)
- `gradle-version`: Gradle version to use for setup-gradle action (optional)
- `gradle-wrapper-validation`: Whether to validate Gradle wrapper (default: `true`)
- `develocity-url`: URL for Develocity (default: `https://develocity.sonar.build/`)
- `repox-url`: URL for Repox (default: `https://repox.jfrog.io`)

### Outputs

- `project-version`: The project version from gradle.properties

### Features

- Automated version management with build numbers
- SonarQube analysis for code quality (credentials from Vault)
- Conditional deployment based on branch patterns
- Automatic artifact signing (credentials from Vault)
- Pull request support with optional deployment
- Develocity integration for build optimization
- Comprehensive build logging and error handling

## `build-npm`

Build, test, analyze, and deploy an NPM project with SonarQube integration and JFrog Artifactory deployment.

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
      - uses: SonarSource/ci-github-actions/build-npm@v1
        with:
          artifactory-deploy-repo: ""                               # Artifactory repository name
          artifactory-deploy-access-token: ""                       # Artifactory access token
          deploy-pull-request: false                                # Deploy pull request artifacts
          skip-tests: false                                         # Skip running tests
          cache-npm: true                                           # Cache NPM dependencies
          repox-url: https://repox.jfrog.io                         # Repox URL
```

⚠️ Required GitHub permissions:

- `id-token: write`
- `contents: write`

⚠️ Required Vault permissions:

- `development/kv/data/next`: SonarQube credentials

### Inputs

- `artifactory-deploy-repo`: Name of deployment repository (optional)
- `artifactory-deploy-access-token`: Access token to deploy to Artifactory (optional)
- `deploy-pull-request`: Whether to deploy pull request artifacts (default: `false`)
- `skip-tests`: Whether to skip running tests (default: `false`)
- `cache-npm`: Whether to cache NPM dependencies (default: `true`)
- `repox-url`: URL for Repox (default: `https://repox.jfrog.io`)

### Outputs

- `project-version`: The project version from package.json
- `build-info-url`: The JFrog build info UI URL (when deployment occurs)

### Features

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality (credentials from Vault)
- Conditional deployment based on branch patterns (main, maintenance, dogfood branches)
- NPM dependency caching for faster builds (configurable)
- Pull request support with optional deployment
- JFrog build info publishing with UI links
- Comprehensive build logging and error handling
- Support for different branch types (main, maintenance, PR, dogfood, long-lived feature)

## `promote`

This action promotes a build in JFrog Artifactory and updates the GitHub status check accordingly.

The GitHub status check is named `repox-${GITHUB_REF_NAME}`.

### Usage

```yaml
  promote:
    needs:
      - build
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: ubuntu-24.04-large
    name: Promote
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/promote@v1
```

⚠️ Required GitHub permissions:

- `id-token: write`
- `contents: write`

⚠️ Required Vault permissions:

- `promoter` Artifactory role for the promotion.
- `promotion` GitHub token.

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

⚠️ **Note**: This action automatically detects repository visibility and ownership. External repositories will always use GitHub Actions
cache.
SonarSource private repositories will use the internal S3 cache when available.
