#!/usr/bin/env bash
set -euo pipefail

# Report Platform Operations chart dependency adoption from hmcts-charts.

usage() {
  cat <<'EOF'
Usage:
  ./chart-adoption.sh (--charts-dir <path> | --clone) \
    [--nagger <nagger-versions.yaml>] [--charts <chart:version,...>] \
    [--format table|md|csv] [--out <file>] [--check-latest]

Options:
  --charts-dir <path>  Existing hmcts-charts checkout.
  --clone              Shallow-clone hmcts/hmcts-charts for this run.
  --nagger <path>      Seed targets from the helm section of nagger-versions.yaml.
  --charts <list>      Add or override targets. Accepts chart-java:x.y.z or java:x.y.z.
                       Square brackets around the comma-separated list are optional.
  --format <format>    Output format: table (default), md, or csv.
  --out <file>         Write the report to a file instead of standard output.
  --check-latest       Query stable GitHub releases and show the latest version per target.
  -h, --help           Show this help.

Notes:
  - The scan is read-only and recursively includes every Chart.yaml under stable/.
  - A dependency absent from a chart is reported as n/a.
  - OK means the dependency version is at or above the supplied target.
  - BELOW includes prerelease dependencies and versions lower than the target.
  - UNKNOWN means a dependency does not use a supported numeric version expression.
  - Targets must be explicit. Latest releases are never used as compliance targets.
  - Explicit --charts values override --nagger values. The last duplicate value wins.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

latest_release() {
  local chart_name="$1"
  local response
  local -a curl_args
  curl_args=(
    --fail
    --silent
    --show-error
    --location
    --retry 3
    --connect-timeout 10
    --max-time 30
  )

  if [[ -n "${GH_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer ${GH_TOKEN}")
  fi

  response="$(curl "${curl_args[@]}" "https://api.github.com/repos/hmcts/chart-${chart_name}/releases?per_page=100")"
  jq -r '
    .[]
    | select(.draft == false and .prerelease == false)
    | .tag_name
    | sub("^[vV]"; "")
    | select(test("^[0-9]+(\\.[0-9]+){2,3}$"))
  ' <<<"$response" | sort -V | tail -1
}

CHARTS_DIR=""
CLONE_CHARTS="false"
NAGGER_FILE=""
CHART_SPECS=""
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
CHECK_LATEST="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --charts-dir)
      [[ $# -ge 2 ]] || { echo "--charts-dir requires a value" >&2; exit 1; }
      CHARTS_DIR="$2"
      shift 2
      ;;
    --clone)
      CLONE_CHARTS="true"
      shift
      ;;
    --nagger)
      [[ $# -ge 2 ]] || { echo "--nagger requires a value" >&2; exit 1; }
      NAGGER_FILE="$2"
      shift 2
      ;;
    --charts)
      [[ $# -ge 2 ]] || { echo "--charts requires a value" >&2; exit 1; }
      CHART_SPECS="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || { echo "--format requires a value" >&2; exit 1; }
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || { echo "--out requires a value" >&2; exit 1; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --check-latest)
      CHECK_LATEST="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd yq
require_cmd jq
require_cmd awk
require_cmd sed
if [[ "$CHECK_LATEST" == "true" ]]; then
  require_cmd curl
fi
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
  require_cmd column
fi

if [[ "$OUTPUT_FORMAT" != "table" && "$OUTPUT_FORMAT" != "md" && "$OUTPUT_FORMAT" != "csv" ]]; then
  echo "Unsupported format: $OUTPUT_FORMAT" >&2
  exit 1
fi

if [[ -n "$CHARTS_DIR" && "$CLONE_CHARTS" == "true" ]]; then
  echo "Use either --charts-dir or --clone, not both" >&2
  exit 1
fi

if [[ -z "$CHARTS_DIR" && "$CLONE_CHARTS" != "true" ]]; then
  echo "One of --charts-dir or --clone is required" >&2
  exit 1
fi

if [[ -z "$NAGGER_FILE" && -z "$CHART_SPECS" ]]; then
  echo "At least one of --nagger or --charts is required" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chart-adoption.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "$CLONE_CHARTS" == "true" ]]; then
  require_cmd git
  CHARTS_DIR="$WORK_DIR/hmcts-charts"
  git clone --quiet --depth 1 https://github.com/hmcts/hmcts-charts.git "$CHARTS_DIR"
fi

CHARTS_DIR="$(cd "$CHARTS_DIR" 2>/dev/null && pwd)" || {
  echo "Charts directory does not exist: $CHARTS_DIR" >&2
  exit 1
}

if [[ ! -d "$CHARTS_DIR/stable" ]]; then
  echo "Expected an hmcts-charts stable directory at: $CHARTS_DIR/stable" >&2
  exit 1
fi

TARGETS_RAW="$WORK_DIR/targets-raw.tsv"
TARGETS_TSV="$WORK_DIR/targets.tsv"
TARGETS_JSON="$WORK_DIR/targets.jsonl"
INVENTORY_JSON="$WORK_DIR/inventory.jsonl"
REPORT_JSON="$WORK_DIR/report.json"
RENDERED_REPORT="$WORK_DIR/report.txt"
: >"$TARGETS_RAW"
: >"$INVENTORY_JSON"

if [[ -n "$NAGGER_FILE" ]]; then
  if [[ ! -f "$NAGGER_FILE" ]]; then
    echo "Nagger file does not exist: $NAGGER_FILE" >&2
    exit 1
  fi

  if ! nagger_document="$(yq e -o=json '.' "$NAGGER_FILE")"; then
    echo "Failed to parse nagger file: $NAGGER_FILE" >&2
    exit 1
  fi
  if ! jq -e '.helm | type == "object"' <<<"$nagger_document" >/dev/null; then
    echo "Nagger file has no helm mapping: $NAGGER_FILE" >&2
    exit 1
  fi

  jq -r '.helm | to_entries[] | [.key, (.value.version | tostring)] | @tsv' <<<"$nagger_document" \
    >>"$TARGETS_RAW"
fi

if [[ -n "$CHART_SPECS" ]]; then
  cleaned_specs="$(trim "$CHART_SPECS")"
  cleaned_specs="${cleaned_specs#[}"
  cleaned_specs="${cleaned_specs%]}"
  IFS=',' read -r -a specs <<<"$cleaned_specs"

  for spec in "${specs[@]}"; do
    spec="$(trim "$spec")"
    if [[ "$spec" != *:* ]]; then
      echo "Invalid chart target '$spec'. Expected chart-name:x.y.z" >&2
      exit 1
    fi

    chart_name="$(trim "${spec%%:*}")"
    target_version="$(trim "${spec#*:}")"
    chart_name="${chart_name#chart-}"
    target_version="${target_version#v}"
    target_version="${target_version#V}"

    if [[ ! "$chart_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      echo "Invalid chart name: $chart_name" >&2
      exit 1
    fi
    if [[ ! "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      echo "Invalid target version for chart-$chart_name: $target_version" >&2
      exit 1
    fi

    printf '%s\t%s\n' "$chart_name" "$target_version" >>"$TARGETS_RAW"
  done
fi

# Preserve declaration order while allowing explicit --charts values to override nagger values.
awk -F '\t' '
  !seen[$1]++ { order[++count] = $1 }
  { version[$1] = $2 }
  END {
    for (item = 1; item <= count; item++) {
      name = order[item]
      print name "\t" version[name]
    }
  }
' "$TARGETS_RAW" >"$TARGETS_TSV"

if [[ ! -s "$TARGETS_TSV" ]]; then
  echo "No chart targets were found" >&2
  exit 1
fi

: >"$TARGETS_JSON"
while IFS=$'\t' read -r chart_name target_version; do
  target_version="${target_version#v}"
  target_version="${target_version#V}"
  if [[ ! "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid target version for chart-$chart_name: $target_version" >&2
    exit 1
  fi

  latest_version=""
  if [[ "$CHECK_LATEST" == "true" ]]; then
    latest_version="$(latest_release "$chart_name")"
    if [[ -z "$latest_version" ]]; then
      echo "No stable release found for chart-$chart_name" >&2
      exit 1
    fi
  fi

  jq -cn \
    --arg name "$chart_name" \
    --arg target "$target_version" \
    --arg latest "$latest_version" \
    '{name: $name, target: $target, latest: (if $latest == "" then null else $latest end)}' \
    >>"$TARGETS_JSON"
done <"$TARGETS_TSV"

chart_count=0
while IFS= read -r -d '' chart_file; do
  relative_file="${chart_file#"$CHARTS_DIR/stable/"}"
  chart_path="${relative_file%/*}"
  if ! chart_document="$(yq e -o=json '.' "$chart_file")"; then
    echo "Failed to parse chart file: $chart_file" >&2
    exit 1
  fi
  chart_name="$(jq -r '.name // empty' <<<"$chart_document")"
  if [[ -z "$chart_name" ]]; then
    chart_name="$(basename "$chart_path")"
  fi

  jq -cn \
    --arg chart "$chart_name" \
    --arg path "$chart_path" \
    --argjson document "$chart_document" \
    '{
      chart: $chart,
      path: $path,
      dependencies: [
        ($document.dependencies // [])[]
        | {
            name: (.name | tostring),
            version: (.version | tostring),
            repository: ((.repository // "") | tostring)
          }
      ]
    }' >>"$INVENTORY_JSON"
  chart_count=$((chart_count + 1))
done < <(find "$CHARTS_DIR/stable" -type f \( -iname 'Chart.yaml' -o -iname 'Chart.yml' \) -print0)

if [[ "$chart_count" -eq 0 ]]; then
  echo "No Chart.yaml files found under: $CHARTS_DIR/stable" >&2
  exit 1
fi

jq -n \
  --slurpfile targets "$TARGETS_JSON" \
  --slurpfile charts "$INVENTORY_JSON" '
  def version_core:
    tostring
    | sub("^[~^vV[:space:]]+"; "")
    | split("-")[0];

  def version_parts:
    version_core as $version
    | if ($version | test("^[0-9]+(\\.[0-9]+){1,3}$")) then
        (($version | split(".") | map(tonumber)) + [0, 0, 0, 0])[:4]
      else
        null
      end;

  def compliance($current; $target):
    ($current | version_parts) as $current_parts
    | ($target | version_parts) as $target_parts
    | if $current_parts == null or $target_parts == null then
        "UNKNOWN"
      elif ($current | test("-(alpha|beta|rc)([.-]|$)"; "i")) then
        "BELOW"
      elif $current_parts >= $target_parts then
        "OK"
      else
        "BELOW"
      end;

  def is_hmcts_repository:
    tostring
    | test("^(@hmctspublic|oci://(hmctspublic|hmctsprod|hmctssbox)\\.azurecr\\.io/helm/?|https://hmctspublic\\.azurecr\\.io/helm/v1/repo/?)$");

  {
    targets: $targets,
    rows: (
      $charts
      | sort_by(.path)
      | map(
          . as $chart
          | {
              chart: $chart.chart,
              path: $chart.path,
              cells: [
                $targets[] as $target
                | ([
                    $chart.dependencies[]
                    | select(.name == $target.name)
                  ]) as $named_dependencies
                | ([$named_dependencies[] | select(.repository | is_hmcts_repository)]) as $hmcts_dependencies
                | ([$named_dependencies[] | select((.repository | is_hmcts_repository) | not)]) as $external_dependencies
                | ($hmcts_dependencies | first) as $dependency
                | if $dependency == null then
                    {
                      name: $target.name,
                      version: null,
                      repository: null,
                      external: ($external_dependencies | length),
                      status: "n/a",
                      display: "n/a"
                    }
                  else
                    (compliance($dependency.version; $target.target)) as $status
                    | {
                        name: $target.name,
                        version: $dependency.version,
                        repository: $dependency.repository,
                        external: ($external_dependencies | length),
                        status: $status,
                        display: ($dependency.version + " (" + $status + ")")
                      }
                  end
              ]
            }
        )
    )
  }
  | .summary = [
      .targets[] as $target
      | {
          name: $target.name,
          target: $target.target,
          latest: $target.latest,
          ok: ([.rows[].cells[] | select(.name == $target.name and .status == "OK")] | length),
          below: ([.rows[].cells[] | select(.name == $target.name and .status == "BELOW")] | length),
          unavailable: ([.rows[].cells[] | select(.name == $target.name and .status == "n/a")] | length),
          unknown: ([.rows[].cells[] | select(.name == $target.name and .status == "UNKNOWN")] | length),
          external: ([.rows[].cells[] | select(.name == $target.name) | .external] | add // 0)
        }
    ]
' >"$REPORT_JSON"

render_table() {
  {
    printf 'Chart\tTarget\tLatest\tOK\tBELOW\tn/a\tUNKNOWN\tEXTERNAL\n'
    jq -r '.summary[] | ["chart-" + .name, .target, (.latest // "not checked"), .ok, .below, .unavailable, .unknown, .external] | @tsv' "$REPORT_JSON"
  } | column -t -s $'\t'

  printf '\n'
  {
    jq -r '(["Chart name", "Chart path"] + [.targets[] | "chart-" + .name + " (>=" + .target + ")"]) | @tsv' "$REPORT_JSON"
    jq -r '.rows[] | ([.chart, .path] + [.cells[].display]) | @tsv' "$REPORT_JSON"
  } | column -t -s $'\t'
}

render_markdown() {
  jq -r '
    (["Chart", "Target", "Latest", "OK", "BELOW", "n/a", "UNKNOWN", "EXTERNAL"] | "| " + join(" | ") + " |"),
    (["---", "---", "---", "---:", "---:", "---:", "---:", "---:"] | "| " + join(" | ") + " |"),
    (.summary[] | ["chart-" + .name, .target, (.latest // "not checked"), (.ok | tostring), (.below | tostring), (.unavailable | tostring), (.unknown | tostring), (.external | tostring)] | "| " + join(" | ") + " |"),
    "",
    ((["Chart name", "Chart path"] + [.targets[] | "chart-" + .name + " (>=" + .target + ")"]) | "| " + join(" | ") + " |"),
    ((["---", "---"] + [.targets[] | "---"]) | "| " + join(" | ") + " |"),
    (.rows[] | ([.chart, .path] + [.cells[].display]) | "| " + join(" | ") + " |")
  ' "$REPORT_JSON"
}

render_csv() {
  jq -r '
    (["Chart name", "Chart path"] + [.targets[] | "chart-" + .name + " (>=" + .target + ")"] | @csv),
    (.rows[] | ([.chart, .path] + [.cells[].display]) | @csv)
  ' "$REPORT_JSON"
}

case "$OUTPUT_FORMAT" in
  table)
    render_table >"$RENDERED_REPORT"
    ;;
  md)
    render_markdown >"$RENDERED_REPORT"
    ;;
  csv)
    render_csv >"$RENDERED_REPORT"
    jq -r '.summary[] | "chart-\(.name): target=\(.target) latest=\(.latest // "not checked") OK=\(.ok) BELOW=\(.below) n/a=\(.unavailable) UNKNOWN=\(.unknown) EXTERNAL=\(.external)"' "$REPORT_JSON" >&2
    ;;
esac

if [[ -n "$OUTPUT_FILE" ]]; then
  cp "$RENDERED_REPORT" "$OUTPUT_FILE"
  echo "Report written to: $OUTPUT_FILE" >&2
else
  cat "$RENDERED_REPORT"
fi