# Contribute

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

Add a new spec file in the `spec` directory for the action. Use the existing tests as examples for writing your own tests.

Only create Action test workflow when it completes the ShellSpec tests, and does not require complex setup or external dependencies.
The actions are used in the dummy repositories, so they are tested in the CI/CD environment.

### Test Guidelines

Focus on targeting 100% code coverage for the scripts in the action.

Do not test the underlying commands or tools used in the scripts, such as `git`, `curl`, etc. Instead, mock their outputs if necessary.

Do not test the missing parameters in the Shell scripts: this is handled by
the [Bash parameter expansion](https://xtranet-sonarsource.atlassian.net/wiki/spaces/Platform/pages/2683109459/Shell+Script+-+Cirrus+CI#Validate-Values-and-Report-Errors).

Additional tests will be added to cover specific scenarios or edge cases, when fixing bugs (test-driven development).
