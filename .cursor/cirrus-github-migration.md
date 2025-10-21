# Cirrus CI to GitHub Actions AI Migration Guide

This guide documents the patterns and best practices for migrating SonarSource projects from Cirrus CI to GitHub Actions.
⚠️ This document is intended for use during migrations involving AI agents. ⚠️

For human readable docs refer to [xtranet](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/4232970266/Migration+From+Cirrus+CI+-+GitHub).

## Maintaining This Documentation

### Editing Guidelines

When updating this migration guide:

1. **Line Length**: Follow MD013 rule - maximum 140 characters per line
2. **Code Blocks**: Use proper syntax highlighting (`yaml`, `bash`, etc.)
3. **Formatting**: Use consistent header levels and bullet points
4. **Examples**: Always test examples before adding them to the guide
5. **Links**: Use proper markdown linking format

## ⚠️ MANDATORY READING BEFORE STARTING

**STOP**: This documentation contains EXACT specifications that MUST be followed precisely. Do NOT:

- Guess action versions
- Mix this documentation with other sources
- Skip any required parameters
- Substitute similar-looking configurations from other workflows

## 🔒 EXACT ACTION VERSIONS - COPY THESE PRECISELY

### ⚠️ CRITICAL: Use EXACTLY these versions with COMPLETE configuration

```yaml
# Checkout
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0

# Mise Setup - INCLUDES REQUIRED VERSION PARAMETER
- uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
  with:
    version: 2025.7.12

# Upload Artifacts
- name: Upload coverage reports
  if: always() && ! canceled()
  uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
  with:
    name: coverage-reports
    path: path/to/coverage.xml

# Download Artifacts
- name: Download coverage reports
  uses: actions/download-artifact@634f93cb2916e3fdff6788551b99b062d0335ce0 # v5.0.0
  with:
    name: coverage-reports

# SonarQube Scan
- name: SonarQube scan
  uses: sonarsource/sonarqube-scan-action@fd88b7d7ccbaefd23d8f36f73b59db7a3d246602 # v6.0.0
  env:
    SONAR_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_HOST_URL }}
```

⚠️ CRITICAL - `sonarsource/sonarqube-scan-action` requires to be running on `github-ubuntu-latest-s` runner.

## ✅ VALIDATION CHECKLIST

After creating your workflow, verify EVERY item:

### Action Versions

Update this section when newer versions are released:

#### Core GitHub Actions

- [ ] `actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8`
- [ ] `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`
- [ ] `actions/download-artifact@634f93cb2916e3fdff6788551b99b062d0335ce0 # v5.0.0`

#### Build Tools

- [ ] `jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0`
- [ ] `sonarsource/sonarqube-scan-action@fd88b7d7ccbaefd23d8f36f73b59db7a3d246602 # v6.0.0`

#### SonarSource Actions

- [ ] `SonarSource/vault-action-wrapper@v3`
- [ ] `SonarSource/gh-action_pre-commit@v1`
- [ ] `SonarSource/gh-action_release/.github/workflows/main.yaml@v6`

### Mise Configuration

- [ ] `version: 2025.7.12` parameter included

### Workflow Configuration

- [ ] **Concurrency**: Defined at workflow level (not job level)
- [ ] **Standard triggers**: push, pull_request, workflow_dispatch
- [ ] **Runner selection**: Correct runner based on **GitHub Actions Runner Selection** section

## Pre-Migration Checklist

1. ✅ Identify the project type (Maven, Gradle, Poetry, etc.)
2. ✅ **CRITICAL**: Verify repository visibility (public vs private)
    - **Auto-detection**: Repository visibility is automatically inferred from `ARTIFACTORY_DEPLOY_REPO` value:
      - `sonarsource-private-qa` → Private repository configuration
      - `sonarsource-public-qa` → Public repository configuration
