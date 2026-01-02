#!/bin/bash

set -ex

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

MGMT_CLUSTER="mgmt"
VAULT_NAMESPACE="vault"
VAULT_RELEASE="vault"

echo -e "${GREEN}Bootstrapping Vault with secrets...${NC}"

# Check if we're connected to Mgmt cluster
if ! kubectl config current-context | grep -q "kind-${MGMT_CLUSTER}"; then
    echo -e "${YELLOW}Setting context to Mgmt cluster...${NC}"
    kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
    export KUBECONFIG=/tmp/mgmt-kubeconfig
    kubectl config use-context kind-${MGMT_CLUSTER}
fi

# Check if Vault is running
echo -e "${YELLOW}Checking Vault pod status...${NC}"
if ! kubectl get pods -n ${VAULT_NAMESPACE} -l app.kubernetes.io/name=vault | grep -q Running; then
    echo -e "${RED}Vault is not running. Please run setup.sh first.${NC}"
    exit 1
fi

# Wait for Vault pod to be ready
echo -e "${YELLOW}Waiting for Vault pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=120s

# Get Vault pod name
VAULT_POD=$(kubectl get pods -n ${VAULT_NAMESPACE} -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

# Set Vault address and token for kubectl exec
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

echo -e "${GREEN}Vault pod is ready: ${VAULT_POD}${NC}"

# Function to run vault commands via kubectl exec
vault_exec() {
    kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault "$@"
}

# Enable KV secrets engine if not already enabled
echo -e "${YELLOW}Enabling KV secrets engine...${NC}"
vault_exec secrets enable -version=2 -path=secret kv 2>/dev/null || echo "KV secrets engine already enabled"

# Create secrets
echo -e "${YELLOW}Adding secrets to Vault...${NC}"

# Main app credentials
vault_exec kv put secret/app-credentials \
  username="admin" \
  password="SuperSecretPassword123!"

echo -e "${GREEN}✓ Added secret/app-credentials${NC}"

# Verify the secret was stored
echo -e "${YELLOW}Verifying secret/app-credentials:${NC}"
vault_exec kv get secret/app-credentials

# Additional example secrets (optional)
vault_exec kv put secret/database-credentials \
  host="db.example.com" \
  port="5432" \
  username="dbuser" \
  password="DbSecretPass456!" \
  database="myapp"

echo -e "${GREEN}✓ Added secret/database-credentials${NC}"

# Verify the secret was stored
echo -e "${YELLOW}Verifying secret/database-credentials:${NC}"
vault_exec kv get secret/database-credentials

vault_exec kv put secret/api-keys \
  github_token="ghp_example_token_12345" \
  aws_access_key="AKIAIOSFODNN7EXAMPLE" \
  aws_secret_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

echo -e "${GREEN}✓ Added secret/api-keys${NC}"

# Verify the secret was stored
echo -e "${YELLOW}Verifying secret/api-keys:${NC}"
vault_exec kv get secret/api-keys

# List all secrets
echo -e "${YELLOW}Listing all secrets in Vault:${NC}"
vault_exec kv list secret/

echo -e "${GREEN}Bootstrap completed successfully!${NC}"
echo -e "${GREEN}Secrets available in Vault:${NC}"
echo -e "  - secret/app-credentials (username, password)"
echo -e "  - secret/database-credentials (host, port, username, password, database)"
echo -e "  - secret/api-keys (github_token, aws_access_key, aws_secret_key)"

