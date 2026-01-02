#!/bin/bash

set -ex

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MGMT_CLUSTER="mgmt"
WORKLOAD_CLUSTER="workload1"
VAULT_NAMESPACE="vault"
ESO_NAMESPACE="external-secrets"
VAULT_RELEASE="vault"
ESO_RELEASE="external-secrets"

echo -e "${GREEN}Starting Vault and External Secrets Operator setup...${NC}"

# Step 0: Check and install prerequisites
echo -e "${YELLOW}Step 0: Checking prerequisites...${NC}"

# Check for vault CLI
if ! command -v vault &> /dev/null; then
    echo -e "${YELLOW}Vault CLI not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install vault
        else
            echo -e "${RED}Homebrew not found. Please install Homebrew first:${NC}"
            echo -e "${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
            echo -e "${RED}Or install Vault manually from: https://developer.hashicorp.com/vault/downloads${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Vault CLI not found. Please install it manually:${NC}"
        echo -e "${YELLOW}Visit: https://developer.hashicorp.com/vault/downloads${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Vault CLI found: $(vault version | head -1)${NC}"
fi

# Check for other prerequisites
if ! command -v kind &> /dev/null; then
    echo -e "${RED}kind not found. Please install it first.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install it first.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install it first.${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites satisfied!${NC}"

# Step 1: Delete existing kind clusters
echo -e "${YELLOW}Step 1: Cleaning up existing kind clusters...${NC}"
kind get clusters | while read cluster; do
    if [ ! -z "$cluster" ]; then
        echo -e "${YELLOW}Deleting cluster: $cluster${NC}"
        kind delete cluster --name "$cluster"
    fi
done

# Step 2: Create new kind clusters
echo -e "${YELLOW}Step 2: Creating kind clusters...${NC}"

# Create Mgmt cluster with 1 control plane and 1 worker
cat <<EOF | kind create cluster --name ${MGMT_CLUSTER} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

# Create workload1 cluster with 1 control plane and 1 worker
cat <<EOF | kind create cluster --name ${WORKLOAD_CLUSTER} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

echo -e "${GREEN}Clusters created successfully!${NC}"

# Step 3: Set kubeconfig context to Mgmt cluster
kind get kubeconfig --name ${MGMT_CLUSTER} > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig
kubectl config use-context kind-${MGMT_CLUSTER}

# Step 4: Install Vault using Helm
echo -e "${YELLOW}Step 3: Installing Vault on Mgmt cluster...${NC}"
kubectl create namespace ${VAULT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install ${VAULT_RELEASE} hashicorp/vault \
  --namespace ${VAULT_NAMESPACE} \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "server.extraArgs=-dev-listen-address=0.0.0.0:8200" \
  --wait

echo -e "${GREEN}Vault installed successfully!${NC}"

# Wait for Vault pod to be ready
echo -e "${YELLOW}Waiting for Vault pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s

# Step 5: Install External Secrets Operator using Helm
echo -e "${YELLOW}Step 4: Installing External Secrets Operator on Mgmt cluster...${NC}"
kubectl create namespace ${ESO_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install ${ESO_RELEASE} external-secrets/external-secrets \
  --namespace ${ESO_NAMESPACE} \
  --wait

echo -e "${GREEN}External Secrets Operator installed successfully!${NC}"

# Wait for ESO pods to be ready
echo -e "${YELLOW}Waiting for ESO pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n ${ESO_NAMESPACE} --timeout=300s

# Step 6: Configure Vault with username and password
echo -e "${YELLOW}Step 5: Configuring Vault with username and password...${NC}"
./bootstrap-vault.sh

# Step 7: Wait for ESO CRDs to be ready
echo -e "${YELLOW}Step 6: Waiting for ESO CRDs to be ready...${NC}"
kubectl wait --for condition=established --timeout=60s crd/clustersecretstores.external-secrets.io || true
kubectl wait --for condition=established --timeout=60s crd/externalsecrets.external-secrets.io || true
kubectl wait --for condition=established --timeout=60s crd/pushsecrets.external-secrets.io || true

# Wait a bit more for API server to recognize the CRDs
echo -e "${YELLOW}Waiting for API server to recognize CRDs...${NC}"
sleep 10

# Verify CRDs are available via API
kubectl api-resources | grep -q clustersecretstore || (echo "ClusterSecretStore CRD not available" && exit 1)

# Step 8: Create ExternalSecretStore
echo -e "${YELLOW}Step 7: Creating ExternalSecretStore...${NC}"
kubectl apply -f yamls/external-secret-store.yaml

# Wait for store to be ready
sleep 5

# Step 9: Create ExternalSecret
echo -e "${YELLOW}Step 8: Creating ExternalSecret...${NC}"
kubectl apply -f yamls/external-secret.yaml

# Wait for secret to be synced
echo -e "${YELLOW}Waiting for ExternalSecret to sync...${NC}"
sleep 10
kubectl wait --for=condition=Ready externalsecret/app-credentials --timeout=60s || true

# Step 10: Create PushSecret to push to workload1
echo -e "${YELLOW}Step 9: Creating PushSecret to push secret to workload1 cluster...${NC}"

# Create Kubernetes SecretStore with proper authentication
./create-kubernetes-store.sh

# Apply PushSecret
kubectl apply -f yamls/push-secret.yaml

# Wait for push secret to be synced (if PushSecret works)
echo -e "${YELLOW}Waiting for PushSecret to sync...${NC}"
sleep 10
kubectl wait --for=condition=Ready pushsecret/app-credentials-push --timeout=60s 2>/dev/null || {
    echo -e "${YELLOW}PushSecret may not support remote Kubernetes clusters directly.${NC}"
    echo -e "${YELLOW}Using alternative sync method...${NC}"
    ./sync-secret-to-workload.sh || true
}

# Cleanup port forward
kill $PF_PID 2>/dev/null || true

echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${GREEN}Summary:${NC}"
echo -e "  - Mgmt cluster: ${MGMT_CLUSTER}"
echo -e "  - Workload cluster: ${WORKLOAD_CLUSTER}"
echo -e "  - Vault namespace: ${VAULT_NAMESPACE}"
echo -e "  - ESO namespace: ${ESO_NAMESPACE}"
echo -e "  - Secret stored in Vault: secret/app-credentials"
echo -e "  - ExternalSecret created: app-credentials"
echo -e "  - PushSecret created: app-credentials-push"

