#!/usr/bin/env bash

get_token_valid(){
  API_SCOPE="$1"
  TENANT_ID="$2"
  VALID_TOKEN=$(az account get-access-token --tenant "$TENANT_ID" --scope "$API_SCOPE" --query accessToken -o tsv)
  echo "$VALID_TOKEN"
}

get_token_wrong_audience(){
  TENANT_ID="$1"
  WRONG_AUDIENCE_TOKEN=$(az account get-access-token --tenant "$TENANT_ID" --resource https://management.azure.com --query accessToken -o tsv)
  echo "$WRONG_AUDIENCE_TOKEN"
}

inspect_gateway_cert(){
  local TEST_HOST="$1"
  local GATEWAY_PORT="8443"
  echo "Inspecting gateway certificate for host: $TEST_HOST"
  openssl s_client \
    -connect "127.0.0.1:${GATEWAY_PORT}" \
    -servername "${TEST_HOST}" \
    -showcerts </dev/null
}

_port_forward_istio_gateway(){
  local NS="$1"
  # Port forward the Istio ingress gateway to localhost:8443
  kubectl -n "$NS" port-forward svc/istio-ingressgateway-oauth 8443:443 &
  PORT_FORWARD_PID=$!
  echo "Port forwarding Istio ingress gateway (443) to localhost:8443 (PID: $PORT_FORWARD_PID)"
}

connect_to_jwt_test() {
  local TEST_HOST="$1"
  local GATEWAY_PORT="8443"
  echo "Trying to test JWT on host: $TEST_HOST via port forwarding to localhost:${GATEWAY_PORT}"
  curl -kv \
    --connect-to "${TEST_HOST}:443:127.0.0.1:${GATEWAY_PORT}" \
    "https://${TEST_HOST}/"
}

test-gateway-policy-valid-token() {
 local TEST_HOST="$1"
 local TEST_PATH="$2"
 local GATEWAY_PORT="8443"
 local CA_CERT_PATH="/xxx-yyyy.pem"

 local API_SCOPE="api://xxxx-5d0c-xxxxxx/api.read"
 local valid_token=$(get_token_valid "$API_SCOPE" "xxxxxxx-9947-4e78-xxxxxx")
 local partial_token=$(echo "$valid_token" | cut -c1-20)
 echo "Testing gateway policy with valid token for host: $TEST_HOST, path: $TEST_PATH Valid token: [$partial_token...]"
 curl -k --silent --show-error --write-out '\nHTTP %{http_code}\n' \
   --connect-to "${TEST_HOST}:443:127.0.0.1:${GATEWAY_PORT}" \
   --header "Authorization: Bearer ${valid_token}" \
   "https://${TEST_HOST}${TEST_PATH}"
#   --cacert "$CA_CERT_PATH" \
}

test-gateway-policy-missing-token(){
  local TEST_HOST="$1"
  local TEST_PATH="$2"
  local GATEWAY_PORT="8443"
  echo "Testing gateway policy with missing token for host: $TEST_HOST, path: $TEST_PATH"
  curl -k --silent --show-error --write-out '\nHTTP %{http_code}\n' \
    --connect-to "${TEST_HOST}:443:127.0.0.1:${GATEWAY_PORT}" \
    "https://${TEST_HOST}${TEST_PATH}"
}

test-gateway-policy-invalid-token(){
  local TEST_HOST="$1"
  local TEST_PATH="$2"
  local GATEWAY_PORT="8443"
  local API_SCOPE="api://xxxx-xxxxxxx/api.read"
  local invalid_token=$(get_token_wrong_audience "xxxxxxx-9947-xxxxxx")
  local partial_token=$(echo "$invalid_token" | cut -c1-20)
  echo "Testing gateway policy with invalid token for host: $TEST_HOST, path: $TEST_PATH Invalid token: [$partial_token...]"
  curl -k --silent --show-error --write-out '\nHTTP %{http_code}\n' \
    --connect-to "${TEST_HOST}:443:127.0.0.1:${GATEWAY_PORT}" \
    --header "Authorization: Bearer ${invalid_token}" \
    "https://${TEST_HOST}${TEST_PATH}"
}

# Step 1: Port forward the Istio ingress gateway to localhost:8443. Do this in a separate terminal.
#_port_forward_istio_gateway "istio-ingress-oauth"

# Step 2: Test the gateway policy with a valid token, missing token, and invalid token in another terminal.
test-gateway-policy-valid-token "jwt-check.auth01.ste.nl.cjscp.org.uk" "/"
test-gateway-policy-missing-token "jwt-check.auth01.ste.nl.cjscp.org.uk" "/"
test-gateway-policy-invalid-token "jwt-check.auth01.ste.nl.cjscp.org.uk" "/"

#inspect_gateway_cert "jwt-check.auth01.ste.nl.cjscp.org.uk"

#connect_to_jwt_test "jwt-check.auth01.ste.nl.cjscp.org.uk"

# find the PID of the port-forward process and kill it when done
#lsof -nP -iTCP:8443 -sTCP:LISTEN
