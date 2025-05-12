#!/bin/bash

set -euo pipefail

# Input parameters
CLUSTER_NAME="${1:-}"
NAMESPACE="${2:-argocd}"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "❌ Usage: $0 <kind-cluster-name> [argocd-namespace]"
  exit 1
fi

if [[ "$CLUSTER_NAME" == *"-control-plane" ]]; then
  echo "❌ Please provide the KIND cluster name (e.g. 'argocd-child-1'), not the container name"
  exit 1
fi

echo "📦 Registering cluster: $CLUSTER_NAME into namespace: $NAMESPACE"

# Get container IP
CONTAINER_IP=$(docker inspect "${CLUSTER_NAME}-control-plane" --format '{{ .NetworkSettings.Networks.kind.IPAddress }}' 2>/dev/null || true)
if [[ -z "$CONTAINER_IP" ]]; then
  echo "❌ Could not find container IP for $CLUSTER_NAME"
  exit 1
fi

echo "🔍 Container IP: $CONTAINER_IP"

# Clean up any existing secret
kubectl delete secret "$CLUSTER_NAME" -n "$NAMESPACE" --ignore-not-found

# Create the secret
kubectl create secret generic "$CLUSTER_NAME" \
  --from-literal=name="$CLUSTER_NAME" \
  --from-literal=server="https://${CONTAINER_IP}:6443" \
  --from-literal=config='{"tlsClientConfig":{"insecure":true}}' \
  -n "$NAMESPACE" \
  --type argoproj.io/cluster

# Label the secret so ArgoCD picks it up
kubectl label secret "$CLUSTER_NAME" \
  -n "$NAMESPACE" \
  argocd.argoproj.io/secret-type=cluster --overwrite

echo "✅ Cluster \"$CLUSTER_NAME\" registered in namespace \"$NAMESPACE\" with server=https://${CONTAINER_IP}:6443"
echo "🔁 Restarting ArgoCD controller to pick up the new cluster..."

kubectl rollout restart StatefulSet argocd-application-controller -n "$NAMESPACE"

# Final verification
echo "🔎 Verifying cluster registration..."
sleep 3
argocd --server localhost:8080 --insecure cluster list | grep "$CLUSTER_NAME" || echo "⚠️  Still not visible — check ArgoCD UI and logs."
