# Helm Chart Adoption

Reports Platform Operations dependency versions for every chart under
`hmcts-charts/stable`, including nested and old charts.

## Requirements

- Bash, `yq` v4 and `jq`
- `column` for table output
- `git` with `--clone`
- `curl` with `--check-latest`

## Example

The versions below are illustrative. Use the approved published targets for adoption tracking.

```bash
./chart-adoption.sh \
  --charts-dir ../../hmcts-charts \
  --charts '[chart-java:6.1.0,chart-nodejs:3.3.0,chart-postgresql:1.1.2]' \
  --format csv \
  --out adoption.csv
```

Targets can instead come from `--nagger <nagger-versions.yaml>`. Explicit `--charts`
values override matching nagger values. Use `--clone` instead of `--charts-dir` for a
fresh checkout. Run `./chart-adoption.sh --help` for all options.

## Behavior

- `chart-` is removed from target names before matching `Chart.yaml` dependencies.
- Cells are `OK`, `BELOW`, `n/a`, or `UNKNOWN`. Prereleases are `BELOW`.
- Only HMCTS chart repositories count. Same-named external dependencies are excluded.
- Chart name and path are both shown so nested charts remain distinct.
- Table includes a summary. CSV writes its summary to standard error.
- `--check-latest` is informational and never changes supplied targets. Set `GH_TOKEN`
  to avoid GitHub API rate limits.

Run tests with `./test-chart-adoption.sh`.
