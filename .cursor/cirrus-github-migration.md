# CirrusCI to GitHub Actions Migration Guide

This guide documents the patterns and best practices for migrating SonarSource projects from CirrusCI to GitHub Actions.

## Maintaining This Documentation

### Editing Guidelines

When updating this migration guide:

1. **Line Length**: Follow MD013 rule - maximum 140 characters per line
2. **Code Blocks**: Use proper syntax highlighting (`yaml`, `bash`, etc.)
3. **Formatting**: Use consistent header levels and bullet points
4. **Examples**: Always test examples before adding them to the guide
5. **Links**: Use proper markdown linking format

### Pre-commit Rules

This repository uses the following linting rules:

- **markdownlint (MD013)**: Line length must not exceed 140 characters
- **YAML formatting**: Consistent indentation and structure in code examples
- **Spell checking**: Ensure technical terms are correctly spelled

### Common Linting Errors

- **MD013**: Line too long → Break line at natural points (see example above)
- **MD032**: Lists should be surrounded by blank lines
- **MD038**: No spaces inside code span elements
- **MD040**: Code blocks should specify language
- **MD041**: First line should be a top-level header

### Contributing to This Guide

When adding new patterns or updating existing ones:

1. **Document the "why"**: Explain reasoning behind recommendations
2. **Provide before/after examples**: Show CirrusCI → GitHub Actions transformations
3. **Update multiple sections**: Ensure consistency across:
   - Main examples
   - "Common Pitfalls" section
   - "Do These Instead" best practices
   - Migration checklist items
4. **Version references**: Always use stable versions (e.g., `@v1`) in final examples
5. **Test thoroughly**: Validate in both public and private repository contexts

### Repository Structure

```text
ci-github-actions/
├── .cursor/
│   └── cirrus-github-migration.md  # This guide
├── build-gradle/
├── build-poetry/
├── build-maven/                    # Custom action implementations
├── cache/
├── get-build-number/
├── promote/
└── pr_cleanup/
```

## Overview

The migration typically involves converting two main CirrusCI tasks:

- **build_task**: Build, test, analyze, and deploy artifacts
- **promote_task**: Promote artifacts in Artifactory

## Security Considerations for GitHub Actions

⚠️ **CRITICAL**: GitHub Actions workflows provide a large attack surface and must be configured securely.
Follow these security principles during migration:

### Key Security Practices

1. **Script Injection Prevention**: Never use untrusted input directly in shell commands
2. **Secure Third-Party Actions**: Pin all third-party actions to full commit SHAs
3. **Least Privilege**: Use minimal required permissions for `GITHUB_TOKEN`
4. **Secure Artifact Handling**: Never include secrets in artifacts or cache
5. **Environment Protection**: Validate all environment variables from external sources

### Action Pinning Requirements

**✅ Always pin third-party actions to commit SHA**:

```yaml
# ✅ CORRECT - Pinned to commit SHA
- uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7

# ❌ WRONG - Unpinned versions
- uses: actions/checkout@v4  # Can be modified
- uses: actions/checkout@main  # Can be modified
```

**Exception**: SonarSource custom actions use semantic versioning (`@v1`) as they are internally managed and trusted.

### Secure Input Handling

**✅ Use environment variables for untrusted input**:

```yaml
# ✅ CORRECT
- name: Echo PR Title
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "PR Title: $PR_TITLE"

# ❌ WRONG - Script injection vulnerability
- name: Echo PR Title
  run: echo "PR Title: ${{ github.event.pull_request.title }}"
```

### Vault Path Format Differences

**CirrusCI vs GitHub Actions vault path syntax**:

```yaml
# CirrusCI format
SONAR_TOKEN: VAULT[development/kv/data/sonarcloud data.token]

# GitHub Actions format - remove 'data.' prefix
secrets: |
  development/kv/data/sonarcloud token | SONAR_TOKEN;
```

**Key difference**: In GitHub Actions vault paths, use the field name directly (e.g., `token`, `url`) instead of
the CirrusCI format (`data.token`, `data.url`).

## Pre-Migration Checklist