3. ✅ **Check for cirrus-modules usage**: Look for `.cirrus.star` file - if present,
   see [Cirrus-Modules Migration section](#migrating-repositories-using-cirrus-modules)
4. ✅ Check existing `.github/workflows/` for conflicts
5. ✅ Understand the current Cirrus CI configuration patterns
6. ✅ **SECURITY**: Review third-party actions and pin to commit SHAs
7. Runner type selected (see  **GitHub Actions Runner Selection**)
8. All required action versions copied from Action Versions Table
9. Tool versions identified from existing configuration
10. ✅ **Repository visibility detection**: Check `.cirrus.yml` for `ARTIFACTORY_DEPLOY_REPO` value

⚠️ **CRITICAL**: During migration, leave `.cirrus.yml` unchanged. Both Cirrus CI and GitHub Actions should coexist during the transition
period.

## 🚫 COMMON MISTAKES TO AVOID

1. **Missing mise version parameter**: `version: 2025.7.12` is MANDATORY
2. **Wrong runner type**: You MUST select runners described in **GitHub Actions Runner Selection** section
3. **Mixing documentation sources**: Use ONLY this guide, not other workflows
4. **Incomplete action configurations**: Copy the COMPLETE blocks from this guide
5. **Missing dependencies**: Convert Cirrus CI `depends_on` to GitHub Actions `needs`
6. **Forgetting documentation updates**: Always update README.md badges and path references
7. **Leaving Cirrus CI path references**: Update `/tmp/cirrus-ci-build/` paths to GitHub Actions equivalents
8. **Keeping manual workflow implementations**: Replace manual pr-cleanup.yml with official SonarSource actions

## 📞 SUPPORT

If ANY step is unclear, STOP and ask for clarification. Do NOT proceed with assumptions.

---

**Remember**: Following this documentation EXACTLY is critical for security, consistency, and functionality.
Every parameter and version listed here is required.

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
2. **Provide before/after examples**: Show Cirrus CI → GitHub Actions transformations
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

The migration typically involves converting two main Cirrus CI tasks:

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
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0

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
  run:
    echo "PR Title: $PR_TITLE"

# ❌ WRONG - Script injection vulnerability
- name: Echo PR Title
  run:
    echo "PR Title: ${{ github.event.pull_request.title }}"
```

### Vault Path Format Differences

**Cirrus CI vs GitHub Actions vault path syntax**:

```yaml
# Cirrus CI format
SONAR_TOKEN: VAULT[development/kv/data/sonarcloud data.token]

# GitHub Actions format - remove 'data.' prefix, used by vault-action-wrapper
secrets: |
  development/kv/data/sonarcloud token | SONAR_TOKEN;
```

**Key difference**: In GitHub Actions, the `vault-action-wrapper` uses the field name directly (e.g., `token`, `url`) instead of
the Cirrus CI format (`data.token`, `data.url`). The `vault-action-wrapper` is automatically used by all SonarSource custom actions.

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
      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
        with:
          version: 2025.7.12
```

**For promote jobs**, disable cache saving:

```yaml
- uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
  with:
    cache_save: false
    version: 2025.7.12
```

## Standard GitHub Actions Workflow Structure

### Basic Template

⚠️ **First, check your repository visibility** to select the correct runner.

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

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: sonar-xs  # For private repos; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write  # Required for Vault OIDC authentication
      contents: write  # Required for repository access and tagging
    steps:
      # NOTE: Check for latest releases and update commit SHAs for actions
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
        with:
          version: 2025.7.12
      - uses: SonarSource/ci-github-actions/build-maven@v1
        with:
          deploy-pull-request: true

  promote:
    needs: [ build ]
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Promote
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
        with:
          cache_save: false
          version: 2025.7.12
      - uses: SonarSource/ci-github-actions/promote@v1
        with:
          promote-pull-request: true
```

## SonarSource Custom Actions

**📚 Always check the latest documentation**: The
[SonarSource/ci-github-actions](https://github.com/SonarSource/ci-github-actions/)
repository is public and contains the most up-to-date documentation, examples, and usage
instructions for all custom actions.

### SonarSource Vault Integration

All SonarSource custom actions use the `vault-action-wrapper` to securely fetch secrets from HashiCorp Vault using OIDC
authentication. **You don't need to use this action directly** - it's automatically integrated into all build and promote actions.

#### vault-action-wrapper

Fetches secrets from HashiCorp Vault using GitHub OIDC authentication.

```yaml
- name: Vault
  id: secrets
  uses: SonarSource/vault-action-wrapper@v3 # v3.1.0
  with:
    secrets: |
      development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader access_token | ARTIFACTORY_ACCESS_TOKEN;
      development/kv/data/next url | SONAR_HOST_URL;
      development/kv/data/next token | SONAR_TOKEN;
```

**Key Features:**

- **OIDC Authentication**: No stored secrets required - uses GitHub OIDC tokens
- **Dynamic Path Resolution**: `{REPO_OWNER_NAME_DASH}` automatically replaced with repository path
- **Multi-Secret Fetch**: Fetch multiple secrets in a single action call
- **JSON Output**: Secrets available via `fromJSON(steps.secrets.outputs.vault).SECRET_NAME`
- **Required permissions:** `id-token: write`

## Complete Vault Migration Example from Cirrus CI to GitHub Actions

**BEFORE (Cirrus CI):**

```yaml
build_task:
  name: Build
  env:
    # Direct vault references in environment
    ARTIFACTORY_DEPLOY_USERNAME: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer username]
    ARTIFACTORY_DEPLOY_PASSWORD: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer access_token]
    ARTIFACTORY_USERNAME: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader username]
    ARTIFACTORY_PASSWORD: VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader access_token]
  build_script:
    - source cirrus-env BUILD
    - regular_gradle_build_deploy_analyze
```

**AFTER (GitHub Actions):**

```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4

      # Step 1: Retrieve secrets from Vault
      - name: Vault
        id: secrets
        uses: SonarSource/vault-action-wrapper@v3 # 3.1.0
        with:
          secrets: |
            development/artifactory/token/{REPO_OWNER_NAME_DASH}-qa-deployer username | ARTIFACTORY_DEPLOY_USERNAME;
            development/artifactory/token/{REPO_OWNER_NAME_DASH}-qa-deployer access_token | ARTIFACTORY_DEPLOY_ACCESS_TOKEN;
            development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader username | ARTIFACTORY_USERNAME;
            development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader access_token | ARTIFACTORY_ACCESS_TOKEN;
      # Step 2: Use secrets in build action
      - name: Build, Analyze and deploy
        id: build
        uses: SonarSource/ci-github-actions/build-gradle@v1
        with:
          artifactory-deploy-repo: "sonarsource-private-qa"
          deploy-pull-request: true
        env:
          # Reference vault outputs using fromJSON
          ARTIFACTORY_DEPLOY_USERNAME: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_DEPLOY_USERNAME }}
          ARTIFACTORY_DEPLOY_ACCESS_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_DEPLOY_ACCESS_TOKEN }}
          ARTIFACTORY_USERNAME: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_USERNAME }}
          ARTIFACTORY_ACCESS_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_ACCESS_TOKEN }}
```

**Variable Transformation Rules:**

| Cirrus CI | GitHub Actions | Notes |
|-----------|----------------|-------|
| `${CIRRUS_REPO_OWNER}` | `{REPO_OWNER_NAME_DASH}` | Automatically replaced by vault-action-wrapper |
| `${CIRRUS_REPO_NAME}` | *(removed)* | Now included in `{REPO_OWNER_NAME_DASH}` |
| `VAULT[path field]` | `path field \| OUTPUT_NAME;` | New syntax with pipe separator |
| Direct env reference | `fromJSON(steps.secrets.outputs.vault).OUTPUT_NAME` | Must use fromJSON to parse vault output |

**Key Differences:**

1. **Two-step process**: Vault retrieval → Build execution
2. **JSON output**: Secrets are returned as JSON and must be parsed with `fromJSON()`
3. **Step references**: Use `steps.{step-id}.outputs.vault` to reference vault step
4. **Repository naming**: `{REPO_OWNER_NAME_DASH}` combines owner and repo with dashes

**Common Vault Paths Used by SonarSource Actions:**

| Secret Type | Vault Path | Usage |
|-------------|------------|-------|
| **Artifactory Reader** | `development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader` | Reading dependencies |
| **Artifactory Deployer** | `development/artifactory/token/{REPO_OWNER_NAME_DASH}-qa-deployer` | Deploying artifacts |
| **Artifactory Promoter** | `development/artifactory/token/{REPO_OWNER_NAME_DASH}-promoter` | Promoting builds |
| **SonarQube Next** | `development/kv/data/next` | Primary SonarQube platform |
| **SonarCloud EU** | `development/kv/data/sonarcloud` | SonarCloud European platform |
| **SonarQube US** | `development/kv/data/sonarqube-us` | SonarQube US platform |
| **Code Signing** | `development/kv/data/sign` | JAR/artifact signing |
| **GitHub Token** | `development/github/token/{REPO_OWNER_NAME_DASH}-promotion` | GitHub API operations |

**❌ Manual Usage Not Recommended:**

Since all SonarSource custom actions automatically handle vault secret fetching, you should **avoid using
vault-action-wrapper manually** unless you have specific requirements not covered by the build actions.

```yaml
# ❌ AVOID - Manual vault usage when build actions are sufficient
- name: Vault
  id: secrets
  uses: SonarSource/vault-action-wrapper@v3
  with:
    secrets: |
      development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader username | ARTIFACTORY_USERNAME;
      development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader access_token | ARTIFACTORY_ACCESS_TOKEN;
