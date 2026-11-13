#!/usr/bin/env bash

test_istio_ingress_gateway() {
  local TEST_HOST="$1"
  local TEST_PATH="$2"
  local TOKEN="xxxxxxxxxx"
  echo "Testing Istio ingress gateway for host: $TEST_HOST, path: $TEST_PATH"
  curl -sS -i --connect-timeout 5 --max-time 15 \
   -H "Authorization: Bearer $TOKEN" \
   https://${TEST_HOST}${TEST_PATH}
}

connect_to_jumpbox_bastion() {
  local RG_ID="$1"
  local SUB_ID="$2"
  local JUMPBOX_NAME="$3"
  local USERNAME="$4"
  local jumpbox_resource_id="/subscriptions/${SUB_ID}/resourceGroups/${RG_ID}/providers/Microsoft.Compute/virtualMachines/${JUMPBOX_NAME}"
  if [[ -z "$RG_ID" || -z "$SUB_ID" || -z "$JUMPBOX_NAME" || -z "$USERNAME" ]]; then
    echo "Usage: connect_to_jumpbox_bastion <RG_ID> <SUB_ID> <JUMPBOX_NAME> <USERNAME>"
    return 1
  fi

  # Connect to the jumpbox via Azure Bastion
  az network bastion ssh \
    --name BA-MDV-DMZ-01 \
    --resource-group RG-MDV-BASTION-01 \
    --target-resource-id "$jumpbox_resource_id" \
    --auth-type AAD \
    --username "$USERNAME" \
    -- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes
#   -o IdentitiesOnly=yes -o PreferredAuthentications=publickey
}

get_access_token() {
  az account get-access-token --tenant "xxx-xxxx-xxxx-xxxx-xxxx" \
   --scope "api://xxxx-5d0c-xxxxxx/api.read" \
   --query accessToken -o tsv
}

#connect_to_jumpbox_bastion "RG-MDV-INT-01" "xxxxx-a835-xxxxxxxxx" "MDVJUMPL01.cpp.nonlive" "firstname.lastname"
#get_access_token
#test_istio_ingress_gateway "jwt-check.auth01.ste.nl.cjscp.org.uk" "/"