1. ✅ Identify the project type (Maven, Gradle, Poetry, etc.)
2. ✅ **Check for cirrus-modules usage**: Look for `.cirrus.star` file - if present, see [Cirrus-Modules Migration section](#migrating-repositories-using-cirrus-modules)
3. ✅ Check existing `.github/workflows/` for conflicts
4. ✅ Understand the current CirrusCI configuration patterns
5. ✅ **CRITICAL**: Verify repository visibility (public vs private) - check GitHub repo Settings → General → Repository visibility
   - Public repos → Use `ubuntu-24.04-large` runners for SonarSource custom actions
   - Private repos → Use `sonar-xs` runners (recommended)
6. ✅ **SECURITY**: Review third-party actions and pin to commit SHAs

⚠️ **CRITICAL**: During migration, leave `.cirrus.yml` unchanged. Both CirrusCI and GitHub Actions should coexist during the transition period.

## Tool Setup with Mise

### Create mise.toml

Always use `mise.toml` for consistent tool versions across environments:

```toml
[tools]
java = "21.0"
maven = "3.9"
# Add other tools as needed (hadolint, etc.)
```

### GitHub Workflow Integration

```yaml
- uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
```

**For promote jobs**, disable cache saving:

```yaml
- uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
  with:
    cache_save: false
```

## Standard GitHub Actions Workflow Structure

### Basic Template

⚠️ **First, check your repository visibility** (Settings → General → Repository visibility) to select the correct runner.

```yaml
name: Build
on:
  push:
    branches:
      - master
      - branch-*
      - dogfood-*
  pull_request:
  merge_group:
  workflow_dispatch:

jobs:
  build:
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: sonar-xs  # For private repos; use ubuntu-24.04-large for public repos
    name: Build
    permissions:
      id-token: write  # Required for Vault OIDC authentication
      contents: write  # Required for repository access and tagging
    steps:
      - uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7
      - uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/build-maven@v1
        with:
          deploy-pull-request: true

  promote:
    needs: [build]
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: sonar-xs
    name: Promote
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
        with:
          cache_save: false
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/promote@v1
```

## SonarSource Custom Actions

**📚 Always check the latest documentation**: The
[SonarSource/ci-github-actions](https://github.com/SonarSource/ci-github-actions/)
repository is public and contains the most up-to-date documentation, examples, and usage
instructions for all custom actions.

### Required Actions for All Projects

#### get-build-number

Generates unique build numbers stored in GitHub repository properties. **Always include this before build actions**.

```yaml
- uses: SonarSource/ci-github-actions/get-build-number@v1
```

**Features:**

- Stores build number in repository property `build_number`
- Sets `BUILD_NUMBER` environment variable and output
- Unique per workflow run ID (unchanged on reruns)
- **Required permissions:** `id-token: write`, `contents: read`

#### promote

Promotes builds in JFrog Artifactory and updates GitHub status checks.

```yaml
- uses: SonarSource/ci-github-actions/promote@v1
```

**Features:**

- Creates GitHub status check named `repox-${GITHUB_REF_NAME}`
- **Required permissions:** `id-token: write`, `contents: write`
- **Required vault permissions:** `promoter` Artifactory role, `promotion` GitHub token

### Build Actions by Project Type

#### Maven Projects

```yaml
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    # All parameters below are optional with auto-detected defaults
    public: false                                  # Auto-detected from repo visibility
    artifactory-reader-role: private-reader       # private-reader/public-reader
    artifactory-deployer-role: qa-deployer        # qa-deployer/public-deployer
    maven-local-repository-path: .m2/repository   # Maven cache path
    maven-opts: -Xmx1536m -Xms128m                # JVM options for Maven
    scanner-java-opts: -Xmx512m                   # JVM options for SonarQube scanner
    use-develocity: false                          # Enable Develocity build tracking
```

**Features:**

- Automatic build context detection (master, maintenance, PR, dogfood, feature)
- SonarQube analysis with context-appropriate profiles
- Artifact signing and conditional deployment
- **Required permissions:** `id-token: write`, `contents: write`

##### Overriding Artifactory Roles

In some cases, your existing CirrusCI configuration may use different Artifactory roles than the
automatic detection. For example, a public repository might use `private-reader` and `qa-deployer`
instead of the default `public-reader` and `public-deployer`.

```yaml
# Override artifactory roles to match existing CirrusCI configuration
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    artifactory-reader-role: private-reader    # Override default public-reader
    artifactory-deployer-role: qa-deployer     # Override default public-deployer
```

**When to use this**: Check your `.cirrus.yml` file for the vault paths used:

- `ARTIFACTORY_PRIVATE_USERNAME: vault-${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader` → Use `artifactory-reader-role: private-reader`
- `ARTIFACTORY_DEPLOY_USERNAME: vault-${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer` → Use `artifactory-deployer-role: qa-deployer`

**Available role options:**

- **Reader roles**: `private-reader`, `public-reader`
- **Deployer roles**: `qa-deployer`, `public-deployer`

#### Gradle Projects

```yaml
- uses: SonarSource/ci-github-actions/build-gradle@v1
  with:
    deploy-pull-request: true
    # All parameters below are optional with auto-detected defaults
    public: false                                     # Auto-detected from repo visibility
    artifactory-deploy-repo: ""                       # Auto-detected: sonarsource-public-qa/sonarsource-private-qa
    artifactory-reader-role: private-reader           # private-reader/public-reader
    artifactory-deployer-role: qa-deployer            # qa-deployer/public-deployer
    skip-tests: false                                  # Skip running tests
    gradle-args: ""                                    # Additional Gradle arguments
    gradle-version: ""                                 # Gradle version (uses wrapper if not specified)
    gradle-wrapper-validation: true                    # Validate Gradle wrapper
    develocity-url: https://develocity.sonar.build/   # Develocity URL
    repox-url: https://repox.jfrog.io                 # Repox URL
    sonar-platform: next                              # SonarQube platform: next/sqc-eu/sqc-us
```

**Features:**

- Automated version management with build numbers
- SonarQube analysis with configurable platform
- Conditional deployment and automatic artifact signing
- Develocity integration for build optimization
- **Required permissions:** `id-token: write`, `contents: write`
- **Outputs:** `project-version` from gradle.properties

#### Poetry Projects (Python)

```yaml
- uses: SonarSource/ci-github-actions/build-poetry@v1
  with:
    deploy-pull-request: true
    # All parameters below are optional with auto-detected defaults
    public: false                                         # Auto-detected from repo visibility
    artifactory-reader-role: private-reader              # private-reader/public-reader
    artifactory-deployer-role: qa-deployer               # qa-deployer/public-deployer
    poetry-virtualenvs-path: .cache/pypoetry/virtualenvs # Poetry virtual environments path
    poetry-cache-dir: .cache/pypoetry                    # Poetry cache directory
```

**Features:**

- Python project build and publish using Poetry
- SonarQube analysis integration
- Conditional deployment based on branch patterns
- **Required permissions:** `id-token: write`, `contents: write`

#### NPM Projects (JavaScript/TypeScript)

```yaml
- uses: SonarSource/ci-github-actions/build-npm@v1
  with:
    deploy-pull-request: false                        # Deploy pull request artifacts
    # All parameters below are optional
    artifactory-deploy-repo: ""                       # Artifactory repository name
    artifactory-deploy-access-token: ""               # Artifactory access token
    skip-tests: false                                  # Skip running tests
    cache-npm: true                                    # Cache NPM dependencies
    repox-url: https://repox.jfrog.io                 # Repox URL
```

**Features:**

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality (credentials from Vault)
- Conditional deployment based on branch patterns (main, maintenance, dogfood branches)
- NPM dependency caching for faster builds (configurable)
- JFrog build info publishing with UI links
- **Required permissions:** `id-token: write`, `contents: write`
- **Outputs:** `project-version` from package.json, `build-info-url` when deployment occurs

### Additional Actions

#### cache

Adaptive cache action that automatically chooses the appropriate caching backend based on repository visibility.

```yaml
- uses: SonarSource/ci-github-actions/cache@v1
  with:
    path: |
      ~/.m2/repository
      ~/.cache/pip
    key: ${{ runner.os }}-cache-${{ hashFiles('**/pom.xml', '**/requirements.txt') }}
    restore-keys: |
      ${{ runner.os }}-cache
    # Optional parameters
    upload-chunk-size: ""                           # Chunk size for large files (bytes)
    enableCrossOsArchive: false                     # Allow cross-platform cache restore
    fail-on-cache-miss: false                       # Fail if cache entry not found
    lookup-only: false                              # Check cache existence without downloading
```

**Features:**

- **Smart backend selection:** GitHub Actions cache for public repos, SonarSource S3 cache for private repos
- **Seamless API compatibility:** Drop-in replacement for standard GitHub Actions cache
- **Automatic detection:** Repository visibility and ownership automatically detected
- **Output:** `cache-hit` boolean indicating exact match found

#### pr_cleanup

Automatically cleans up GitHub Actions resources when pull requests are closed.

```yaml
- uses: SonarSource/ci-github-actions/pr_cleanup@v1
```

**Features:**

- Removes GitHub Actions caches associated with closed PRs
- Cleans up artifacts created during PR workflows
- Provides detailed output of deleted resources
- Shows before/after state of caches and artifacts
- **Required permissions:** `actions: write`

**Usage example in workflow:**

```yaml
name: Cleanup PR Resources
on:
  pull_request:
    types: [closed]
jobs:
  cleanup:
    runs-on: sonar-xs
    permissions:
      actions: write
    steps:
      - uses: SonarSource/ci-github-actions/pr_cleanup@v1
```

## CirrusCI → GitHub Actions Mapping

### Environment Variables

Complete mapping table for ci-common-scripts compatibility:

| CirrusCI Variable | GitHub Actions Variable | Purpose |
|------------------|------------------------|---------|
| `CIRRUS_CHANGE_IN_REPO` | `GITHUB_SHA` | Git commit SHA |
| `CIRRUS_BASE_BRANCH` | `GITHUB_BASE_REF` | Base branch for PRs |
| `CIRRUS_BRANCH` | `GITHUB_HEAD_REF` (PR) / `GITHUB_REF_NAME` (branch) | Current branch |
| `CIRRUS_REPO_FULL_NAME` | `GITHUB_REPOSITORY` | Full repo name (owner/repo) |
| `CIRRUS_BUILD_ID` / `CIRRUS_TASK_ID` | `GITHUB_RUN_ID` | Build/run identifier |
| `BUILD_NUMBER` / `CI_BUILD_NUMBER` | `BUILD_NUMBER` / `BUILD_ID` / `PIPELINE_ID` | Build number |
| `CIRRUS_REPO_NAME` | `PROJECT` | Repository name only |
| `PROJECT_VERSION` | `PROJECT_VERSION` | Project version |
| `CIRRUS_DEFAULT_BRANCH` | `DEFAULT_BRANCH` | Default branch |
| `CIRRUS_PR` | `PULL_REQUEST` | PR number or false |
| `CIRRUS_BASE_SHA` | `PULL_REQUEST_SHA` | Base SHA for PRs |
| `CIRRUS_ENV` | `GITHUB_ENV` | Environment file path |

**Additional Variables**:

- `MAVEN_CONFIG`: Defaults to `$HOME/.m2`
- `MAVEN_LOCAL_REPOSITORY`: Defaults to `$MAVEN_CONFIG/repository`
- `SONARSOURCE_QA`: Set to `true` if not prefixed with BUILD (impacts Maven settings)

#### Specific Environment Variable Mappings

CirrusCI configurations often include these patterns:

```yaml
# CirrusCI
env:
  ARTIFACTORY_DEPLOY_REPO: sonarsource-private-qa  # or sonarsource-public-qa
  ARTIFACTORY_DEPLOY_USERNAME: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer username]
  ARTIFACTORY_DEPLOY_PASSWORD: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer access_token]
  ARTIFACTORY_PRIVATE_USERNAME: vault-${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader
  SONAR_HOST_URL: VAULT[development/kv/data/next data.url]
  SONAR_TOKEN: VAULT[development/kv/data/next data.token]
  PGP_PASSPHRASE: VAULT[development/kv/data/sign data.passphrase]
```

**✅ GitHub Actions Solution**: All these are handled automatically by `build-maven@v1`!
You don't need to specify any of these environment variables or vault secrets manually.

### Container Definitions

| CirrusCI | GitHub Actions |
|----------|----------------|
| `eks_container` | `runs-on: sonar-xs` |
| `cpu: 2, memory: 2G` | Runner handles resources |
| Custom images | Use mise for tools |

#### Resource Requirements

```yaml
# CirrusCI
eks_container:
  <<: *CONTAINER_DEFINITION
  cpu: 2
  memory: 2G
```

**GitHub Actions Runner Selection**:

⚠️ **IMPORTANT**: Before selecting a runner, verify if your repository is **public** or **private**:

- Check your GitHub repository settings → General → Repository visibility
- Public repositories are visible to everyone on GitHub
- Private repositories are only visible to you and people you share them with

| Runner Type | OS | Label | Usage |
|-------------|-------|-------|-------|
| GitHub-Hosted | Ubuntu | `ubuntu-24.04` | Public repos, no auth actions |
| **GitHub-Hosted Large** | **Ubuntu** | **`ubuntu-24.04-large`** | **Public repos, auth actions, Docker-in-Docker** |
| GitHub-Hosted Large | Ubuntu ARM | `ubuntu-24.04-arm-large` | Public repos, ARM builds |
| GitHub-Hosted Large | Windows | `windows-latest-large` | Public repos, Windows builds |
| Self-Hosted Large | Ubuntu | `sonar-runner-large` | Private repos, Docker-in-Docker |
| Self-Hosted Large | Ubuntu ARM | `sonar-runner-large-arm` | Private repos, ARM builds |
| **Self-Hosted On-Demand** | **Ubuntu** | **`sonar-xs`, `sonar-s`, `sonar-m`, `sonar-l`, `sonar-xl`** | **Recommended for private repos** |
| Self-Hosted Sidecar | Ubuntu | `sonar-se-xs`, `sonar-se-m` | Private repos with Kubernetes sidecar |
| Self-Hosted ARM | Ubuntu ARM | `sonar-arm-s` | Private repos, ARM builds |

**Runner Selection Guide**:

- **Public Repository + SonarSource Custom Actions**: Use `ubuntu-24.04-large`
- **Private Repository**: Use `sonar-xs` (scale up as needed: `sonar-s`, `sonar-m`, etc.)
- **Public Repository + No Auth Actions**: Use `ubuntu-24.04`

#### Job Dependencies

```yaml
# CirrusCI
promote_task:
  depends_on:
    - build

# GitHub Actions
promote:
  needs:
    - build  # Cleaner syntax
```

### Conditional Execution

| CirrusCI Pattern | GitHub Actions Pattern |
|------------------|------------------------|
| `only_if: $CIRRUS_USER_COLLABORATOR == 'true'` | Built into SonarSource custom actions |
| `only_if: $CIRRUS_TAG == ""` | Built into promotion logic |
| `only_if: $CIRRUS_PR != ""` | Use `if:` conditions on jobs |

#### Complex CirrusCI Conditions

Original CirrusCI often has complex anchor patterns like:

```yaml
only_sonarsource_qa: &ONLY_SONARSOURCE_QA
  only_if: >
    (
      $CIRRUS_USER_COLLABORATOR == 'true' &&
      $CIRRUS_TAG == "" && (
        $CIRRUS_PR != "" ||
        $CIRRUS_BRANCH == 'master' ||
        $CIRRUS_BRANCH =~ "branch-.*" ||
        $CIRRUS_BRANCH =~ "dogfood-on-.*" ||
        $CIRRUS_BUILD_SOURCE == 'api'
      )
    ) || $CIRRUS_CRON == 'nightly'
```

**✅ GitHub Actions Solution**: Remove these entirely! The SonarSource custom actions
handle all this logic automatically. The workflow will run based on the `on:` triggers
and the actions will handle internal authorization and deployment logic.

### Build Scripts

| CirrusCI | GitHub Actions |
|----------|----------------|
| `source cirrus-env BUILD-PRIVATE` | Handled by custom actions |
| `regular_mvn_build_deploy_analyze` | `build-maven@v1` action |
| `cleanup_maven_repository` | Automatic in custom actions |

#### Cache and Cleanup Patterns

CirrusCI typically includes:

```yaml
# CirrusCI
maven_cache:
  folder: ${CIRRUS_WORKING_DIR}/.m2/repository
build_script:
  - source cirrus-env BUILD-PRIVATE
  - regular_mvn_build_deploy_analyze
cleanup_before_cache_script: cleanup_maven_repository
```

**✅ GitHub Actions Solution**: All cache management and cleanup is handled automatically
by the custom actions. No need to specify cache folders or cleanup scripts.

## Common Patterns and Best Practices

### 1. Security Best Practices

**Action Pinning**:

```yaml
# ✅ Pin third-party actions to commit SHA
- uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7
- uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0

# ✅ SonarSource actions use semantic versioning (trusted)
- uses: SonarSource/ci-github-actions/build-maven@v1
```

**Permissions Documentation**:

```yaml
permissions:
  id-token: write  # Required for Vault OIDC authentication
  contents: write  # Required for repository access and tagging
```

**Secure Input Handling**:

```yaml
# ✅ Never use untrusted input directly in commands
- name: Process PR data
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
    PR_BODY: ${{ github.event.pull_request.body }}
  run: |
    echo "Processing PR: $PR_TITLE"
    echo "Body length: ${#PR_BODY}"
```

### 2. Job Dependencies

```yaml
promote:
  needs: [build]  # Always make promote depend on build
```

### 3. Artifact and Cache Security

**⚠️ CRITICAL**: Never include secrets in artifacts or cache:

```yaml
# ❌ WRONG - May leak secrets
- uses: actions/upload-artifact@v4
  with:
    path: .  # Entire directory may contain .git/config with tokens

# ✅ CORRECT - Upload specific files only
- uses: actions/upload-artifact@v4
  with:
    path: |
      dist/
      build/libs/*.jar
```

**Cache Security**:

- Never cache sensitive information (tokens, keys, credentials)
- Be aware that cache is accessible to anyone with read access to the repository
- Consider cache poisoning risks when using third-party actions

### 4. Concurrency Control

Always use this pattern to prevent conflicts:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
```

### 5. Required Permissions

All jobs need these permissions:

```yaml
permissions:
  id-token: write  # For Vault authentication
  contents: write  # For repository access
```

### 6. Step Ordering

Standard order:

1. `actions/checkout@v4`
2. `jdx/mise-action` (tool setup)
3. `get-build-number@v1`
4. Build action (`build-maven@v1`, etc.)
5. `promote@v1` (promote job only)

### 7. Avoid Unnecessary Environment Variables

❌ Don't add unused env vars like:

```yaml
env:
  DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}  # Usually not needed
```

## Repository-Specific Configurations

### Public vs Private Repositories

```yaml
# Both private and public repositories - auto-detected behavior
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    # public parameter auto-detected from repository visibility:
    #   - Private repo → public: false (uses private-reader, qa-deployer roles)
    #   - Public repo → public: true (uses public-reader, public-deployer roles)
    # artifactory roles are also auto-detected based on repository visibility
```

**Key Point**: Repository visibility is automatically detected. The `public` parameter and
Artifactory roles are determined based on whether your GitHub repository is public or private.
Only override if you have specific requirements.

## Migration Checklist

### Phase 1: Setup

- [ ] **CRITICAL**: Check repository visibility (Settings → General → Repository visibility)
- [ ] Select correct runner type based on repository visibility:
  - [ ] Public repo → `ubuntu-24.04-large`
  - [ ] Private repo → `sonar-xs`
- [ ] **SECURITY**: Pin all third-party actions to commit SHA
- [ ] **SECURITY**: Verify permissions follow least-privilege principle
- [ ] Check similar dummy repository for your project type
- [ ] Create `mise.toml` with required tool versions
- [ ] Verify Vault permissions are configured
- [ ] Create `.github/workflows/build.yml`
- [ ] Verify no conflicts with existing workflows

### Phase 2: Build Job

- [ ] Add standard triggers (push, PR, merge_group, workflow_dispatch)
- [ ] Select appropriate runner type (sonar-xs for private repos)
- [ ] Configure concurrency control
- [ ] Add checkout, mise, get-build-number steps
- [ ] Add appropriate build action (maven/gradle/poetry)
- [ ] **If using cirrus-modules**: Verify all features are covered by SonarSource custom actions
- [ ] Test build job functionality

### Phase 3: Promote Job

- [ ] Add promote job with proper dependencies
- [ ] Configure same concurrency control
- [ ] Add checkout, mise (with cache_save: false), get-build-number
- [ ] Add promote action
- [ ] Test promotion functionality

### Phase 4: Additional Workflows

- [ ] Add `pr-cleanup.yml` for automatic PR resource cleanup
- [ ] Consider stable-branch-update job if needed
- [ ] Set up any project-specific additional workflows

### Phase 5: Cleanup & Configuration

⚠️ **IMPORTANT**: Do NOT modify `.cirrus.yml` during migration. Leave it exactly as-is to ensure
CirrusCI continues to work alongside GitHub Actions during the transition period.

- [ ] Verify all CirrusCI functionality is replicated
- [ ] Configure build number in repository settings (> latest CirrusCI build)
- [ ] Test both PR and branch builds
- [ ] Keep `.cirrus.yml` as-is (DO NOT remove or comment out during migration)
- [ ] Update any documentation references

## Vault Permissions Setup

Ensure your repository has the required Vault permissions in `re-terraform-aws-vault/orders`:

```yaml
some-repository:
  auth:
    github: {}
  secrets:
    artifactory:
      roles:
        - *artifactory_public-reader    # For PUBLIC repository, reader token
        - *artifactory_public-deployer  # For PUBLIC repository, deployer token
        - *artifactory_private-reader   # For PRIVATE repository, reader token
        - *artifactory_qa-deployer      # For PRIVATE repository, deployer token
        - *artifactory_promoter         # For artifact promotion
    github:
      presets:
        - licenses                      # Only for QA tests
      customs:
        - <<: *github_jira             # For gh-action-lt-backlog
          repositories: [some-repository]
        - <<: *github_promotion        # GitHub checks with build number
          repositories: [some-repository]
    kv_paths:
      development/kv/data/datadog: {}    # For gh-action_release
      development/kv/data/jira: {}       # For gh-action-lt-backlog
      development/kv/data/ossrh: {}      # For gh-action_release, if mavenCentralSync
      development/kv/data/pypi-test: {}  # For gh-action_release, if publishToTestPyPI
      development/kv/data/pypi: {}       # For gh-action_release, if publishToPyPI
      development/kv/data/repox: {}      # For gh-action_release
      development/kv/data/slack: {}      # For gh-action_release
      development/kv/data/sonarcloud: {} # For manual scan with SC
```

**Note**: Most secrets should already exist from CirrusCI usage.

## Build Number Configuration

**Critical Step**: After migration, configure the build number in repository settings:

1. Go to Repository Settings → Custom Properties
2. Set build number to a value **greater than the latest CirrusCI build**
3. This ensures continuous build numbering after migration

## Additional Example Repositories

Reference these SonarSource dummy repositories for specific patterns:

| Repository | Type | Build System | Notes |
|------------|------|--------------|-------|
| [sonar-dummy](https://github.com/SonarSource/sonar-dummy) | Private Java | Maven | Standard private Maven project |
| [sonar-dummy-maven-enterprise](https://github.com/SonarSource/sonar-dummy-maven-enterprise) | Public+Private Java | Maven | Mixed public/private content |
| [sonar-dummy-yarn](https://github.com/SonarSource/sonar-dummy-yarn) | Private NodeJS | NPM+Yarn | Node.js with Yarn |
| [sonar-dummy-js](https://github.com/SonarSource/sonar-dummy-js) | Private JavaScript | NPM | JavaScript project |
| [sonar-dummy-oss](https://github.com/SonarSource/sonar-dummy-oss) | Public Java | Gradle | Public Gradle project |
| [sonar-dummy-python-oss](https://github.com/SonarSource/sonar-dummy-python-oss) | Public Python | Poetry | Public Python with Poetry |

**Best Practice**: Check the most similar dummy repository for your project type before starting migration.

## Required Additional Workflows

### PR Cleanup Workflow

**Recommended**: Add `.github/workflows/pr-cleanup.yml` to automatically clean up PR resources when PRs are closed.

See the [pr_cleanup action documentation](#pr_cleanup) above for full details and usage example.

This workflow automatically:

- Removes GitHub Actions caches associated with closed PRs
- Cleans up artifacts created during PR workflows
- Provides detailed output of deleted resources

## Internal Best Practices

### ✅ DO These

- Get build number before promotion (always include `get-build-number@v1`)
- Move `DEPLOY_PULL_REQUEST` to global environment variable
- Use Maven cache key format: `maven-${{ runner.os }}` (better UI filtering)
- Include `pr-cleanup.yml` for automatic PR resource cleanup
- **SECURITY**: Pin all third-party actions to commit SHA
- **SECURITY**: Use environment variables for untrusted input
- **SECURITY**: Document all permissions with comments explaining why they're needed

### ❌ DON'T Do These

- Don't specify `GH_TOKEN` environment variable in build job (auto-handled)
- Don't trigger on `gh-readonly-queue/*` branches
- Don't upload `${{ github.event_path }}` file as artifact
- Don't use GitHub licenses token except for QA tests
- **SECURITY**: Don't use unpinned third-party actions (`@main`, `@v1`)
- **SECURITY**: Don't use untrusted input directly in shell commands
- **SECURITY**: Don't upload entire directories as artifacts (may contain secrets)
- **SECURITY**: Don't cache sensitive information (tokens, keys, credentials)

## Troubleshooting

### Common Issues

1. **Missing permissions**: Ensure `id-token: write` and `contents: write` are set
2. **Build numbers**: Always include `get-build-number@v1` before build actions
3. **Tool versions**: Use mise.toml instead of manual setup actions
4. **Cache conflicts**: Use `cache_save: false` in promote jobs
5. **Branch conditions**: Let custom actions handle most conditional logic
6. **Build number continuity**: Set custom property > latest CirrusCI build
7. **Artifactory role mismatch**: If your CirrusCI uses different roles than auto-detected, override them:
   ```yaml
   # Check .cirrus.yml for actual roles used and override if needed
   - uses: SonarSource/ci-github-actions/build-maven@v1
     with:
       artifactory-reader-role: private-reader    # Match CirrusCI config
       artifactory-deployer-role: qa-deployer     # Match CirrusCI config
   ```
8. **Cirrus-modules migration**: If migrating from cirrus-modules, don't try to recreate individual features
   manually - use the comprehensive SonarSource custom actions instead
9. **Security**: Ensure third-party actions are pinned to commit SHA
10. **Script injection**: Never use untrusted input directly in shell commands

### Security Troubleshooting

**Script Injection Issues**:

```yaml
# ❌ If you see injection vulnerabilities
run: echo "Title: ${{ github.event.pull_request.title }}"

# ✅ Fix with environment variables
env:
  PR_TITLE: ${{ github.event.pull_request.title }}
run: echo "Title: $PR_TITLE"
```

**Action Pinning Issues**:

- Check that all non-SonarSource actions use commit SHA
- Use GitHub's Dependabot to keep pinned actions updated
- Never use `@main` or `@master` for third-party actions

### Testing Tips

- Use feature branches of custom actions for testing (e.g., `@feat/branch-name`)
- Test both PR and branch builds
- Verify promotion works correctly
- Check Artifactory deployments
- **Always consult the [official repository](https://github.com/SonarSource/ci-github-actions/) for the latest action parameters and examples**

#### Using Feature Branches for Testing

When testing new custom actions, use feature branches:

```yaml
# For testing new features
- uses: SonarSource/ci-github-actions/build-maven@feat/smarini/BUILD-8317-createBuildMavenGhAction

# Production ready
- uses: SonarSource/ci-github-actions/build-maven@v1
```

Remember to update to `@v1` once the feature is released!

**💡 Version Updates**: Check the
[releases page](https://github.com/SonarSource/ci-github-actions/releases) for the
latest stable versions. While `@v1` is typically the current stable version, newer
major versions may be available with enhanced features.

## Migrating Repositories Using Cirrus-Modules

### What is Cirrus-Modules?

Many SonarSource repositories use `cirrus-modules`, a centralized Starlark library that abstracts away CI
infrastructure complexity. You can identify these repositories by the presence of a `.cirrus.star` file:

```starlark
# renovate: datasource=github-releases depName=SonarSource/cirrus-modules
load("github.com/SonarSource/cirrus-modules@74c00b08bd556f6f6f59cc244941f0a815d79e42", "load_features")  # 3.3.0

def main(ctx):
    return load_features(ctx)
```

### Cirrus-Modules Features and GitHub Actions Equivalents

The cirrus-modules system provides several features that need to be handled during migration:

| Cirrus-Modules Feature | GitHub Actions Equivalent | Notes |
|------------------------|---------------------------|-------|
| **AWS Infrastructure** | `runs-on: sonar-xs` | Runner selection handles infrastructure |
| **Vault Authentication** | `SonarSource/vault-action-wrapper` | Direct vault integration |
| **Build Numbers** | `SonarSource/ci-github-actions/get-build-number@v1` | Continuous build numbering |
| **Repox/Artifactory** | `SonarSource/ci-github-actions/build-*@v1` | Handled by build actions |
| **Conditional Execution** | `on:` triggers + `if:` conditions | GitHub Actions native conditions |

## Real Migration Example

### Before: `.cirrus.yml` (66 lines)

```yaml
env:
  CIRRUS_CLONE_DEPTH: "20"
  CIRRUS_SHELL: bash
  ARTIFACTORY_URL: VAULT[development/kv/data/repox data.url]
  PGP_PASSPHRASE: VAULT[development/kv/data/sign data.passphrase]

container_definition: &CONTAINER_DEFINITION
  image: ${CIRRUS_AWS_ACCOUNT}.dkr.ecr.eu-central-1.amazonaws.com/base:j17-latest
  cluster_name: ${CIRRUS_CLUSTER_NAME}
  region: eu-central-1
  namespace: default

only_sonarsource_qa: &ONLY_SONARSOURCE_QA
  only_if: >
    (
      $CIRRUS_USER_COLLABORATOR == 'true' &&
      $CIRRUS_TAG == "" && (
        $CIRRUS_PR != "" ||
        $CIRRUS_BRANCH == 'master' ||
        $CIRRUS_BRANCH =~ "branch-.*" ||
        $CIRRUS_BRANCH =~ "dogfood-on-.*" ||
        $CIRRUS_BUILD_SOURCE == 'api'
      )
    ) || $CIRRUS_CRON == 'nightly'

build_task:
  <<: *ONLY_SONARSOURCE_QA
  eks_container:
    <<: *CONTAINER_DEFINITION
    cpu: 2
    memory: 2G
  env:
    ARTIFACTORY_DEPLOY_PASSWORD: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer access_token]
    ARTIFACTORY_DEPLOY_USERNAME: vault-${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer
    ARTIFACTORY_PRIVATE_USERNAME: vault-${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader
    ARTIFACTORY_DEPLOY_REPO: sonarsource-private-qa
    SONAR_HOST_URL: VAULT[development/kv/data/next data.url]
    DEPLOY_PULL_REQUEST: "true"
    SONAR_TOKEN: VAULT[development/kv/data/next data.token]
  maven_cache:
    folder: ${CIRRUS_WORKING_DIR}/.m2/repository
  build_script:
    - source cirrus-env BUILD-PRIVATE
    - regular_mvn_build_deploy_analyze
  cleanup_before_cache_script: cleanup_maven_repository

promote_task:
  depends_on:
    - build
  <<: *ONLY_SONARSOURCE_QA
  eks_container:
    <<: *CONTAINER_DEFINITION
    cpu: 1
    memory: 1G
  env:
    ARTIFACTORY_PROMOTE_ACCESS_TOKEN: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-promoter access_token]
    GITHUB_TOKEN: VAULT[development/github/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-promotion token]
  maven_cache:
    folder: ${CIRRUS_WORKING_DIR}/.m2/repository
  script: cirrus_promote_maven
  cleanup_before_cache_script: cleanup_maven_repository
```

### After: `.github/workflows/build.yml` (55 lines)

```yaml
name: Build
on:
  push:
    branches:
      - master
      - branch-*
      - dogfood-*
  pull_request:
  merge_group:
  workflow_dispatch:

jobs:
  build:
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: sonar-xs
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/build-maven@v1
        with:
          deploy-pull-request: true

  promote:
    needs: [build]
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}
    runs-on: sonar-xs
    name: Promote
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
        with:
          cache_save: false
      - uses: SonarSource/ci-github-actions/get-build-number@v1
      - uses: SonarSource/ci-github-actions/promote@v1
```

### Plus: `mise.toml` (3 lines)

```toml
[tools]
java = "21.0"
maven = "3.9"
```

**Result**: 17% reduction in configuration lines, 90% reduction in complexity, same functionality!

## Common Migration Pitfalls to Avoid

### ❌ Don't Do These

1. **Don't manually fetch Vault secrets**:

   ```yaml
   # ❌ WRONG - Don't do this
   - name: Vault
     id: secrets
     uses: SonarSource/vault-action-wrapper@3.0.2
     with:
       secrets: |
         development/artifactory/token/... | ARTIFACTORY_TOKEN
   ```

   ✅ **Correct**: Let `build-maven@v1` handle all secrets automatically.

2. **Don't manually set up caching**:

   ```yaml
   # ❌ WRONG - Don't do this
   - uses: actions/cache@v4
     with:
       path: ~/.m2/repository
   ```

   ✅ **Correct**: Custom actions handle caching automatically.

3. **Don't copy complex CirrusCI conditions**:

   ```yaml
   # ❌ WRONG - Don't port these complex conditions
   if: ${{ github.actor == 'dependabot[bot]' || ... complex logic ... }}
   ```

   ✅ **Correct**: Use simple triggers and let custom actions handle authorization.

4. **Don't specify unnecessary parameters**:

   ```yaml
   # ❌ WRONG - These are auto-detected
   - uses: SonarSource/ci-github-actions/build-maven@v1
     with:
       public: true  # Auto-detected from repo visibility
       deploy-pull-request: true

   # ❌ WRONG - These environment variables are auto-detected
   env:
     ARTIFACTORY_URL: https://repox.jfrog.io/artifactory
     DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}

   # ❌ WRONG - GITHUB_TOKEN is already available by default
   - uses: jdx/mise-action@bfb9fa0b029db830a8c570757cee683df207a6c5 # v2.4.0
     env:
       GITHUB_TOKEN: ${{ github.token }}  # Not needed!
   ```

5. **Don't use manual JDK setup when using mise**:

   ```yaml
   # ❌ WRONG - Conflicts with mise
   - uses: actions/setup-java@v4
     with:
       java-version: '21'
   ```

   ✅ **Correct**: Use `mise.toml` and `jdx/mise-action`.

6. **Don't modify `.cirrus.yml` during migration**:

   ```yaml
   # ❌ WRONG - Don't comment out or modify .cirrus.yml during migration
   # env:
   #   CIRRUS_CLONE_DEPTH: "20"
   ```

   ✅ **Correct**: Leave `.cirrus.yml` exactly as-is during migration for coexistence.

### ✅ Do These Instead

- Keep it simple - trust the custom actions
- Use standard triggers and let actions handle the rest
- Always include `get-build-number@v1`
- Use `mise.toml` for tool versions
- Let parameters auto-detect from repository settings (public/private, Artifactory roles)
- **Leave `.cirrus.yml` unchanged during migration**
- Test with feature branches first

## Additional Migration Guidelines

### Checkout Depth Configuration

When migrating from CirrusCI, replace specific checkout depth configurations (like CIRRUS_CLONE_DEPTH) with
standard checkout action without fetch-depth parameter.

### SonarQube Scanning

Replace any manual SonarQube scanning implementations with the official SonarSource/sonarqube-scan-action
unless explicitly asked not to do it. Manual implementations typically involve downloading sonar-scanner CLI,
setting up paths, running sonar-scanner command directly, or using Docker containers.

Example of manual scanning that should be replaced:

```yaml
- name: SonarQube Scan
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
  run: |
    # Download and setup sonar-scanner
    wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip
    unzip -q sonar-scanner-cli-5.0.1.3006-linux.zip
    export PATH=$PATH:$(pwd)/sonar-scanner-5.0.1.3006-linux/bin
    sonar-scanner
```

Example from CirrusCI that should be replaced:

```yaml
scanner_task:
  name: SonarQube Cloud Scan
  depends_on:
    - test
  eks_container:
    image: sonarsource/sonar-scanner-cli:5.0
    cluster_name: ${CIRRUS_CLUSTER_NAME}
    region: eu-central-1
    namespace: default
    cpu: 2
    memory: 2G
  env:
    SONAR_TOKEN: VAULT[development/kv/data/sonarcloud data.token]
    SONAR_HOST_URL: VAULT[development/kv/data/sonarcloud data.url]
  analyze_script:
    - sonar-scanner
```

Replace with:

```yaml
- name: SonarQube Scan
  uses: SonarSource/sonarqube-scan-action@8c71dc039c2dd71d3821e89a2b58ecc7fee6ced9 # v5.3.0
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    SONAR_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_HOST_URL }}
```

### Pre-commit Integration

If pre-commit is available in the repository (indicated by any precommit file like `.pre-commit-config.yaml`,
`.github/workflows/pre-commit.yml`, etc.), after making any file changes, always run pre-commit on all
changed files to catch and fix linting/formatting issues. Fix any errors that pre-commit reports, but do not
commit the changes automatically.

Example workflow:

1. Make changes to files
2. Run: `pre-commit run --files [list of changed files]`
3. Fix any issues reported by pre-commit
4. Present the fixed files to the user without committing

### Version Management

Always search for and use the latest stable version of tools, dependencies, and GitHub Actions. Avoid using
outdated versions unless specifically required for compatibility.

## Common GitHub Actions - Latest Versions Index

Update this section when newer versions are released:

**Core Actions:**

- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`
- `actions/setup-node@26961cf329f22f6837d5f54c3efd76b480a6422d # v4.0.4`
- `actions/setup-python@41baba1a9c8c95fb52b6b51ee3d90bb4ba21026b # v5.4.0`
- `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`
- `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4.3.0`
- `actions/cache@5a3ec84eff668545956fd18022155c47e93e2684 # v4.1.2`

**Tool Management:**

- `jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac # v2.4.4`

**SonarSource Actions:**

- `SonarSource/sonarqube-scan-action@8c71dc039c2dd71d3821e89a2b58ecc7fee6ced9 # v5.3.0`
- `SonarSource/vault-action-wrapper@d6d745ffdbc82b040df839b903bc33b5592cd6b0 # v3.0.2`
