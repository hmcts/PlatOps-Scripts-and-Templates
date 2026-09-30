#!/usr/bin/env bash
set -euo pipefail

readonly CLUSTER_QUERY="Resources | where type =~ 'microsoft.containerservice/managedclusters' | where name startswith 'cft-' or name startswith 'ss-' | project id, subscriptionId, resourceGroup, name | order by id asc"

usage() {
  printf 'Usage: %s [--dry-run | --help]\n' "${0##*/}"
  printf '%s\n' 'Discovers cft-* and ss-* AKS clusters across accessible subscriptions.'
  printf '%s\n' '--dry-run queries Azure but does not change kubeconfig.'
}

log() {
  printf '%s\n' "${*}" >&2
}

main() {
  local dry_run=false
  local dependency graph_json skip_token='' page_rows cluster_rows='' subscription resource_group cluster_name

  case "${1:-}" in
    --help|-h) usage; return 0 ;;
    --dry-run) dry_run=true ;;
    '') ;;
    *) usage >&2; return 2 ;;
  esac
  if [[ "${#}" -gt 1 ]]; then
    usage >&2
    return 2
  fi

  for dependency in az jq; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
      log "Missing dependency: ${dependency}. Run az login before using this script."
      return 1
    fi
  done
  if [[ "${dry_run}" == false ]] && ! command -v kubelogin >/dev/null 2>&1; then
    log 'kubelogin is required to convert the refreshed kubeconfig.'
    return 1
  fi

  while :; do
    if [[ -n "${skip_token}" ]]; then
      graph_json="$(az graph query -q "${CLUSTER_QUERY}" --first 1000 --skip-token "${skip_token}" --output json)" || return 1
    else
      graph_json="$(az graph query -q "${CLUSTER_QUERY}" --first 1000 --output json)" || return 1
    fi
    page_rows="$(jq -r '.data[] | select((.name | ascii_downcase | startswith("cft-")) or (.name | ascii_downcase | startswith("ss-"))) | [.subscriptionId, .resourceGroup, .name] | @tsv' <<< "${graph_json}")" || return 1
    if [[ -n "${page_rows}" ]]; then
      cluster_rows+="${page_rows}"$'\n'
    fi
    skip_token="$(jq -r '.skipToken // empty' <<< "${graph_json}")" || return 1
    if [[ -z "${skip_token}" ]]; then
      if jq -e '.resultTruncated == true or .resultTruncated == "true"' <<< "${graph_json}" >/dev/null; then
        log 'Resource Graph truncated the cluster list without a continuation token.'
        return 1
      fi
      break
    fi
  done

  if [[ -z "${cluster_rows}" ]]; then
    log 'No cft-* or ss-* AKS clusters found.'
    return 1
  fi

  while IFS=$'\t' read -r subscription resource_group cluster_name; do
    if [[ "${dry_run}" == true ]]; then
      printf 'DRY-RUN: Would run `az aks get-credentials --subscription %q --resource-group %q --name %q --overwrite-existing`\n' \
        "${subscription}" "${resource_group}" "${cluster_name}"
    else
      log "Refreshing ${cluster_name} (${subscription})"
      az aks get-credentials \
        --subscription "${subscription}" \
        --resource-group "${resource_group}" \
        --name "${cluster_name}" \
        --overwrite-existing
    fi
  done <<< "${cluster_rows%$'\n'}"

  if [[ "${dry_run}" == true ]]; then
    printf 'DRY-RUN: Would run `kubelogin convert-kubeconfig -l azurecli` ...\n'
  else
    log 'Converting kubeconfig to Azure CLI authentication'
    kubelogin convert-kubeconfig -l azurecli
  fi
}

main "${@}"
