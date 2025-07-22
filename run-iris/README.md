# Run IRIS Analysis Action

A reusable GitHub composite action that runs SonarSource IRIS analysis tool to synchronize projects between SonarQube instances.

## Usage

### External Repository Usage

When using this action from another repository (e.g., if moved to a dedicated action repository):

```yaml
- name: Run IRIS Analysis
  uses: SonarSource/sonar-iris-action/.github/actions/run-iris@main
  with:
    source_project_key: "SonarSource_your-project-name"
    source_organization: "sonarsource"
    destination_project_key: "SonarSource_your-project-name"
    destination_organization: "sonarsource"
```

### Basic Usage

```yaml
jobs:
  run-iris:
    runs-on: sonar-runner-on-demand
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Run IRIS Analysis
        uses: ./.github/actions/run-iris
        with:
          source_project_key: "SonarSource_your-project-name"
          source_organization: "your-organization"
          destination_project_key: "SonarSource_your-project-name"
          destination_organization: "your-organization"
```

### Complete Workflow Example

```yaml
name: Run IRIS Analysis

permissions:
  id-token: write
  contents: read
  pull-requests: read
  statuses: read
  checks: read

on:
  schedule:
    - cron: '20 */12 * * *'
  workflow_dispatch:
    inputs:
      github_environment:
        description: 'GitHub Environment'
        required: false
        type: string
        default: "ManualDispatch"
      runner_label:
        description: 'GitHub Action runner'
        required: false
        type: string
        default: "ubuntu-latest"

jobs:
  run-iris:
    runs-on: ${{ github.event_name == 'workflow_dispatch' && inputs.runner_label || 'ubuntu-latest' }}
    steps:
      - name: Run IRIS Analysis
        uses: ./.github/actions/run-iris
        with:
          source_project_key: "SonarSource_your-project-name"
          source_organization: "your-organization"
          destination_project_key: "SonarSource_your-project-name"
          destination_organization: "your-organization"
          github_environment: ${{ github.event_name == 'workflow_dispatch' && inputs.github_environment || 'Scheduled' }}
```

## Inputs

### Required Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `source_project_key` | Source project key | Yes | - |
| `source_organization` | Source organization name | Yes | - |
| `destination_project_key` | Destination project key | Yes | - |
| `destination_organization` | Destination organization name | Yes | - |

### Optional Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github_environment` | GitHub Environment | No | `ManualDispatch` |
| `sonar_sqc_eu_url` | SonarCloud EU URL | No | `https://sonarcloud.io` |
| `sonar_sqc_us_url` | SonarCloud US URL | No | `https://sonarqube.us` |
| `sonar_next_url` | SonarQube Next URL | No | `https://next.sonarqube.com/sonarqube` |

## Prerequisites

### Required Permissions

The workflow using this action must have the following permissions:

```yaml
permissions:
  id-token: write    # Required for vault authentication
  contents: read     # Required for checkout
```

### Required Secrets

This action requires access to SonarSource vault with the following secrets:

- `development/kv/data/iris` - IRIS tokens for different instances
- `development/artifactory/token/{REPO_OWNER_NAME_DASH}-private-reader` - Artifactory credentials
- `development/kv/data/repox` - Artifactory URL
