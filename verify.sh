#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

MGMT_CLUSTER="mgmt"
WORKLOAD_CLUSTER="workload1"

echo -e "${YELLOW}Verifying setup...${NC}"

# Check Mgmt cluster
echo -e "${YELLOW}Checking Mgmt cluster...${NC}"
kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig
kubectl config use-context kind-${MGMT_CLUSTER}

echo -e "${YELLOW}Vault pods:${NC}"
kubectl get pods -n vault

echo -e "${YELLOW}ESO pods:${NC}"
kubectl get pods -n external-secrets

echo -e "${YELLOW}ExternalSecret status:${NC}"
kubectl get externalsecret app-credentials

echo -e "${YELLOW}Secret in Mgmt cluster:${NC}"
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d && echo

echo -e "${YELLOW}PushSecret status:${NC}"
kubectl get pushsecret app-credentials-push

# Check workload1 cluster
echo -e "${YELLOW}Checking workload1 cluster...${NC}"
kind get kubeconfig --name ${WORKLOAD_CLUSTER} > /tmp/workload1-kubeconfig-verify
export KUBECONFIG=/tmp/workload1-kubeconfig-verify
kubectl config use-context kind-${WORKLOAD_CLUSTER}

echo -e "${YELLOW}Secret in workload1 cluster:${NC}"
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d && echo

echo -e "${GREEN}Verification completed!${NC}"

