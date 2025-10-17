# Contribute

## 📋 Standardization & Requirements

All actions in this repository follow standardized patterns for consistency and maintainability. Key standardizations include:

### Standardized Environment Variables

All actions use consistent environment variables with safe fallback patterns (`|| ''` instead of `false` or `null`):

- `PULL_REQUEST`: Pull request number or empty string
- `PULL_REQUEST_SHA`: Pull request base SHA or empty string
- `DEFAULT_BRANCH`: Repository default branch name

### Event Detection

Actions use `$GITHUB_EVENT_NAME` environment variable for reliable pull request detection instead of legacy string comparison patterns.

## Unit testing of Bash scripts

The Bash scripts used by the GitHub actions are tested with the [ShellSpec framework](https://github.com/shellspec/shellspec)

### Prerequisites

Use `mise` to install the dependencies:

```bash
mise install
```

#### kcov

[kcov](https://github.com/SimonKagstrom/kcov) must be manually installed to generate code coverage reports.

```bash
sudo apt-get install kcov
```

## Run the tests

```bash
./run_shell_tests.sh
```

Example of output:

```bash
========================
Test ci-common-scripts
========================
Running: /usr/bin/bash [bash 5.1.16(1)-release]
............................

Finished in 1.87 seconds (user 0.95 seconds, sys 0.96 seconds)
28 examples, 0 failures

Code covered: 90.09%, Executed lines: 100, Instrumented lines: 111

```

The coverage report is available here: `coverage/index.html`

> Note: you can also run directly a `.spec` file in order to run only subset of the tests.

### Debugging

Use `Dump` in the spec file to print the variables and their values during the test execution.

Use ShellSpec options like `-x`, `-X` to run the tests in debug mode.

Use ShellSpec options like `-q` (`--quick`), `-n` (`--next-failure`)... to iterate on the tests and debug them.

```shell
# List all examples in the spec files, with IDs
shellspec --kcov --list examples

# List all examples in the spec files, with line numbers
shellspec --kcov --list examples:lineno
```

## Project structure

```text
├── .github
│        └── workflows
│            └── test-<action_name>.yml # Action test workflow
├── <action_name>                       # GitHub action directory
│         ├── action.yml
│         └── *.sh                      # Shell scripts to be tested
├── .shellspec                          # ShellSpec configuration file
├── run_shell_tests.sh
└── spec                                # ShellSpec unit tests
```

## Add New Action and Tests

To add a new GitHub action, create a new directory under the root of the repository with the name of the action.
Inside this directory, create an `action.yml` file that defines the action and any necessary scripts.

Add a section in the README.md file to document the new action, including its usage and parameters.

Add the action folder to the `.shellspec` configuration file to include it in the tests.

Also add the action to the `sonar-project.properties` file to include its coverage in the SonarQube analysis.

Add a new spec file in the `spec` directory for the action. Use the existing tests as examples for writing your own tests.

Only create an Action test workflow when it completes the ShellSpec tests, and does not require complex setup or external dependencies.
The actions are used in the dummy repositories, so they are tested for real in the CI/CD environment.

### Test Guidelines

Focus on targeting 100% code coverage for the scripts in the action.

Do not test the underlying commands or tools used in the scripts, such as `git`, `curl`, etc. Instead, mock their outputs if necessary.

Do not test the missing parameters in the Shell scripts: this is handled by
the [Bash parameter expansion](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/2683109459/Shell+Script+-+Cirrus+CI#Validate-Values-and-Report-Errors).

Additional tests will be added to cover specific scenarios or edge cases, when fixing bugs (test-driven development).

## Step Formatting

```yaml
    - name: Add a name to the step ONLY IF RELEVANT
      uses: ...
      if: ...
      id: underscore_id_only_if_needed
```

Do not name obvious steps, for instance: checkout, vault, etc. But name a step when it deserves a description.

Set an ID only if it is used.

## Referring Local Actions

When using local actions in an action, some fixes are necessary to ensure that the action works correctly both in the standard usage and in
a container (see [BUILD-9094](https://sonarsource.atlassian.net/browse/BUILD-9094)).

### Symlinks to Local Actions And Host Paths Variables

Example of action `build-xyz` calling local action `config-xyz`:

```yaml
runs:
  using: composite
  steps:
    - name: Set local action paths
      id: set-path
      shell: bash
      run: |
        echo "::group::Fix for using local actions"
        echo "GITHUB_ACTION_PATH=$GITHUB_ACTION_PATH"                           # For debugging purposes
        echo "github.action_path=${{ github.action_path }}"                     # For debugging purposes
        ACTION_PATH_BUILD_XYZ="${{ github.action_path }}"                       # For local usage instead of GITHUB_ACTION_PATH
        echo "ACTION_PATH_BUILD_XYZ=$ACTION_PATH_BUILD_XYZ"                     # For debugging purposes
        echo "ACTION_PATH_BUILD_XYZ=$ACTION_PATH_BUILD_XYZ" >> "$GITHUB_ENV"    # For local usage instead of GITHUB_ACTION_PATH
        host_actions_root="$(dirname "$ACTION_PATH_BUILD_XYZ")"                 # Effective path to the local actions checkout on the host
        echo "host_actions_root=$host_actions_root" >> "$GITHUB_OUTPUT"

        mkdir -p ".actions"
        ln -sf "$host_actions_root/config-xyz" .actions/config-xyz              # For local reference
        ln -sf "$host_actions_root/shared" .actions/shared                      # For use in the Shell scripts
        ls -la .actions/*                                                       # For debugging purposes
        echo "::endgroup::"

    - uses: ./.actions/config-xyz                                               # Local action reference
      with:
        host-actions-root: ${{ steps.set-path.outputs.host_actions_root }}      # Only needed if the child action will use local references

    - shell: bash
      run: $ACTION_PATH_BUILD_XYZ/build.sh                                      # Use ACTION_PATH_BUILD_XYZ instead of GITHUB_ACTION_PATH
```

```shell
#!/bin/bash
# Example build.sh loading the common functions

set -euo pipefail

# shellcheck source=SCRIPTDIR/../shared/common-functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../shared/common-functions.sh"
```

### Child Action With Local References

In the case of a child action that also uses local references, `host-actions-root` input and similar fixes are necessary.

```yaml
inputs:
  host-actions-root:
    description: Path to the actions folder on the host (used when called from another local action)
    default: ''

runs:
  using: composite
  steps:
    - name: Set local action paths
      id: set-path
      shell: bash
      run: |
        echo "::group::Fix for using local actions"
        echo "GITHUB_ACTION_PATH=$GITHUB_ACTION_PATH"
        echo "github.action_path=${{ github.action_path }}"
        ACTION_PATH_CONFIG_XYZ="${{ github.action_path }}"
        host_actions_root="${{ inputs.host-actions-root }}"
        if [ -z "$host_actions_root" ]; then
          host_actions_root="$(dirname "$ACTION_PATH_CONFIG_XYZ")"
        else
          ACTION_PATH_CONFIG_XYZ="$host_actions_root/config-xyz"
        fi
        echo "ACTION_PATH_CONFIG_XYZ=$ACTION_PATH_CONFIG_XYZ"
        echo "ACTION_PATH_CONFIG_XYZ=$ACTION_PATH_CONFIG_XYZ" >> "$GITHUB_ENV"
        echo "host_actions_root=$host_actions_root" >> "$GITHUB_OUTPUT"

        mkdir -p ".actions"
        ln -sf "$host_actions_root/another-action" .actions/another-action
        ln -sf "$host_actions_root/shared" .actions/shared
        ls -la .actions/*
        echo "::endgroup::"

    - uses: ./.actions/another-action

    - shell: bash
      run: $ACTION_PATH_CONFIG_XYZ/config.sh
```

## Documentation for AI tools

This repository includes a comprehensive migration guide at [cirrus-github-migration.md](.cursor/cirrus-github-migration.md) that
documents the process of migrating Cirrus CI pipelines to GitHub Actions. This guide is accessible to everyone in the company
using Cursor through the `@Doc` command. The purpose of the document is to provide a context to Cursor and similar AI tools
to aid with migration

### Development Workflow with AI

When working on this repository or migrating eng-xp repositories, follow these best practices to use AI and keep the doc up-to-date.

1. **Multi-repository setup**: If working on a different repository, add the `ci-github-actions` repository to your workspace
   via `File → Add Folder to Workspace` in Cursor to access the documentation directly.

2. **Reference documentation**: Directly attach the migration guide to your AI chat conversations rather than using the `@Doc` syntax.

3. **Keep documentation current**: After completing your work, ask the AI to review and update the migration guide based on
   any new patterns, edge cases, or improvements discovered during development. Include these documentation updates in your
   pull request to maintain accuracy for future migrations.
