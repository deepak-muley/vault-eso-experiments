#!/bin/bash

# Alternative script to sync secret to workload cluster using kubectl
# This can be used if PushSecret doesn't work for remote Kubernetes clusters

set -e

MGMT_CLUSTER="mgmt"
WORKLOAD_CLUSTER="workload1"
SECRET_NAME="app-credentials"
NAMESPACE="default"

echo "Syncing secret ${SECRET_NAME} from ${MGMT_CLUSTER} to ${WORKLOAD_CLUSTER}..."

# Get secret from mgmt cluster
kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Get the secret data
SECRET_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o json)

# Switch to workload cluster
kind get kubeconfig --name ${WORKLOAD_CLUSTER} > /tmp/workload1-kubeconfig
export KUBECONFIG=/tmp/workload1-kubeconfig

# Create or update the secret in workload cluster
echo "$SECRET_DATA" | kubectl apply -f -

echo "Secret ${SECRET_NAME} synced successfully to ${WORKLOAD_CLUSTER}!"

