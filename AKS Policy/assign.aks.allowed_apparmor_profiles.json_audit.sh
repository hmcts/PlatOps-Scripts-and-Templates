#!/bin/zsh

# Ensure all cluster contexts are loaded into kubectl and valid

set -uo pipefail

contexts=$(kubectl config get-contexts -o name | grep -E '^(cft-|ss-)' | sort)

for ctx in ${(f)contexts}; do
  echo "### CONTEXT: $ctx"

  echo "-- legacy annotations --"
  kubectl --context="$ctx" get pods --all-namespaces -o json 2>/tmp/err.$$ | jq -r '
    .items[] | .metadata as $m |
    ($m.annotations // {} | to_entries[] | select(.key | startswith("container.apparmor.security.beta.kubernetes.io/"))) as $a |
    [$m.namespace, $a.key, $a.value] | @tsv
  ' | sort | uniq -c

  echo "-- native appArmorProfile (non runtime/default) --"
  kubectl --context="$ctx" get pods --all-namespaces -o json 2>>/tmp/err.$$ | jq -r '
    .items[] | .metadata as $m |
    (.spec.containers[]? | select(.securityContext.appArmorProfile != null and .securityContext.appArmorProfile.type != "RuntimeDefault")) as $c |
    [$m.namespace, $c.name, $c.securityContext.appArmorProfile.type, ($c.securityContext.appArmorProfile.localhostProfile // "")] | @tsv
  ' | sort | uniq -c

  if [[ -s /tmp/err.$$ ]]; then
    echo "-- errors --"
    cat /tmp/err.$$
  fi
  rm -f /tmp/err.$$
  echo ""
done
