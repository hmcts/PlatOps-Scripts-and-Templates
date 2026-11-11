#!/usr/bin/env bash

create_namespace() {
  local namespace="$1"
  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Creating namespace: $namespace"
    kubectl create namespace "$namespace"
  else
    echo "Namespace $namespace already exists."
  fi
}

apply_istio_vs_busybox() {
  local namespace="$1"
  echo "Applying istio-vs-busybox.yaml to namespace: $namespace"
  # check if the namespace exists before applying the manifest
  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Error: Namespace $namespace does not exist. Please create it first."
    exit 1
  fi
  # check the following resources (configmap/oauth-gateway-test-page, deployment.apps/oauth-gateway-test-page,service/oauth-gateway-test-page, virtualservice.networking.istio.io/oauth-gateway-test-page ) before applying the manifest
  if kubectl get configmap/oauth-gateway-test-page -n "$namespace" >/dev/null 2>&1; then
    echo "ConfigMap oauth-gateway-test-page already exists in namespace $namespace. Deleting it first."
    kubectl delete configmap/oauth-gateway-test-page -n "$namespace"
  fi
  if kubectl get deployment.apps/oauth-gateway-test-page -n "$namespace" >/dev/null 2>&1; then
    echo "Deployment oauth-gateway-test-page already exists in namespace $namespace. Deleting it first."
    kubectl delete deployment.apps/oauth-gateway-test-page -n "$namespace"
  fi
  if kubectl get service/oauth-gateway-test-page -n "$namespace" >/dev/null 2>&1; then
    echo "Service oauth-gateway-test-page already exists in namespace $namespace. Deleting it first."
    kubectl delete service/oauth-gateway-test-page -n "$namespace"
  fi
  if kubectl get virtualservice.networking.istio.io/oauth-gateway-test-page -n "$namespace" >/dev/null 2>&1; then
    echo "VirtualService oauth-gateway-test-page already exists in namespace $namespace. Deleting it first."
    kubectl delete virtualservice.networking.istio.io/oauth-gateway-test-page -n "$namespace"
  fi

  kubectl apply -f istio-vs-busybox.yaml -n "$namespace"
}

create_namespace "ns-ste-ops-99"
apply_istio_vs_busybox "ns-ste-ops-99"