- name: Build
  env:
    ARTIFACTORY_USERNAME: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_USERNAME }}
    ARTIFACTORY_ACCESS_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).ARTIFACTORY_ACCESS_TOKEN }}
  uses: SonarSource/ci-github-actions/build-maven@v1

# ✅ PREFERRED - Use integrated build action
- uses: SonarSource/ci-github-actions/build-maven@v1
  # Vault secrets handled automatically
```

### Required Actions for All Projects

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
    artifactory-reader-role: private-reader       # private-reader/public-reader
    artifactory-deployer-role: qa-deployer        # qa-deployer/public-deployer
    maven-local-repository-path: .m2/repository   # Maven cache path
    scanner-java-opts: -Xmx512m                   # JVM options for SonarQube scanner
    use-develocity: false                          # Enable Develocity build tracking
```

**Features:**

- Automatic build context detection (master, maintenance, PR, dogfood, feature)
- SonarQube analysis with context-appropriate profiles
- Artifact signing and conditional deployment
- **Required permissions:** `id-token: write`, `contents: write`

##### Overriding Artifactory Roles

Some public repositories use private Artifactory credentials instead of the default public ones. This is
common when the repository content is public but the project needs access to private Artifactory repositories.

```yaml
# Override artifactory roles to match existing Cirrus CI configuration
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    artifactory-reader-role: private-reader    # Override default public-reader
    artifactory-deployer-role: qa-deployer     # Override default public-deployer
```

**🔍 Detection Steps - Follow These Exactly**:

1. **Check repository visibility**: Verify that the repository is public
2. **Examine `.cirrus.yml` for private reader pattern**:
    Look for: `VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-private-reader access_token]`

3. **Examine `.cirrus.yml` for qa-deployer pattern**:
    Look for: `VAULT[development/artifactory/token/${CIRRUS_REPO_OWNER}-${CIRRUS_REPO_NAME}-qa-deployer access_token]`

**🎯 Decision Matrix**:

| Repository Type | Reader Pattern Found | Deployer Pattern Found | Action Required |
|----------------|---------------------|------------------------|-----------------|
| **Public**     | ✅ `private-reader`  | ✅ `qa-deployer`       | **Override both roles** |
| **Public**     | ❌ No pattern       | ❌ No pattern          | **Use defaults** |
| **Private**    | Any pattern         | Any pattern            | **Use defaults** |

**🛠️ Implementation Examples**:

```yaml
# Example 1: Public repo with private artifactory access (OVERRIDE NEEDED)
# Found in .cirrus.yml: ARTIFACTORY_PRIVATE_PASSWORD: VAULT[...private-reader...]
# Found in .cirrus.yml: ARTIFACTORY_DEPLOY_PASSWORD: VAULT[...qa-deployer...]
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    artifactory-reader-role: private-reader    # Override default public-reader
    artifactory-deployer-role: qa-deployer     # Override default public-deployer

# Example 2: Public repo with public artifactory access (NO OVERRIDE NEEDED)
# No private-reader or qa-deployer patterns found in .cirrus.yml
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    # artifactory roles auto-detected (public-reader, public-deployer)

# Example 3: Private repo (NO OVERRIDE NEEDED)
# Regardless of patterns in .cirrus.yml
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    # artifactory roles auto-detected (private-reader, qa-deployer)
```

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

##### Migrating Gradle Parameters from regular_gradle_build_deploy_analyze

When migrating from Cirrus CI, parameters passed to `regular_gradle_build_deploy_analyze` should be moved to the `gradle-args` parameter:

**Cirrus CI Pattern**:

```yaml
# .cirrus.yml
build_script:
  - source cirrus-env BUILD-PRIVATE
  - regular_gradle_build_deploy_analyze -PexecuteSpotless -Dscan.tag.CI
```

**GitHub Actions Migration**:

```yaml
- uses: SonarSource/ci-github-actions/build-gradle@v1
  with:
    gradle-args: "-PexecuteSpotless -Dscan.tag.CI"  # All parameters from regular_gradle_build_deploy_analyze
```

**Migration Steps**:

1. Find `regular_gradle_build_deploy_analyze` call in `.cirrus.yml`
2. Copy all parameters after the function name
3. Add them to `gradle-args` parameter in GitHub Actions

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
    repox-url: https://repox.jfrog.io                    # Repox URL
    sonar-platform: next                                 # SonarQube platform (next, sqc-eu, sqc-us)
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
    skip-tests: false                                  # Skip running tests
    cache-npm: true                                    # Cache NPM dependencies
    repox-url: https://repox.jfrog.io                 # Repox URL
    sonar-platform: next                              # SonarQube platform (next, sqc-eu, sqc-us)
```

**Features:**

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality (credentials from Vault)
- Conditional deployment based on branch patterns (main, maintenance, dogfood branches)
- NPM dependency caching for faster builds (configurable)
- JFrog build info publishing with UI links
- **Required permissions:** `id-token: write`, `contents: write`
- **Outputs:** `project-version` from package.json

#### YARN Projects (JavaScript/TypeScript)

```yaml
- uses: SonarSource/ci-github-actions/build-yarn@v1
  with:
    deploy-pull-request: false                        # Deploy pull request artifacts
    # All parameters below are optional
    artifactory-deploy-repo: ""                       # Artifactory repository name
    skip-tests: false                                  # Skip running tests
    cache-yarn: true                                   # Cache Yarn dependencies
    repox-url: https://repox.jfrog.io                 # Repox URL
    sonar-platform: next                              # SonarQube platform (next, sqc-eu, sqc-us)
