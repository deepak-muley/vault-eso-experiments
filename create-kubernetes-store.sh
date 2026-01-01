#!/bin/bash

# Create the Kubernetes SecretStore with proper server URL
# This script extracts the server URL and creates the ClusterSecretStore

set -e

WORKLOAD_CLUSTER="workload1"
MGMT_CLUSTER="mgmt"
NAMESPACE="default"

echo "Creating Kubernetes SecretStore for ${WORKLOAD_CLUSTER}..."

# Set context to mgmt cluster
kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Extract auth info first (this also prepares the kubeconfig)
./extract-kubeconfig-auth.sh

# Extract server URL from the prepared kubeconfig
SERVER_URL=$(grep "server:" /tmp/workload1-kubeconfig | awk '{print $2}' | head -1)

if [ -z "$SERVER_URL" ]; then
    echo "Error: Could not extract server URL from kubeconfig"
    exit 1
fi

echo "Using server URL: ${SERVER_URL}"

# Create ClusterSecretStore with the server URL
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: kubernetes-remote-store
spec:
  provider:
    kubernetes:
      remoteNamespace: ${NAMESPACE}
      server:
        url: "${SERVER_URL}"
        caProvider:
          type: Secret
          name: workload1-auth
          key: ca.crt
          namespace: ${NAMESPACE}
      auth:
        cert:
          clientCert:
            name: workload1-auth
            key: client.crt
            namespace: ${NAMESPACE}
          clientKey:
            name: workload1-auth
            key: client.key
            namespace: ${NAMESPACE}
EOF

echo "ClusterSecretStore created successfully!"

