#!/usr/bin/env bash
set -euo pipefail

# Add one subscription|resource-group|cluster-name entry per AKS cluster.
CLUSTERS=(
  '1497c3d7-ab6d-4bb7-8a10-b51d03189ee3|cft-ptlsbox-00-rg|cft-ptlsbox-00-aks'
  '1baf5470-1c3e-40d3-a6f7-74bfbce4b348|cft-ptl-00-rg|cft-ptl-00-aks'
  '3eec5bde-7feb-4566-bfb6-805df6e10b90|ss-test-00-rg|ss-test-00-aks'
  '3eec5bde-7feb-4566-bfb6-805df6e10b90|ss-test-01-rg|ss-test-01-aks'
  '5ca62022-6aa2-4cee-aaa7-e7536c8d566c|ss-prod-00-rg|ss-prod-00-aks'
  '5ca62022-6aa2-4cee-aaa7-e7536c8d566c|ss-prod-01-rg|ss-prod-01-aks'
  '62864d44-5da9-4ae9-89e7-0cf33942fa09|cft-ithc-01-rg|cft-ithc-01-aks'
  '64b1c6d6-1481-44ad-b620-d8fe26a2c768|ss-ptlsbox-00-rg|ss-ptlsbox-00-aks'
  '6c4d2513-a873-41b4-afdd-b05a33206631|ss-ptl-00-rg|ss-ptl-00-aks'
  '74dacd4f-a248-45bb-a2f0-af700dc4cf68|ss-stg-01-rg|ss-stg-01-aks'
  '74dacd4f-a248-45bb-a2f0-af700dc4cf68|ss-stg-00-rg|ss-stg-00-aks'
  '867a878b-cb68-4de5-9741-361ac9e178b6|ss-dev-00-rg|ss-dev-00-aks'
  '8a07fdcd-6abd-48b3-ad88-ff737a4b9e3c|cft-perftest-00-rg|cft-perftest-00-aks'
  '8a07fdcd-6abd-48b3-ad88-ff737a4b9e3c|cft-perftest-01-rg|cft-perftest-01-aks'
  '8b6ea922-0862-443e-af15-6056e1c9b9a4|cft-preview-00-rg|cft-preview-00-aks'
  '8cbc6f36-7c56-4963-9d36-739db5d00b27|cft-prod-00-rg|cft-prod-00-aks'
  '8cbc6f36-7c56-4963-9d36-739db5d00b27|cft-prod-01-rg|cft-prod-01-aks'
  '96c274ce-846d-4e48-89a7-d528432298a7|cft-aat-01-rg|cft-aat-01-aks'
  '96c274ce-846d-4e48-89a7-d528432298a7|cft-aat-00-rg|cft-aat-00-aks'
  'a8140a9e-f1b0-481f-a4de-09e2ee23f7ab|ss-sbox-00-rg|ss-sbox-00-aks'
  'a8140a9e-f1b0-481f-a4de-09e2ee23f7ab|ss-sbox-01-rg|ss-sbox-01-aks'
  'b72ab7b7-723f-4b18-b6f6-03b0f2c6a1bb|cft-sbox-01-rg|cft-sbox-01-aks'
  'b72ab7b7-723f-4b18-b6f6-03b0f2c6a1bb|cft-sbox-00-rg|cft-sbox-00-aks'
  'ba71a911-e0d6-4776-a1a6-079af1df7139|ss-ithc-00-rg|ss-ithc-00-aks'
  'c68a4bed-4c3d-4956-af51-4ae164c1957c|ss-demo-00-rg|ss-demo-00-aks'
  'c68a4bed-4c3d-4956-af51-4ae164c1957c|ss-demo-01-rg|ss-demo-01-aks'
  'd025fece-ce99-4df2-b7a9-b649d3ff2060|cft-demo-00-rg|cft-demo-00-aks'
  'd025fece-ce99-4df2-b7a9-b649d3ff2060|cft-demo-01-rg|cft-demo-01-aks'
)

usage() {
  printf 'Usage: %s [--dry-run | --help]\n' "${0##*/}"
}

log() {
  printf '%s\n' "${*}" >&2
}

main() {
  local dry_run=false
  local entry subscription resource_group cluster_name

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

  if [[ "${dry_run}" == false ]] && ! command -v az >/dev/null 2>&1; then
    log 'Azure CLI (az) is required. Install it and run az login first.'
    return 1
  fi

  for entry in "${CLUSTERS[@]}"; do
    IFS='|' read -r subscription resource_group cluster_name <<< "${entry}"
    if [[ -z "${subscription}" || -z "${resource_group}" || -z "${cluster_name}" || "${subscription}" == REPLACE_WITH_SUBSCRIPTION_ID ]]; then
      log "Invalid cluster entry: ${entry}. Set its subscription, resource group and cluster name."
      return 1
    fi

    if [[ "${dry_run}" == true ]]; then
      printf 'az aks get-credentials --subscription %q --resource-group %q --name %q --overwrite-existing\n' \
        "${subscription}" "${resource_group}" "${cluster_name}"
    else
      log "Refreshing ${cluster_name} (${subscription})"
      az aks get-credentials \
        --subscription "${subscription}" \
        --resource-group "${resource_group}" \
        --name "${cluster_name}" \
        --overwrite-existing
    fi
  done
}

main "${@}"