```

**Features:**

- Automated version management with build numbers and SNAPSHOT handling
- SonarQube analysis for code quality (credentials from Vault)
- Conditional deployment based on branch patterns (main, maintenance, dogfood branches)
- NPM dependency caching for faster builds (configurable)
- JFrog build info publishing with UI links
- **Required permissions:** `id-token: write`, `contents: write`
- **Outputs:** `project-version` from package.json

##### Overriding Pull Request Deployment and Promotion

Certain repositories want to publish PR artifacts to repox and promote them to the `builds` repository from the initial `qa` repository.
This is useful if the project is being tested in another project and you want to reference it from another repository.

**When to use this**: If your Cirrus CI pipeline has the environment variable `DEPLOY_PULL_REQUEST` set to `true`, you need to configure
these parameters for both the build and promote actions.

**GitHub Actions Configuration:**

```yaml
# .github/workflows/build.yml
jobs:
  build:
    # ... other configuration
    steps:
      - uses: SonarSource/ci-github-actions/build-maven@v1
        with:
          deploy-pull-request: true    # Deploy PR artifacts to qa repository

  promote:
    # ... other configuration
    steps:
      - uses: SonarSource/ci-github-actions/promote@v1
        with:
          promote-pull-request: true   # Promote PR artifacts to builds repository
```

**Cirrus CI Equivalent:**

```yaml
# .cirrus.yml
env:
  DEPLOY_PULL_REQUEST: "true"  # This triggers both deployment and promotion for PRs
```

**Key Points:**

- **Build Action**: `deploy-pull-request: true` deploys PR artifacts to the `qa` repository
- **Promote Action**: `promote-pull-request: true` promotes PR artifacts from `qa` to `builds` repository
- **Cross-Repository Testing**: Enables other projects to reference PR artifacts for testing
- **Automatic Promotion**: PR artifacts are automatically promoted, not just deployed

**Migration Steps:**

1. **Check Cirrus CI**: Look for `DEPLOY_PULL_REQUEST: "true"` in your `.cirrus.yml`
2. **Configure Build Action**: Add `deploy-pull-request: true` to your build action
3. **Configure Promote Action**: Add `promote-pull-request: true` to your promote action

##### Overriding SonarQube Platform

The SonarQube platform used for analysis is based on the `SONAR_HOST_URL` in your Cirrus CI configuration.

**🔍 Detection Steps - Follow These Exactly**:

1. **Examine `.cirrus.yml` for SONAR_HOST_URL pattern**:
   Look for: `SONAR_HOST_URL: VAULT[development/kv/data/... data.url]`

2. **Check the vault path to determine platform**:
   - `development/kv/data/next` → **No action needed** (default platform)
   - `development/kv/data/sonarcloud` → Set `sonar-platform: sqc-eu`
   - `development/kv/data/sonarqube-us` → Set `sonar-platform: sqc-us`

**🎯 Decision Matrix**:

| Vault Path in .cirrus.yml                    | SONAR_HOST_URL Contains | Action Required                    |
|----------------------------------------------|-------------------------|-----------------------------------|
| `development/kv/data/next`                   | `next`                  | **No override needed** (default)  |
| `development/kv/data/sonarcloud`             | `sonarcloud`            | **Set `sonar-platform: sqc-eu`**  |
| `development/kv/data/sonarqube-us`           | `sonarqube-us`          | **Set `sonar-platform: sqc-us`**  |

**🛠️ Implementation Examples**:

```yaml
# Example 1: Using sonarcloud platform (EU)
# Found in .cirrus.yml: SONAR_HOST_URL: VAULT[development/kv/data/sonarcloud data.url]
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    sonar-platform: sqc-eu    # Override default next platform

# Example 2: Using sonarqube-us platform (US)
# Found in .cirrus.yml: SONAR_HOST_URL: VAULT[development/kv/data/sonarqube-us data.url]
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    sonar-platform: sqc-us    # Override default next platform

# Example 3: Using next platform (default)
# Found in .cirrus.yml: SONAR_HOST_URL: VAULT[development/kv/data/next data.url]
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    # sonar-platform auto-detected (next) - no override needed
```

**Available platform options**:

- **`next`**: Default SonarQube platform (auto-detected)
- **`sqc-eu`**: SonarCloud EU platform
- **`sqc-us`**: SonarCloud US platform

**Migration Steps**:

1. **Check Cirrus CI**: Look for `SONAR_HOST_URL` in your `.cirrus.yml`
2. **Identify vault path**: Determine which vault path is used for the SonarQube URL
3. **Configure platform**: Add `sonar-platform` parameter if needed (see decision matrix above)
4. **Test analysis**: Verify that SonarQube analysis works with the correct platform

### Additional Actions

#### cache

Adaptive cache action that automatically chooses the appropriate caching backend based on repository visibility.

```yaml
- uses: SonarSource/ci-github-actions/cache@v1
  with:
    path: |
      ~/.m2/repository
      ~/.cache/pip
    key: cache-${{ runner.os }}-${{ hashFiles('**/pom.xml', '**/requirements.txt') }}
    restore-keys: cache-${{ runner.os }}-
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
    types: [ closed ]
jobs:
  cleanup:
    runs-on: sonar-xs
    permissions:
      actions: write
    steps:
      - uses: SonarSource/ci-github-actions/pr_cleanup@v1
```

## Cirrus CI → GitHub Actions Mapping

### Environment Variables

Complete mapping table for ci-common-scripts compatibility:

| Cirrus CI Variable                               | GitHub Actions Variable                             | Purpose                                          |
|--------------------------------------------------|-----------------------------------------------------|--------------------------------------------------|
| `GIT_SHA1` or `CIRRUS_CHANGE_IN_REPO`            | `GITHUB_SHA`                                        | Git commit SHA                                   |
| `GITHUB_BASE_BRANCH` or `CIRRUS_BASE_BRANCH`     | `GITHUB_BASE_REF`                                   | Base branch for PRs                              |
| `CIRRUS_BASE_SHA`                                | -                                                   | Base SHA for PRs                                 |
| `GITHUB_BRANCH` or `CIRRUS_BRANCH`               | `GITHUB_HEAD_REF` (PR) / `GITHUB_REF_NAME` (branch) | Current branch                                   |
| `GITHUB_REPO` or `CIRRUS_REPO_FULL_NAME`         | `GITHUB_REPOSITORY`                                 | Full repo name (owner/repo)                      |
| `CIRRUS_REPO_NAME` or `PROJECT`                  | `"${GITHUB_REPOSITORY#*/}"`                         | Repository short name                            |
| `CIRRUS_BUILD_ID` or `PIPELINE_ID`               | `GITHUB_RUN_ID`                                     | Cirrus CI build / GitHub workflow run identifier |
| `CIRRUS_TASK_ID`                                 | `GITHUB_JOB`                                        | Cirrus CI task / GitHub job identifier           |
| `BUILD_NUMBER`, `CI_BUILD_NUMBER`, or `BUILD_ID` | `BUILD_NUMBER`                                      | Build number                                     |
| `CIRRUS_DEFAULT_BRANCH`                          | `${{ github.event.repository.default_branch }}`     | Default branch                                   |
| `CIRRUS_ENV`                                     | `GITHUB_ENV`                                        | Environment file path                            |

#### Specific Environment Variable Mappings

Cirrus CI configurations often include these patterns:

```yaml
# Cirrus CI
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

