# Runner hooks for CI Metrics

This directory is **not** a GitHub Action. It holds a runner-side shell hook (`job-completed.sh`) used by self-hosted GitHub runners
to collect resource-usage metrics after each job.

| Artifact        | Path                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------ |
| Post-job script | [`job-completed.sh`](job-completed.sh)                                                           |
| Raw URL         | `https://raw.githubusercontent.com/SonarSource/ci-github-actions/v1/ci-metrics/job-completed.sh` |

The hook collects cgroup v2 and network totals, writes `${CI_METRICS_DIR}/job-metrics.json` (default `/tmp/ci-metrics`), and appends a
`## CI Metrics` table to `$GITHUB_STEP_SUMMARY`. It is fail-open (errors exit 0).

## How runners invoke the hooks

See [CI Metrics and Runner Hooks](https://xtranet-sonarsource.atlassian.net/wiki/x/BIDiNgE) for more details.

## Configuration

Collection can be disabled by setting `CI_METRICS_ENABLED=false` in the job/action environment.
