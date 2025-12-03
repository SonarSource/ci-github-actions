# Config Pip

GitHub Action to configure pip to use SonarSource's internal Artifactory registry for package installation.

This action replaces the deprecated `configure-pipx-repox` action from `sonarqube-cloud-github-actions` repository. It configures pip to
pull packages from the internal JFrog Artifactory registry instead of the default PyPI.

## Usage

To use this action in your workflow, include the following step:

```yaml
steps:
  - uses: SonarSource/ci-github-actions/config-pip@master
```

### With Custom Artifactory Reader Role

```yaml
steps:
  - uses: SonarSource/ci-github-actions/config-pip@master
    with:
      artifactory-reader-role: custom-reader
```

## Inputs

| Input                     | Description                                                                                                                                          | Default                  |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `artifactory-reader-role` | Suffix for the Artifactory reader role in Vault. Defaults to `private-reader` for private repositories, and `public-reader` for public repositories. | `''` (auto-detected)     |
| `repox-url`               | URL for Repox                                                                                                                                        | `https://repox.jfrog.io` |
| `repox-artifactory-url`   | URL for Repox Artifactory API (overrides repox-url/artifactory if provided)                                                                          | `''`                     |
| `host-actions-root`       | Path to the actions folder on the host (used when called from another local action)                                                                  | `''`                     |

## What It Does

1. **Sets up local action paths** - Configures paths for the action script
2. **Determines Artifactory reader role** - Automatically selects `private-reader` or `public-reader` based on repository visibility
3. **Fetches Vault secrets** - Retrieves Artifactory credentials (username and access token) from Vault
4. **Configures pip** - Creates `~/.pip/pip.conf` with the Artifactory registry URL and authentication credentials

After this action runs, all `pip install` commands will automatically use the internal Artifactory registry instead of PyPI.

## Example: Installing pipenv

```yaml
steps:
  - name: Checkout code
    uses: actions/checkout@v4

  - name: Set up Python
    uses: actions/setup-python@v5
    with:
      python-version: 3.12

  - name: Configure pip with Artifactory
    uses: SonarSource/ci-github-actions/config-pip@master

  - name: Install pipenv
    run: |
      python -m pip install --upgrade pip
      pip install pipenv
```

## Migration from configure-pipx-repox

If you're currently using `SonarSource/sonarqube-cloud-github-actions/configure-pipx-repox@master`, you can replace it with:

```yaml
# Old
- uses: SonarSource/sonarqube-cloud-github-actions/configure-pipx-repox@master

# New
- uses: SonarSource/ci-github-actions/config-pip@master
```

Both actions produce the same configuration and are functionally equivalent.