| Cirrus CI            | GitHub Actions           |
|----------------------|--------------------------|
| `eks_container`      | `runs-on: sonar-xs` (private) / `github-ubuntu-latest-s` (public) |
| `cpu: 2, memory: 2G` | Runner handles resources |
| Custom images        | Use mise for tools       |

#### Resource Requirements

```yaml
# Cirrus CI
eks_container:
  <<: *CONTAINER_DEFINITION
  cpu: 2
  memory: 2G
```

**GitHub Actions Runner Selection**:

⚠️ **IMPORTANT**: Before selecting a runner, verify if your repository is **public** or **private**.

### Custom GitHub-Hosted Runners (for public repos and DIND)

**Used for**:

- Public repositories
- Private repositories that require Docker-in-Docker

**Available sizes**:

- `github-ubuntu-latest-s`
- `github-ubuntu-24.04-arm-s`
- `github-windows-latest-s`
- `github-ubuntu-latest-m`
- `github-ubuntu-24.04-arm-m`
- `github-ubuntu-latest-l`

**Example**:

```yaml
jobs:
  build:
    runs-on: github-ubuntu-latest-s
    steps:
      - uses: actions/checkout@v4
      - run: echo "Custom GitHub-hosted runner"
```

Self-Hosted Runners (default for private repos)

**Best for**:

- Default for private repositories
- Access to internal tools and private resources (unified connectivity)

**Available sizes**:

- `sonar-xs`
- `sonar-s`
- `sonar-m`
- `sonar-l`
- `sonar-xl`

**Example**:

```yaml
jobs:
  build:
    runs-on: sonar-m
    steps:
      - uses: actions/checkout@v4
      - run: echo "Private self-hosted (new generation)"
```

**Limitations**:

- Docker-in-Docker is **not supported** (use Custom GitHub-hosted for DIND)

### Quick Selection Guide

**For Public Repositories**:

- **Standard builds**: `github-ubuntu-latest-s`

**For Private Repositories**:

- **Standard builds**: `sonar-xs` (default) → scale up as needed
- **Large builds**: `sonar-s`, `sonar-m`, `sonar-l`, `sonar-xl`

#### Job Dependencies

```yaml
# Cirrus CI
promote_task:
  depends_on:
    - build

# GitHub Actions
promote:
  needs:
    - build  # Cleaner syntax
```

### Conditional Execution

| Cirrus CI Pattern                              | GitHub Actions Pattern                |
|------------------------------------------------|---------------------------------------|
| `only_if: $CIRRUS_USER_COLLABORATOR == 'true'` | Built into SonarSource custom actions |
| `only_if: $CIRRUS_TAG == ""`                   | Built into promotion logic            |
| `only_if: $CIRRUS_PR != ""`                    | Use `if:` conditions on jobs          |

#### Complex Cirrus CI Conditions

Original Cirrus CI often has complex anchor patterns like:

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

| Cirrus CI                          | GitHub Actions              |
|------------------------------------|-----------------------------|
| `source cirrus-env BUILD-PRIVATE`  | Handled by custom actions   |
| `regular_mvn_build_deploy_analyze` | `build-maven@v1` action     |
| `cleanup_maven_repository`         | Automatic in custom actions |

#### Cache and Cleanup Patterns

Cirrus CI typically includes:

```yaml
# Cirrus CI
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
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
- uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
  with:
    version: 2025.7.12

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

**RECOMMENDED**: Define concurrency at workflow level (cleaner and simpler):

```yaml
name: Build
on:
  push:
    branches: [master, branch-*, dogfood-*]
  pull_request:
  merge_group:
  workflow_dispatch:

# ✅ Workflow-level concurrency - RECOMMENDED
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  build:
    # No job-level concurrency needed
    runs-on: sonar-xs
  promote:
    # No job-level concurrency needed
    needs: [build]
    runs-on: sonar-xs
```

**Avoid**: Job-level concurrency duplication (more complex, error-prone):

```yaml
# ❌ Job-level concurrency - NOT RECOMMENDED
jobs:
  build:
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: true
  promote:
    concurrency:  # Duplicated configuration
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: true
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
3. Build action (`build-maven@v1`, etc.)
4. `promote@v1` (promote job only)

### 7. Avoid Unnecessary Environment Variables

❌ Don't add unused env vars like:

```yaml
env:
  DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}  # Usually not needed
```

## Repository-Specific Configurations

### Repository Visibility Detection and Configuration

Repository visibility is automatically detected using multiple indicators:

1. **Primary Detection**: GitHub repository visibility (public/private)
2. **Secondary Detection**: `ARTIFACTORY_DEPLOY_REPO` value in `.cirrus.yml`
3. **Override Detection**: Specific vault patterns for artifactory roles

#### Automatic Repository Visibility Detection

```yaml
# Detection from ARTIFACTORY_DEPLOY_REPO in .cirrus.yml
env:
  ARTIFACTORY_DEPLOY_REPO: sonarsource-private-qa  # → Detected as private repository
  # OR
  ARTIFACTORY_DEPLOY_REPO: sonarsource-public-qa   # → Detected as public repository
```

#### Configuration Results by Repository Type

**Private Repository** (`ARTIFACTORY_DEPLOY_REPO: sonarsource-private-qa`):

```yaml
# Auto-detected configuration - no overrides needed
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    # Automatically uses:
    # - Runner: sonar-xs
    # - Artifactory reader role: private-reader
    # - Artifactory deployer role: qa-deployer
    # - public: false
```

