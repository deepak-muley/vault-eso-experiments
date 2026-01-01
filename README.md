# Vault and External Secrets Operator (ESO) Multi-Cluster Setup

This repository contains scripts and configurations to set up HashiCorp Vault and External Secrets Operator across multiple Kubernetes clusters using Kind. The setup demonstrates how to manage secrets in a management cluster and push them to workload clusters without installing any components on the workload clusters.

## Overview

This setup creates:
- **Mgmt Cluster**: Management cluster with Vault and External Secrets Operator installed
- **workload1 Cluster**: Workload cluster that receives secrets via PushSecret (no ESO installation required)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Mgmt Cluster                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  Vault   │───▶│ External     │───▶│  PushSecret      │  │
│  │          │    │ SecretStore  │    │                  │  │
│  └──────────┘    └──────────────┘    └──────────────────┘  │
│                          │                    │             │
│                          ▼                    ▼             │
│                   ┌──────────────┐    ┌──────────────┐     │
│                   │ External     │    │  Kubernetes  │     │
│                   │ Secret       │    │  Secret      │     │
│                   └──────────────┘    └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ (via kubeconfig)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  workload1 Cluster                          │
│  ┌──────────────┐                                           │
│  │  Kubernetes  │                                           │
│  │  Secret      │                                           │
│  │  (synced)    │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before running the setup, ensure you have the following tools installed:

| Tool | Version | Installation |
|------|---------|--------------|
| `kind` | Latest | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| `kubectl` | v1.24+ | [kubernetes.io/docs/tasks/tools/](https://kubernetes.io/docs/tasks/tools/) |
| `helm` | v3.8+ | [helm.sh/docs/intro/install/](https://helm.sh/docs/intro/install/) |
| `vault` CLI | Latest | [developer.hashicorp.com/vault/install](https://developer.hashicorp.com/vault/install) |

## Quick Start

### 1. Run the Setup Script

```bash
./setup.sh
```

This script will:
1. Delete any existing kind clusters
2. Create two new clusters: `Mgmt` and `workload1`
3. Install Vault on the Mgmt cluster
4. Install External Secrets Operator on the Mgmt cluster
5. Configure Vault with a username and password
6. Create ExternalSecretStore and ExternalSecret
7. Create PushSecret to sync secrets to workload1

### 2. Verify the Setup

```bash
./verify.sh
```

This will check:
- Vault and ESO pods are running
- ExternalSecret is synced
- Secret exists in Mgmt cluster
- PushSecret is synced
- Secret exists in workload1 cluster

### 3. Cleanup

```bash
./cleanup.sh
```

This will delete all kind clusters.

## Manual Setup Steps

If you prefer to run the steps manually:

### Step 1: Create Kind Clusters

```bash
# Create Mgmt cluster
kind create cluster --name Mgmt --config yamls/kind-cluster-configs.yaml

# Create workload1 cluster
kind create cluster --name workload1 --config yamls/kind-cluster-configs.yaml
```

### Step 2: Install Vault on Mgmt Cluster

```bash
# Set context to Mgmt cluster
kind get kubeconfig --name Mgmt > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Create namespace
kubectl create namespace vault

# Add Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault
helm install vault hashicorp/vault \
  --namespace vault \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "server.extraArgs=-dev-listen-address=0.0.0.0:8200" \
  --wait
```

### Step 3: Install External Secrets Operator

```bash
# Create namespace
kubectl create namespace external-secrets

# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --wait
```

### Step 4: Configure Vault with Secrets

```bash
# Port forward Vault
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Enable KV secrets engine
vault secrets enable -version=2 -path=secret kv

# Store username and password
vault kv put secret/app-credentials \
  username="admin" \
  password="SuperSecretPassword123!"
```

### Step 5: Create ExternalSecretStore

```bash
kubectl apply -f yamls/external-secret-store.yaml
```

### Step 6: Create ExternalSecret

```bash
kubectl apply -f yamls/external-secret.yaml
```

### Step 7: Create PushSecret

```bash
# Export workload1 kubeconfig
kind get kubeconfig --name workload1 > /tmp/workload1-kubeconfig

# Create kubeconfig secret
kubectl create secret generic workload1-kubeconfig \
  --from-file=config=/tmp/workload1-kubeconfig

# Apply PushSecret
kubectl apply -f yamls/push-secret.yaml
```

## YAML Files Reference

### `yamls/external-secret-store.yaml`

Defines the connection to Vault. This ClusterSecretStore allows ExternalSecrets to fetch secrets from Vault.

**Key Components:**
- `ClusterSecretStore`: Cluster-wide secret store (can be used by any namespace)
- `ServiceAccount`: Service account for authentication (if using Kubernetes auth)
- `Secret`: Contains Vault token (for dev/testing)

### `yamls/external-secret.yaml`

Defines which secrets to fetch from Vault and how to create Kubernetes secrets.

**Key Components:**
- `ExternalSecret`: References the ClusterSecretStore
- `data`: Maps Vault keys to Kubernetes secret keys
- `target`: Defines the Kubernetes secret to create
- `template`: Optional template for secret data transformation

### `yamls/push-secret.yaml`

Defines how to push secrets from the Mgmt cluster to workload clusters.

**Key Components:**
- `PushSecret`: References a local Kubernetes secret
- `selector`: Selects the secret to push
- `target.remoteRefs`: Defines where to push the secret
- `kubeconfig`: References the remote cluster's kubeconfig

## Verification Commands

### Check Vault Status

```bash
kubectl get pods -n vault
kubectl logs -n vault -l app.kubernetes.io/name=vault
```

### Check ESO Status

```bash
kubectl get pods -n external-secrets
kubectl get externalsecret
kubectl get pushsecret
```

### Check Secrets

```bash
# In Mgmt cluster
kubectl get secret app-credentials -o yaml

# In workload1 cluster
kind get kubeconfig --name workload1 > /tmp/w1-kubeconfig
export KUBECONFIG=/tmp/w1-kubeconfig
kubectl get secret app-credentials -o yaml
```

### Decode Secret Values

```bash
# Username
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d

# Password
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d
```

## Troubleshooting

### Vault Not Accessible

```bash
# Check Vault pod status
kubectl get pods -n vault

# Check Vault logs
kubectl logs -n vault -l app.kubernetes.io/name=vault

# Verify service
kubectl get svc -n vault
```

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret app-credentials

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### PushSecret Not Syncing

```bash
# Check PushSecret status
kubectl describe pushsecret app-credentials-push

# Verify kubeconfig secret exists
kubectl get secret workload1-kubeconfig

# Check remote cluster connectivity
kubectl get secret workload1-kubeconfig -o jsonpath='{.data.config}' | base64 -d > /tmp/check-kubeconfig
export KUBECONFIG=/tmp/check-kubeconfig
kubectl get nodes
```

## Security Considerations

⚠️ **This setup is for development/testing only!**

For production:
1. Use Vault's Kubernetes authentication instead of root token
2. Enable TLS for Vault
3. Use proper RBAC for service accounts
4. Store kubeconfig secrets securely
5. Enable audit logging in Vault
6. Use sealed secrets or other encryption for kubeconfig

## References

- [HashiCorp Vault Installation](https://developer.hashicorp.com/vault/install)
- [Vault GitHub Repository](https://github.com/hashicorp/vault)
- [External Secrets Operator Getting Started](https://external-secrets.io/latest/introduction/getting-started/)
- [External Secrets Operator GitHub](https://github.com/external-secrets/external-secrets)
- [PushSecret API Documentation](https://external-secrets.io/latest/api/pushsecret/)

## License

This repository is provided as-is for educational purposes.

