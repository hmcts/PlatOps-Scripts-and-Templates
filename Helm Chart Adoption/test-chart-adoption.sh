#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/chart-adoption.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chart-adoption-test.XXXXXX")"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

assert_line() {
  local expected="$1"
  local file="$2"

  if ! grep -Fqx "$expected" "$file"; then
    echo "Expected line not found in $file:" >&2
    echo "$expected" >&2
    exit 1
  fi
}

mkdir -p \
  "$WORK_DIR/hmcts-charts/stable/service-a" \
  "$WORK_DIR/hmcts-charts/stable/nested/service-b/prod" \
  "$WORK_DIR/hmcts-charts/stable/no-dependencies"

cat >"$WORK_DIR/hmcts-charts/stable/service-a/Chart.yaml" <<'EOF'
apiVersion: v2
name: service-a
version: 1.0.0
dependencies:
  - name: java
    version: ~6.1.0
    repository: oci://hmctspublic.azurecr.io/helm
  - name: nodejs
    version: 3.2.0
    repository: '@hmctspublic'
  - name: servicebus
    version: 1.2.2-beta
    repository: oci://hmctsprod.azurecr.io/helm
  - name: ccd
    version: ${CCD_VERSION}
    repository: oci://hmctspublic.azurecr.io/helm
  - name: postgresql
    version: 18.8.12
    repository: oci://registry-1.docker.io/bitnamicharts
  # - name: postgresql
  #   version: 1.1.2
EOF

cat >"$WORK_DIR/hmcts-charts/stable/nested/service-b/prod/Chart.yml" <<'EOF'
apiVersion: v2
name: service-b-prod
version: 1.0.0
dependencies:
    - name: function
      version: v2.7.0
      repository: 'https://hmctspublic.azurecr.io/helm/v1/repo/'
    - name: postgresql
      version: 1.1.2
      repository: oci://hmctssbox.azurecr.io/helm
EOF

cat >"$WORK_DIR/hmcts-charts/stable/no-dependencies/Chart.yaml" <<'EOF'
apiVersion: v2
name: no-dependencies
version: 1.0.0
EOF

cat >"$WORK_DIR/nagger-versions.yaml" <<'EOF'
helm:
  java:
    version: "6.0.0"
  nodejs:
    version: "3.3.0"
  servicebus:
    version: "1.2.2"
  function:
    version: "2.7.0"
  ccd:
    version: "9.2.3"
EOF

"$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --nagger "$WORK_DIR/nagger-versions.yaml" \
  --charts '[chart-java:6.1.0,chart-postgresql:1.1.2]' \
  --format csv \
  --out "$WORK_DIR/report.csv" \
  2>"$WORK_DIR/summary.txt"

assert_line '"Chart name","Chart path","chart-java (>=6.1.0)","chart-nodejs (>=3.3.0)","chart-servicebus (>=1.2.2)","chart-function (>=2.7.0)","chart-ccd (>=9.2.3)","chart-postgresql (>=1.1.2)"' "$WORK_DIR/report.csv"
assert_line "\"service-a\",\"service-a\",\"~6.1.0 (OK)\",\"3.2.0 (BELOW)\",\"1.2.2-beta (BELOW)\",\"n/a\",\"\${CCD_VERSION} (UNKNOWN)\",\"n/a\"" "$WORK_DIR/report.csv"
assert_line '"service-b-prod","nested/service-b/prod","n/a","n/a","n/a","v2.7.0 (OK)","n/a","1.1.2 (OK)"' "$WORK_DIR/report.csv"
assert_line '"no-dependencies","no-dependencies","n/a","n/a","n/a","n/a","n/a","n/a"' "$WORK_DIR/report.csv"
assert_line 'chart-java: target=6.1.0 latest=not checked OK=1 BELOW=0 n/a=2 UNKNOWN=0 EXTERNAL=0' "$WORK_DIR/summary.txt"
assert_line 'chart-ccd: target=9.2.3 latest=not checked OK=0 BELOW=0 n/a=2 UNKNOWN=1 EXTERNAL=0' "$WORK_DIR/summary.txt"
assert_line 'chart-postgresql: target=1.1.2 latest=not checked OK=1 BELOW=0 n/a=2 UNKNOWN=0 EXTERNAL=1' "$WORK_DIR/summary.txt"

