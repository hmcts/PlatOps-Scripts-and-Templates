# Helm Chart Adoption

`chart-adoption.sh` reports the Platform Operations chart dependencies used by every
chart under `hmcts-charts/stable`.

The report contains one row per chart file and one column per requested dependency.
Each cell contains the current dependency version and one of these states:

- `OK`: the version meets or exceeds the target
- `BELOW`: the version is below the target or is a prerelease
- `n/a`: the chart does not use that HMCTS dependency and it does not affect compliance
- `UNKNOWN`: the version does not reduce to two to four numeric components
- `EXTERNAL`: summary-only count of same-named dependencies from non-HMCTS repositories

## Requirements

- Bash
- `yq` v4
- `jq`
- `git` when using `--clone`
- `curl` when using `--check-latest`
- `column` when using the default table format

## Usage

Scan an existing `hmcts-charts` checkout with explicit target versions. The versions
below are an inventory example using the current nagger baseline. Replace them with the
approved published targets before creating an adoption tracker:

```bash
./chart-adoption.sh \
  --charts-dir ../../hmcts-charts \
  --charts '[chart-java:5.3.0,chart-nodejs:3.2.0,chart-servicebus:1.1.0,chart-job:2.2.0,chart-function:2.6.0,chart-blobstorage:2.1.0,chart-postgresql:1.1.2]'
```

Seed targets from `cnp-deprecation-map`, add PostgreSQL, and produce Jira-ready
Markdown:

```bash
./chart-adoption.sh \
  --charts-dir ../../hmcts-charts \
  --nagger ../../cnp-deprecation-map/nagger-versions.yaml \
  --charts 'chart-postgresql:1.1.2' \
  --format md \
  --out adoption.md
```

Use a fresh shallow clone and include the newest stable GitHub release beside each
configured target:

```bash
./chart-adoption.sh \
  --clone \
  --charts '[chart-java:6.1.0,chart-nodejs:3.3.0]' \
  --check-latest
```

Set `GH_TOKEN` when using `--check-latest` frequently to avoid unauthenticated GitHub
API rate limits.

Run `./chart-adoption.sh --help` for all options.

## Tests

Run the fixture suite locally after changing the scanner:

```bash
./test-chart-adoption.sh
```

The tests cover nested charts, `Chart.yaml` and `Chart.yml`, commented and external
dependencies, version prefixes, prereleases, unknown versions, target overrides, stable
release selection, empty dependency lists, Markdown and CSV output, and invalid input.

## Target versions

Targets are always supplied explicitly with `--charts`, read from the `helm` section
of `nagger-versions.yaml`, or both. Explicit `--charts` values override matching nagger
values.

When a target appears more than once, the last value wins. This lets an explicit
`--charts` value override one loaded from `--nagger`.

`--check-latest` is informational. It never changes a compliance target because the
latest published release may not be the approved Helm v4 validated release.

The scanner strips the `chart-` prefix from target names, so `chart-java:6.1.0` is
matched to a dependency named `java` in `Chart.yaml`.

Only dependencies from HMCTS chart repositories are compared. Supported sources are the
`@hmctspublic` alias, the legacy `hmctspublic` Helm repository, and the `hmctspublic`,
`hmctsprod`, and `hmctssbox` OCI Helm repositories. A same-named dependency from another
source, such as Bitnami PostgreSQL, is excluded and counted under `EXTERNAL` in the summary.

Prerelease dependencies are always `BELOW` an approved stable target. This is intentionally
stricter than the current Jenkins helper, which drops `-alpha` and `-beta` versions before
comparison and therefore does not warn for them.

## Output

The default `table` and `md` formats include a summary followed by the full matrix.
The `csv` format writes only the matrix so it remains suitable for import, while its
summary is written to standard error.

A full local scan of the current 450-plus chart inventory normally takes between 30
and 90 seconds, depending on the machine and filesystem.

The matrix includes both the name declared in `Chart.yaml` and the path below `stable/`.
This keeps environment-specific charts such as `vh-video-api/prod` distinct while still
reporting the actual chart name requested by the tracking ticket.
