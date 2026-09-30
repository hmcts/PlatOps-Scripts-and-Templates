#!/usr/bin/env bash
set -euo pipefail

readonly ZONE_QUERY="Resources | where type in~ ('microsoft.network/dnszones', 'microsoft.network/privatednszones') | project id, subscriptionId, resourceGroup, name, type | order by id asc"

usage() {
  printf 'Usage: %s SEARCH_STRING\n' "${0##*/}"
  printf 'Search public and private Azure DNS record names and values (case-insensitive).\n'
}

log() {
  printf '%s\n' "${*}" >&2
}

print_matches() {
  local subscription="${1}" zone_kind="${2}" resource_group="${3}" zone_name="${4}" needle="${5}"
  jq -r --arg subscription "${subscription}" --arg kind "${zone_kind}" \
    --arg resource_group "${resource_group}" --arg zone "${zone_name}" --arg needle "${needle}" '
    .[] |
    ([.aRecords[]?, .aaaaRecords[]?, .caaRecords[]?, .cnameRecord?,
      .mxRecords[]?, .nsRecords[]?, .ptrRecords[]?, .soaRecord?,
      .srvRecords[]?, .txtRecords[]?, .targetResource?] |
      [.[] | .. | strings] | unique | join("; ")) as $values |
    (if .name == "@" then $zone else "\(.name).\($zone)" end) as $fqdn |
    select(($fqdn + " " + $values | ascii_downcase | contains($needle))) |
    [$subscription, $kind, $resource_group, $zone, $fqdn,
      (.type | split("/") | last), $values] | @tsv
  '
}

main() {
  local dependency graph_json skip_token='' zone_rows subscription resource_group zone_name resource_type zone_kind records_json
  if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
    usage
    return 0
  fi
  if [[ "${#}" -ne 1 || -z "${1}" ]]; then
    usage >&2
    return 2
  fi
  for dependency in az jq; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
      log "Missing dependency: ${dependency}"
      return 1
    fi
  done

  printf 'SubscriptionId\tZoneKind\tResourceGroup\tZone\tRecord\tType\tValues\n'
  while :; do
    if [[ -n "${skip_token}" ]]; then
      graph_json="$(az graph query -q "${ZONE_QUERY}" --first 1000 --skip-token "${skip_token}" --output json)" || return 1
    else
      graph_json="$(az graph query -q "${ZONE_QUERY}" --first 1000 --output json)" || return 1
    fi
    zone_rows="$(jq -r '.data[] | [.subscriptionId, .resourceGroup, .name, .type] | @tsv' <<< "${graph_json}")" || return 1

    if [[ -n "${zone_rows}" ]]; then
      while IFS=$'\t' read -r subscription resource_group zone_name resource_type; do
        if [[ "${resource_type,,}" == 'microsoft.network/dnszones' ]]; then
          zone_kind=dns
        else
          zone_kind=private-dns
        fi
        records_json="$(az network "${zone_kind}" record-set list \
          --subscription "${subscription}" --resource-group "${resource_group}" \
          --zone-name "${zone_name}" --output json)" || return 1
        print_matches "${subscription}" "${zone_kind}" "${resource_group}" "${zone_name}" "${1,,}" \
          <<< "${records_json}" || return 1
      done <<< "${zone_rows}"
    fi

    skip_token="$(jq -r '.skipToken // empty' <<< "${graph_json}")" || return 1
    if [[ -z "${skip_token}" ]]; then
      if jq -e '.resultTruncated == true or .resultTruncated == "true"' <<< "${graph_json}" >/dev/null; then
        log 'Resource Graph truncated the zone list without a continuation token.'
        return 1
      fi
      break
    fi
  done
}

main "${@}"
