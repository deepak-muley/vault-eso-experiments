#!/bin/bash

# Extract authentication info from kubeconfig for Kubernetes provider
# The Kubernetes provider doesn't support kubeconfig directly, so we need to extract:
# - Server URL
# - CA certificate
# - Client certificate and key (or token)

set -e

WORKLOAD_CLUSTER="workload1"
MGMT_CLUSTER="mgmt"
NAMESPACE="default"

echo "Extracting authentication info from ${WORKLOAD_CLUSTER} kubeconfig..."

# Set context to mgmt cluster
kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Prepare kubeconfig with internal IP
./prepare-workload-kubeconfig.sh

# Extract server URL from the prepared kubeconfig
SERVER_URL=$(grep "server:" /tmp/workload1-kubeconfig | awk '{print $2}' | head -1)

if [ -z "$SERVER_URL" ]; then
    echo "Error: Could not extract server URL"
    exit 1
fi

# Extract CA certificate (base64 encoded in kubeconfig, decode it)
CA_CERT_B64=$(kubectl --kubeconfig=/tmp/workload1-kubeconfig config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CA_CERT=$(echo "$CA_CERT_B64" | base64 -d)

# Extract client certificate
CLIENT_CERT_B64=$(kubectl --kubeconfig=/tmp/workload1-kubeconfig config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
CLIENT_CERT=$(echo "$CLIENT_CERT_B64" | base64 -d)

# Extract client key
CLIENT_KEY_B64=$(kubectl --kubeconfig=/tmp/workload1-kubeconfig config view --raw -o jsonpath='{.users[0].user.client-key-data}')
CLIENT_KEY=$(echo "$CLIENT_KEY_B64" | base64 -d)

# Create secret with extracted auth info
kubectl create secret generic workload1-auth \
  --from-literal=server="${SERVER_URL}" \
  --from-literal=ca.crt="${CA_CERT}" \
  --from-literal=client.crt="${CLIENT_CERT}" \
  --from-literal=client.key="${CLIENT_KEY}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created secret workload1-auth with authentication info"
echo "Server URL: ${SERVER_URL}"