mkdir -p "$WORK_DIR/bin"
cat >"$WORK_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"tag_name":"v6.0.0","draft":false,"prerelease":false},
  {"tag_name":"6.1.0-beta","draft":false,"prerelease":true},
  {"tag_name":"6.1.0","draft":false,"prerelease":false},
  {"tag_name":"7.0.0","draft":true,"prerelease":false}
]
JSON
EOF
chmod +x "$WORK_DIR/bin/curl"

PATH="$WORK_DIR/bin:$PATH" "$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --charts 'chart-java:6.1.0' \
  --check-latest \
  --format csv \
  --out "$WORK_DIR/latest.csv" \
  2>"$WORK_DIR/latest-summary.txt"

assert_line 'chart-java: target=6.1.0 latest=6.1.0 OK=1 BELOW=0 n/a=2 UNKNOWN=0 EXTERNAL=0' "$WORK_DIR/latest-summary.txt"

if "$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --charts 'chart-java:6.1.0' \
  --format md \
  >"$WORK_DIR/invalid.out" \
  2>"$WORK_DIR/invalid.err"; then
  echo "Expected Markdown output format to fail" >&2
  exit 1
fi

assert_line 'Unsupported format: md' "$WORK_DIR/invalid.err"

if "$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --charts 'chart-java:not-a-version' \
  >"$WORK_DIR/invalid.out" \
  2>"$WORK_DIR/invalid.err"; then
  echo "Expected malformed target version to fail" >&2
  exit 1
fi

assert_line 'Invalid target version for chart-java: not-a-version' "$WORK_DIR/invalid.err"

cat >"$WORK_DIR/invalid-nagger.yaml" <<'EOF'
helm:
  java:
    version: latest
EOF

if "$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --nagger "$WORK_DIR/invalid-nagger.yaml" \
  >"$WORK_DIR/invalid.out" \
  2>"$WORK_DIR/invalid.err"; then
  echo "Expected malformed nagger target version to fail" >&2
  exit 1
fi

assert_line 'Invalid target version for chart-java: latest' "$WORK_DIR/invalid.err"

cat >"$WORK_DIR/no-helm.yaml" <<'EOF'
docker:
  java:
    version: 6.1.0
EOF

if "$SCANNER" \
  --charts-dir "$WORK_DIR/hmcts-charts" \
  --nagger "$WORK_DIR/no-helm.yaml" \
  --format csv \
  >"$WORK_DIR/invalid.out" \
  2>"$WORK_DIR/invalid.err"; then
  echo "Expected nagger file without helm mapping to fail" >&2
  exit 1
fi

assert_line "Nagger file has no helm mapping: $WORK_DIR/no-helm.yaml" "$WORK_DIR/invalid.err"

mkdir -p "$WORK_DIR/malformed-charts/stable/broken"
cat >"$WORK_DIR/malformed-charts/stable/broken/Chart.yaml" <<'EOF'
name: broken
dependencies:
  - name: java
    version: [
EOF

if "$SCANNER" \
  --charts-dir "$WORK_DIR/malformed-charts" \
  --charts 'chart-java:6.1.0' \
  --format csv \
  >"$WORK_DIR/invalid.out" \
  2>"$WORK_DIR/invalid.err"; then
  echo "Expected malformed chart YAML to fail" >&2
  exit 1
fi

assert_line "Failed to parse chart file: $WORK_DIR/malformed-charts/stable/broken/Chart.yaml" "$WORK_DIR/invalid.err"

echo "All chart adoption tests passed"
