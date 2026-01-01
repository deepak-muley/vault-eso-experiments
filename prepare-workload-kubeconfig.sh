#!/bin/bash

# This script prepares the workload cluster kubeconfig for use in PushSecret
# It extracts the kind cluster's internal API server address

set -e

WORKLOAD_CLUSTER="workload1"

echo "Preparing kubeconfig for ${WORKLOAD_CLUSTER} cluster..."

# Get the workload cluster kubeconfig
kind get kubeconfig --name ${WORKLOAD_CLUSTER} > /tmp/workload1-kubeconfig-raw

# For kind clusters, we need to get the internal API server address
# Try to get the control plane node's IP in the Docker network
WORKLOAD_CP_IP=$(docker inspect ${WORKLOAD_CLUSTER}-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

if [ -z "$WORKLOAD_CP_IP" ]; then
    echo "Warning: Could not get control plane IP from Docker."
    echo "Trying alternative: using kind network gateway..."
    
    # Get the kind network gateway (usually 172.x.x.1)
    KIND_NETWORK=$(docker network ls | grep kind | awk '{print $1}' | head -1)
    if [ ! -z "$KIND_NETWORK" ]; then
        GATEWAY_IP=$(docker network inspect $KIND_NETWORK --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
        if [ ! -z "$GATEWAY_IP" ]; then
            # Use the control plane hostname with kind network
            # For kind, we can use the service name: workload1-control-plane:6443
            # But we need the IP, so let's try getting it from the kind network
            WORKLOAD_CP_IP=$(docker network inspect $KIND_NETWORK --format '{{range .Containers}}{{if eq .Name "'${WORKLOAD_CLUSTER}'-control-plane"}}{{.IPv4Address}}{{end}}{{end}}' 2>/dev/null | cut -d'/' -f1)
        fi
    fi
fi

if [ -z "$WORKLOAD_CP_IP" ]; then
    echo "Warning: Could not determine internal IP. Using original kubeconfig."
    echo "Note: PushSecret may not work if the API server is not accessible from mgmt cluster."
    cp /tmp/workload1-kubeconfig-raw /tmp/workload1-kubeconfig
else
    # Replace localhost with the control plane IP
    # Kind clusters use port 6443 internally
    sed "s|server:.*|server: https://${WORKLOAD_CP_IP}:6443|g" /tmp/workload1-kubeconfig-raw > /tmp/workload1-kubeconfig
    
    echo "Updated kubeconfig to use internal IP: ${WORKLOAD_CP_IP}:6443"
fi

echo "Kubeconfig prepared: /tmp/workload1-kubeconfig"