**Public Repository** (`ARTIFACTORY_DEPLOY_REPO: sonarsource-public-qa`):

```yaml
# Auto-detected configuration - no overrides needed
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    # Automatically uses:
    # - Runner: github-ubuntu-latest-s (for auth actions)
    # - Artifactory reader role: public-reader
    # - Artifactory deployer role: public-deployer
    # - public: true
```

**Public Repository with Private Access** (Mixed configuration):

```yaml
# Manual override required when .cirrus.yml contains:
# ARTIFACTORY_DEPLOY_REPO: sonarsource-private-qa (but repo is public)
# ARTIFACTORY_PRIVATE_PASSWORD: VAULT[...private-reader...]
- uses: SonarSource/ci-github-actions/build-maven@v1
  with:
    deploy-pull-request: true
    artifactory-reader-role: private-reader    # Override auto-detection
    artifactory-deployer-role: qa-deployer     # Override auto-detection
```

**Key Point**: Repository visibility is automatically detected from the `ARTIFACTORY_DEPLOY_REPO` value in `.cirrus.yml`.
The `public` parameter and Artifactory roles are determined based on this value and GitHub repository visibility.
Only override if you have specific requirements (e.g., public repo needing private Artifactory access).

## Migration Checklist

### Phase 1: Setup

- [ ] **CRITICAL**: Check repository visibility (Settings → General → Repository visibility)
- [ ] Select correct runner type based on repository visibility:
  - [ ] Public repo → `github-ubuntu-latest-s`
  - [ ] Private repo → `sonar-xs`
- [ ] **SECURITY**: Pin all third-party actions to commit SHA
- [ ] **SECURITY**: Verify permissions follow least-privilege principle
- [ ] Check similar dummy repository for your project type
- [ ] Create `mise.toml` with required tool versions
- [ ] Verify Vault permissions are configured
- [ ] Create `.github/workflows/build.yml`
- [ ] Verify no conflicts with existing workflows
- [ ] **DOCUMENTATION**: Identify all documentation files requiring updates (see Phase 6)

### Phase 2: Build Job

- [ ] Add standard triggers (push, PR, merge_group, workflow_dispatch)
- [ ] **Select appropriate runner type**:
  - [ ] Private repos: `sonar-xs`
  - [ ] Public repos: `github-ubuntu-latest-s`
  - [ ] Docker-in-Docker needed: `github-ubuntu-latest-s` (regardless of repo visibility)
  - [ ] Public repos needing internal tools: `sonar-*-public` (requires approval)
- [ ] **Configure concurrency control**:
  - [ ] **RECOMMENDED**: Add workflow-level concurrency (cleaner)
  - [ ] **AVOID**: Job-level concurrency duplication
  - [ ] Verify concurrency is defined only at workflow level, not job level
- [ ] Add checkout, mise steps
- [ ] Add appropriate build action (maven/gradle/poetry)
- [ ] **Verify Overriding Artifactory Roles**:
  - [ ] Check repository visibility (public/private)
  - [ ] Search `.cirrus.yml` for `private-reader` vault pattern
  - [ ] Search `.cirrus.yml` for `qa-deployer` vault pattern
  - [ ] If public repo + both patterns found → Add `artifactory-reader-role: private-reader` and `artifactory-deployer-role: qa-deployer`
  - [ ] If public repo + no patterns found → Use default auto-detection (no override needed)
  - [ ] If private repo → Use default auto-detection (no override needed)
- [ ] Verify Overriding Pull Request Deployment and Promotion
- [ ] **Verify Overriding SonarQube Platform**:
  - [ ] Search `.cirrus.yml` for `SONAR_HOST_URL` vault pattern
  - [ ] If vault path contains `sonarcloud` → Add `sonar-platform: sqc-eu`
  - [ ] If vault path contains `sonarqube-us` → Add `sonar-platform: sqc-us`
  - [ ] If vault path contains `next` → Use default auto-detection (no override needed)
- [ ] **If using cirrus-modules**: Verify all features are covered by SonarSource custom actions
- [ ] Test build job functionality

### Phase 3: Promote Job

- [ ] Add promote job with proper dependencies
- [ ] Configure same concurrency control
- [ ] Add checkout, mise (with cache_save: false)
- [ ] Add promote action
- [ ] Verify Overriding Pull Request Deployment and Promotion
- [ ] Test promotion functionality

### Phase 4: Additional Workflows

- [ ] **Replace manual pr-cleanup.yml** with official SonarSource action (see details below)
- [ ] Add `pr-cleanup.yml` for automatic PR resource cleanup if not present
- [ ] Consider stable-branch-update job if needed
- [ ] Set up any project-specific additional workflows

#### PR Cleanup Workflow Migration

**CRITICAL**: If `.github/workflows/pr-cleanup.yml` exists, check if it uses manual implementation:

**❌ Replace Manual Implementation:**

```yaml
# Manual implementation (64+ lines) - REPLACE THIS
name: Cleanup caches and artifacts on PR close
jobs:
  cleanup:
    steps:
      - name: Cleanup caches
        run: |
          # Complex shell scripts with gh cache commands...
      - name: Delete artifacts
        run: |
          # Complex shell scripts with gh api commands...
```

**✅ With Official SonarSource Action:**

