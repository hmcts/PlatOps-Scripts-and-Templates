# BusyBox test page for the OAuth ingress gateway

This test deploys a static page behind an Istio VirtualService, then checks the
gateway with a valid token, no token, and a token for the wrong audience. The
port-forward test reaches one ingress pod directly; it does not test the
LoadBalancer IP or DNS resolution of the test hostname.

## Prerequisites

- `kubectl` configured for the intended cluster, with permission to create the
  namespace and resources and to port-forward the ingress Service.
- An existing Istio ingress Gateway and its authorization and JWT policies.
- An Azure CLI sign-in able to obtain a token for the API scope used in
  `test-access-token.sh`. The script also requests an Azure Resource Manager
  token for the wrong-audience test.
- `curl` and a trusted PEM CA bundle for the ingress certificate. The cluster
  must be able to pull the BusyBox image specified in the manifest.

Confirm the target before making changes:

```bash
kubectl config current-context
az login --tenant "e2995d11-9947-4e78-9de6-d44e0603518e" \
  --scope "api://6d9ad1f5-5d0c-4c71-9bfd-63ec724a3344/api.read"
```

## Set up the page

Run the following commands from this `testing` directory. The supplied manifest
uses `ns-ste-ops-99`. To use another new namespace, edit **every**
`metadata.namespace` in `istio-vs-busybox.yaml` and the namespace in the
VirtualService destination host. Also replace `ns-ste-ops-99` in the commands
below. Passing `kubectl -n` alone does not override explicit manifest namespaces.

Confirm the VirtualService's `hosts` and `gateways` match your deployment. The
supplied values are:

```yaml
hosts:
  - jwt-check.auth01.ste.nl.cjscp.org.uk
gateways:
  - istio-ingress-oauth/istio-ingressgateway-oauth
```

The Gateway reference is `<Gateway namespace>/<Gateway resource name>`. Check
that its selector matches the ingress pods and its HTTPS server accepts the
hostname. If you change the test host, also change the three calls at the end
of `test-access-token.sh`.

Create the namespace and apply the resources:

```bash
kubectl create namespace ns-ste-ops-99
kubectl apply -f istio-vs-busybox.yaml
kubectl -n ns-ste-ops-99 rollout status deployment/oauth-gateway-test-page
kubectl -n ns-ste-ops-99 get pods,service,virtualservice
```

The manifest creates a ConfigMap, Deployment, ClusterIP Service on port 8080,
and VirtualService. The expected page contains `oauth-gateway-policy-test`.

`setup-busybox-http-page.sh` is an alternative for the default namespace, but
it **deletes existing resources of the same names before recreating them**.
Its namespace is hard-coded; editing only the manifest is not sufficient to use
that script for a different namespace. The direct `kubectl apply` above avoids
that delete-and-recreate behavior.

## Step 1: Port-forward the ingress gateway

In a separate terminal, keep this command running:

```bash
kubectl -n istio-ingress-oauth port-forward \
  svc/istio-ingressgateway-oauth 8443:443
```

This is the command used by `_port_forward_istio_gateway` in the test script.
Wait for the `Forwarding from 127.0.0.1:8443` message before testing. If port
8443 is already in use, stop the existing listener or choose a different local
port and update `GATEWAY_PORT` in the test functions accordingly.

## Step 2: Test the gateway policy

Before running `test-access-token.sh`, update its test functions:

1. In `test-gateway-policy-valid-token`, replace the placeholder header
   `Authorization: ******` with `Authorization: Bearer ${valid_token}`.
2. In `test-gateway-policy-invalid-token`, replace its placeholder header with
   `Authorization: Bearer ${invalid_token}`. This function obtains an Azure
   Resource Manager token, which is intended to have the wrong audience for
   this API.
3. In **all three** test functions, replace `curl -k` with `curl --cacert
   "/path/to/organisation-ca-bundle.pem"`, using the actual trusted CA bundle.
   The existing `CA_CERT_PATH` is a machine-specific path and its `--cacert`
   line is commented out. Do not send tokens with certificate verification
   disabled or use verbose curl output that exposes authorization headers.
4. Verify the tenant, API scope, host and path in the script match your
   deployment. Remove the lines printing partial tokens if test output is shared.

With the port-forward still running, use another terminal:

```bash
bash ./test-access-token.sh
```

The script runs the valid-token, missing-token and wrong-audience-token tests
in that order. Confirm that token acquisition succeeds before interpreting the
results: the current script does not reliably stop when acquisition fails.

Expected results depend on the deployed policies:

| Test | Expected when the policy requires a valid API token |
| --- | --- |
| Valid token | HTTP 200 and a page containing `oauth-gateway-policy-test` |
| Missing token | Rejected, commonly HTTP 403 |
| Wrong audience | Rejected, commonly HTTP 401 if JWT validation checks the audience |

A successful page alone does not prove that the policy rejects other requests;
check all three results. Never paste tokens or unredacted authorization headers
into logs or support requests.

## Troubleshooting

- **Certificate issuer error:** use the correct trusted CA bundle and check that
  the Gateway serves the required intermediate certificates.
- **403 with the valid token:** inspect the applicable Istio
  `RequestAuthentication` and `AuthorizationPolicy` resources, including
  issuer, audience and required claims.
- **404 with `NR route_not_found` in the ingress access log:** verify the
  deployed VirtualService's host and Gateway reference, Gateway selector and
  host, and route configuration in the specific ingress pod.

Stop the port-forward with Ctrl+C when finished.
