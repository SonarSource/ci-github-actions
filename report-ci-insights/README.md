# Report CI Insights

Aggregate per-job CI resource metrics from the current workflow run and post a sticky pull-request comment summarising them.

## Usage

Add a dedicated reporting job that runs after all the jobs you want covered. It must run on every pull-request outcome (`if: always()`)
so the comment is posted even when an earlier job fails:

```yaml
report-ci-insights:
  needs: [build, test, lint]  # list every job whose metrics you want reported
  if: always() && github.event_name == 'pull_request'
  runs-on: sonar-xs
  permissions:
    actions: read           # read sibling job logs via the Actions API
    pull-requests: write    # post / update the sticky comment
  steps:
    - uses: SonarSource/ci-github-actions/report-ci-insights@v1
```

## How it works

1. Lists the run's jobs via the GitHub Actions API and downloads each completed sibling's log.
2. Recovers the metrics JSON that the runner-side CI-metrics hook emitted into the log (a sentinel-wrapped block), skipping the report
   job itself and any job without a metrics block.
3. Renders a headline of run totals (CPU-seconds, peak memory, network, cache) plus foldable per-job and cache breakdown tables.
4. Posts a sticky comment matched by a hidden marker — re-runs update the same comment instead of duplicating it. If no sibling produced
   metrics, nothing is posted.

## Scope and behaviour

- Metrics are produced only on **Linux ARC and WarpBuild runners** where the [CI Metrics runner hook](../ci-metrics/README.md) runs;
  jobs on other runners simply contribute no data.
- **Fail-open**: any error is logged as a warning and the step exits `0`, so this action never fails your workflow.
- Runs only for `pull_request` events — there is no PR to comment on otherwise.