```yaml
# Official implementation (13 lines) - USE THIS
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

### Phase 5: Cleanup & Configuration

⚠️ **IMPORTANT**: During the migration, remove from `.cirrus.yml` the tasks that are now handled by GitHub Actions.
If no task remain, then remove the Cirrus CI files: `.cirrus.yml`, `.cirrus.star`, `.cirrus/Dockerfile`...

- [ ] Verify all Cirrus CI functionality is replicated
- [ ] Configure build number in repository settings (> latest Cirrus CI build)
- [ ] Test both PR and branch builds
- [ ] Keep `.cirrus.yml` as-is (DO NOT remove or comment out during migration)

### Phase 6: Documentation Updates

**CRITICAL**: Always update documentation to reflect the migration. Search systematically:

#### Build Badges

- [ ] **README.md**: Replace Cirrus CI badges with GitHub Actions badges
  ```markdown
  # Before (Cirrus CI)
  ![Cirrus CI - Branch Build Status](https://img.shields.io/cirrus/github/SonarSource/REPO/master?task=TASK&label=LABEL)

  # After (GitHub Actions)
  [![Build](https://github.com/SonarSource/REPO/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/SonarSource/REPO/actions/workflows/build.yml)
  ```

#### Working Directory Path References

- [ ] **Search workflows for Cirrus CI paths**: Look for `/tmp/cirrus-ci-build/` references
- [ ] **Replace with GitHub Actions paths**: Use `$GITHUB_WORKSPACE/` or relative paths
  ```bash
  # Before (Cirrus CI)
  sed "s|/tmp/cirrus-ci-build/src/|src/|g"

  # After (GitHub Actions)
  sed "s|$GITHUB_WORKSPACE/src/|src/|g"
  ```

#### Manual Workflow Replacements

- [ ] **Check existing pr-cleanup.yml**: Look for manual `gh cache` and `gh api` commands
- [ ] **Replace with official action**: Use `SonarSource/ci-github-actions/pr_cleanup@v1`
- [ ] **Verify correct permissions**: Ensure `actions: write` permission is set
- [ ] **Search for other manual implementations** that have official SonarSource equivalents

#### Systematic Documentation Search

- [ ] **Search all `.md` files** for Cirrus CI references:
  ```bash
  grep -ri "cirrus\|\.cirrus" *.md
  ```
- [ ] **Update CI setup instructions** in CONTRIBUTE.md (if present)
- [ ] **Update any workflow documentation** that references `.cirrus.yml`
- [ ] **Check for environment variable references** that may need updating

#### Pre-commit Integration

- [ ] **Run pre-commit on all changed files** to ensure formatting compliance
- [ ] **Fix any linting issues** reported by pre-commit hooks

## Vault Permissions Setup

Ensure your repository has the required Vault permissions in `re-terraform-aws-vault/orders`:

```yaml
some-repository:
  auth:
    github: {}
  secrets:
    artifactory:
      roles:
        - *artifactory_public-reader     # For PUBLIC repository, reader token
        - *artifactory_public-deployer   # For PUBLIC repository, deployer token
        - *artifactory_private-reader    # For PRIVATE repository, reader token
        - *artifactory_qa-deployer       # For PRIVATE repository, deployer token
        - *artifactory_promoter          # For artifact promotion
    github:
      presets:
        - licenses                       # Only for QA tests
      customs:
        - <<: *github_jira               # For gh-action-lt-backlog
          repositories: [some-repository]
        - <<: *github_promotion          # GitHub checks with build number
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

**Note**: Most secrets should already exist from Cirrus CI usage.

## Build Number Configuration

**Critical Step**: After migration, configure the GitHub build number: login to SPEED and run the
[Update GitHub Build Number](https://app.getport.io/self-serve?action=update_github_build_number) action.

## Additional Example Repositories

Reference these SonarSource dummy repositories for specific patterns:

| Repository                                                                                  | Type                | Build System | Notes                          |
|---------------------------------------------------------------------------------------------|---------------------|--------------|--------------------------------|
| [sonar-dummy](https://github.com/SonarSource/sonar-dummy)                                   | Private Java        | Maven        | Standard private Maven project |
| [sonar-dummy-maven-enterprise](https://github.com/SonarSource/sonar-dummy-maven-enterprise) | Public+Private Java | Maven        | Mixed public/private content   |
| [sonar-dummy-yarn](https://github.com/SonarSource/sonar-dummy-yarn)                         | Private NodeJS      | NPM+Yarn     | Node.js with Yarn              |
| [sonar-dummy-js](https://github.com/SonarSource/sonar-dummy-js)                             | Private JavaScript  | NPM          | JavaScript project             |
| [sonar-dummy-oss](https://github.com/SonarSource/sonar-dummy-oss)                           | Public Java         | Gradle       | Public Gradle project          |
| [sonar-dummy-python-oss](https://github.com/SonarSource/sonar-dummy-python-oss)             | Public Python       | Poetry       | Public Python with Poetry      |

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

- Use Maven cache key format: `maven-${{ runner.os }}` (better UI filtering)
- Include `pr-cleanup.yml` for automatic PR resource cleanup
- **SECURITY**: Pin all third-party actions to commit SHA
- **SECURITY**: Use environment variables for untrusted input
- **SECURITY**: Document all permissions with comments explaining why they're needed
- **DOCUMENTATION**: Update README.md build badges from Cirrus CI to GitHub Actions
- **DOCUMENTATION**: Replace all Cirrus CI path references with GitHub Actions equivalents
- **DOCUMENTATION**: Search systematically for all CI system references in `.md` files
- **WORKFLOWS**: Replace manual pr-cleanup.yml implementations with SonarSource/ci-github-actions/pr_cleanup@v1

### ❌ DON'T Do These

- Don't specify `GH_TOKEN` environment variable in build job (auto-handled)
- Don't trigger on `gh-readonly-queue/*` branches
- Don't upload `${{ github.event_path }}` file as artifact
- Don't use GitHub licenses token except for QA tests
- **SECURITY**: Don't use unpinned third-party actions (`@main`, `@v1`)
- **SECURITY**: Don't use untrusted input directly in shell commands
- **SECURITY**: Don't upload entire directories as artifacts (may contain secrets)
- **SECURITY**: Don't cache sensitive information (tokens, keys, credentials)
- **DOCUMENTATION**: Don't forget to update README.md build badges
- **DOCUMENTATION**: Don't leave Cirrus CI path references (e.g., `/tmp/cirrus-ci-build/`)
- **DOCUMENTATION**: Don't skip systematic search for CI references in documentation files
- **WORKFLOWS**: Don't keep manual pr-cleanup implementations when official SonarSource actions exist

## Troubleshooting

### Common Issues

1. **Missing permissions**: Ensure `id-token: write` and `contents: write` are set
2. **Tool versions**: Use mise.toml instead of manual setup actions
3. **Cache conflicts**: Use `cache_save: false` in promote jobs
4. **Branch conditions**: Let custom actions handle most conditional logic
5. **Build number continuity**: Set custom property > latest Cirrus CI build
6. **Artifactory role mismatch**: If your Cirrus CI uses different roles than auto-detected, override them:
   ```yaml
   # Check .cirrus.yml for actual roles used and override if needed
   - uses: SonarSource/ci-github-actions/build-maven@v1
     with:
       artifactory-reader-role: private-reader    # Match Cirrus CI config
       artifactory-deployer-role: qa-deployer     # Match Cirrus CI config
   ```
7. **Cirrus-modules migration**: If migrating from cirrus-modules, don't try to recreate individual features
   manually - use the comprehensive SonarSource custom actions instead
8. **Security**: Ensure third-party actions are pinned to commit SHA
9. **Script injection**: Never use untrusted input directly in shell commands
10. **Vault authentication**: Ensure `id-token: write` permission is set for OIDC authentication
11. **Vault permissions**: Check that repository has required vault permissions in `re-terraform-aws-vault/orders`
12. **Runner selection**: Ensure you're using current runner names (see **GitHub Actions Runner Selection** section)

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

### Understanding Cirrus-Modules Configuration with .cirrus.generated.yml

When migrating repositories that use `cirrus-modules`, it can be helpful to see the actual YAML configuration that the Starlark code
generates. This makes it easier to understand what features need to be replicated in GitHub Actions.

#### Generating the Interpolated Configuration

To see the expanded configuration that `cirrus-modules` generates, you can create a `.cirrus.generated.yml` file by running the Starlark
interpolation locally:

```bash
# Generate the expanded configuration
CIRRUS_REPO_NAME=$(basename $(git rev-parse --show-toplevel))
CIRRUS_DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq ".defaultBranchRef.name")
cat .cirrus.yml > .cirrus.generated.yml
cirrus validate -f .cirrus.star -p -e "CIRRUS_REPO_CLONE_TOKEN=$(gh auth token)" \
  -e "CIRRUS_BRANCH=$CIRRUS_DEFAULT_BRANCH" -e "CIRRUS_DEFAULT_BRANCH=$CIRRUS_DEFAULT_BRANCH" \
  -e "CIRRUS_REPO_OWNER=SonarSource" -e "CIRRUS_REPO_NAME=$CIRRUS_REPO_NAME" -e "CIRRUS_REPO_FULL_NAME=SonarSource/$CIRRUS_REPO_NAME" \
  >> .cirrus.generated.yml
```

#### Using .cirrus.generated.yml for Migration

The generated file shows you exactly what tasks, environments, and configurations the Starlark code creates. Use this file to:

- **Identify all tasks and dependencies** that need to be migrated
- **Understand environment variables** and vault secrets being used
- **Map Cirrus CI patterns** to their GitHub Actions equivalents
- **Verify completeness** of your migration by comparing features

**Example workflow for migration**:

```bash
# 1. Generate the expanded configuration

# 2. Review the generated tasks
grep -E "(task:|depends_on:|only_if:)" .cirrus.generated.yml

# 3. Identify environment variables and vault secrets
grep -E "(env:|VAULT\[)" .cirrus.generated.yml

# 4. Use this information to create your GitHub Actions workflows
# 5. Compare the generated file with your GitHub Actions implementation
```

**⚠️ Important Notes:**

- The `.cirrus.generated.yml` file is for **migration reference only**
- **Never commit** this file to your repository (add to `.gitignore`)
- **Always use the latest version** by regenerating when cirrus-modules updates
- **Remember**: GitHub Actions workflows will be simpler than the generated Cirrus CI config

#### Example Generated Content

A typical `.cirrus.generated.yml` might expand your simple `.cirrus.star` into something like:

```yaml
# This is what gets generated from load_features(ctx)
env:
  CIRRUS_CLONE_DEPTH: "20"
  CIRRUS_SHELL: bash
  ARTIFACTORY_URL: VAULT[development/kv/data/repox data.url]
  # ... many more environment variables

build_task:
  only_if: $CIRRUS_USER_COLLABORATOR == 'true' && ...
  eks_container:
    image: ${CIRRUS_AWS_ACCOUNT}.dkr.ecr.eu-central-1.amazonaws.com/base:j17-latest
    # ... container configuration
  env:
  # ... task-specific environment variables
  maven_cache:
    folder: ${CIRRUS_WORKING_DIR}/.m2/repository
  build_script:
    - source cirrus-env BUILD-PRIVATE
    - regular_mvn_build_deploy_analyze
  # ... more task configuration

promote_task:
  depends_on: [ build ]
  # ... promotion task configuration
```

This expanded view makes it clear what needs to be migrated to GitHub Actions workflows.

### Cirrus-Modules Features and GitHub Actions Equivalents

The cirrus-modules system provides several features that need to be handled during migration:

| Cirrus-Modules Feature    | GitHub Actions Equivalent                           | Notes                                   |
|---------------------------|-----------------------------------------------------|-----------------------------------------|
| **AWS Infrastructure**    | `runs-on: sonar-xs`                                 | Runner selection handles infrastructure |
| **Vault Authentication**  | `SonarSource/vault-action-wrapper`                  | Direct vault integration                |
| **Build Numbers**         | `SonarSource/ci-github-actions/get-build-number@v1` | Continuous build numbering              |
| **Repox/Artifactory**     | `SonarSource/ci-github-actions/build-*@v1`          | Handled by build actions                |
| **Conditional Execution** | `on:` triggers + `if:` conditions                   | GitHub Actions native conditions        |

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
      cancel-in-progress: true
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Build
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
        with:
          version: 2025.7.12
      - uses: SonarSource/ci-github-actions/build-maven@v1
        with:
          deploy-pull-request: true

  promote:
    needs: [build]
    concurrency:
      group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
      cancel-in-progress: true
    runs-on: sonar-xs  # Private repos default; use github-ubuntu-latest-s for public repos
    name: Promote
    permissions:
      id-token: write
      contents: write
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
        with:
          cache_save: false
          version: 2025.7.12
      - uses: SonarSource/ci-github-actions/promote@v1
        with:
          promote-pull-request: true
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

3. **Don't copy complex Cirrus CI conditions**:

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
   - uses: jdx/mise-action@5ac50f778e26fac95da98d50503682459e86d566 # v3.2.0
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
- Use `mise.toml` for tool versions
- Let parameters auto-detect from repository settings (public/private, Artifactory roles)
- **Leave `.cirrus.yml` unchanged during migration**
- Test with feature branches first

## Additional Migration Guidelines

### Checkout Depth Configuration

When migrating from Cirrus CI, replace specific checkout depth configurations (like CIRRUS_CLONE_DEPTH) with
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

Example from Cirrus CI that should be replaced:

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
  uses: SonarSource/sonarqube-scan-action@fd88b7d7ccbaefd23d8f36f73b59db7a3d246602 # v6.0.0
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    SONAR_TOKEN: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ fromJSON(steps.secrets.outputs.vault).SONAR_HOST_URL }}
```
