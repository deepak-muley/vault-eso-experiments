# Managing Secrets Across Kubernetes Clusters with Vault and External Secrets Operator

Managing secrets in a multi-cluster Kubernetes environment can be challenging. In this guide, we'll explore how to use HashiCorp Vault as a centralized secrets management solution and External Secrets Operator (ESO) to automatically sync secrets across clusters — all without installing any components on workload clusters.

> **📦 Complete Code Repository:** All scripts, YAML files, and configurations referenced in this guide are available in the [vault-eso-experiments GitHub repository](https://github.com/deepak-muley/vault-eso-experiments). Clone the repo to get started: `git clone https://github.com/deepak-muley/vault-eso-experiments.git`

## The Challenge

In a multi-cluster setup, you often have:
- A **management cluster** where you want to centralize secret management
- Multiple **workload clusters** that need access to these secrets
- The requirement to keep workload clusters lightweight (no additional operators)

Traditional approaches require installing and configuring secret management tools on every cluster, which increases operational overhead and complexity.

## The Solution

We'll use:
- **HashiCorp Vault**: Centralized secrets management
- **External Secrets Operator**: Kubernetes operator that syncs secrets from external systems
- **PushSecret**: ESO feature that pushes secrets to remote clusters without installing ESO on them

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    mgmt Cluster                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  Vault   │───▶│ External     │───▶│  PushSecret      │  │
│  │          │    │ SecretStore  │    │                  │  │
│  └──────────┘    └──────────────┘    └──────────────────┘  │
│                          │                    │             │
│                          ▼                    ▼             │
│                   ┌──────────────┐    ┌──────────────┐     │
│                   │ External     │    │  Kubernetes  │     │
│                   │ Secret        │    │  Secret      │     │
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

Before we begin, ensure you have the following tools installed:

```
Tool        | Minimum Version | Installation Link
------------|-----------------|--------------------------------------------------
kind        | Latest          | kind.sigs.k8s.io/docs/user/quick-start/
kubectl     | v1.24+          | kubernetes.io/docs/tasks/tools/
helm        | v3.8+           | helm.sh/docs/intro/install/
vault CLI   | Latest          | developer.hashicorp.com/vault/install
```

## Step-by-Step Setup

### Step 1: Create Kubernetes Clusters

We'll use Kind (Kubernetes in Docker) to create two clusters: a management cluster and a workload cluster.

**Cluster Configuration:**

```
Cluster   | Nodes                        | Purpose
----------|------------------------------|----------------------------------------
mgmt      | 1 control-plane, 1 worker   | Hosts Vault and ESO
workload1 | 1 control-plane, 1 worker   | Receives synced secrets
```

```bash
# Create mgmt cluster
kind create cluster --name mgmt --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker

# Create workload1 cluster
kind create cluster --name workload1 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
```

### Step 2: Install Vault on Management Cluster

Vault will serve as our centralized secrets store. We'll install it using Helm in dev mode for simplicity.

```bash
# Set context to mgmt cluster
kind get kubeconfig --name mgmt > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Create namespace
kubectl create namespace vault

# Add Helm repository
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

**Vault Installation Summary:**

```
Component   | Value
------------|----------------------------------------
Namespace   | vault
Mode        | Development (dev mode)
Root Token  | root
Service     | vault.vault.svc.cluster.local:8200
```

### Step 3: Install External Secrets Operator

ESO will handle syncing secrets from Vault to Kubernetes and pushing them to remote clusters.

```bash
# Create namespace
kubectl create namespace external-secrets

# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --wait
```

**ESO Installation Summary:**

```
Component     | Value
--------------|----------------------------------------
Namespace     | external-secrets
Release Name | external-secrets
Chart        | external-secrets/external-secrets
```

### Step 4: Configure Vault with Secrets

Now we'll add a username and password to Vault that we want to sync across clusters.

**Prerequisite: Install Vault CLI**

Before proceeding, ensure you have the Vault CLI installed on your local machine. Here are installation methods for different platforms:

**macOS (using Homebrew):**
```bash
brew install vault
```

**Linux:**
```bash
# Download and install
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

**Windows (using Chocolatey):**
```bash
choco install vault
```

**Or download directly:**
Visit [https://developer.hashicorp.com/vault/downloads](https://developer.hashicorp.com/vault/downloads) and download the appropriate binary for your platform.

**Verify installation:**
```bash
vault version
```

You should see output like: `Vault v1.x.x`

**Step 4a: Port Forward Vault Service**

First, we need to create a port forward from your local machine to the Vault service in the cluster:

```bash
# Port forward Vault service (runs in background)
kubectl port-forward -n vault svc/vault 8200:8200 &
```

This forwards local port 8200 to the Vault service in the cluster. The `&` runs it in the background.

**Step 4b: Configure Vault CLI**

Set environment variables so the Vault CLI knows how to connect:

```bash
# Set Vault address to use the local port forward
export VAULT_ADDR='http://127.0.0.1:8200'

# Set the root token (for dev mode)
export VAULT_TOKEN='root'

# Verify connection (optional - wait a moment for port forward to be ready)
sleep 2
vault status
```

**Step 4c: Configure Vault Secrets Engine and Add Secrets**

Now you can use the Vault CLI commands, which will automatically connect through the port forward:

```bash
# Enable KV secrets engine (version 2)
vault secrets enable -version=2 -path=secret kv

# Store credentials
vault kv put secret/app-credentials \
  username="admin" \
  password="SuperSecretPassword123!"

# Verify the secret was stored correctly
vault kv get secret/app-credentials

# List all secrets in the secret/ path
vault kv list secret/
```

The `vault kv get` command will show you the stored values, and `vault kv list` will show all secrets in that path.

**Important Notes:**
- The port forward must remain running while you use the Vault CLI
- All `vault` commands will use `VAULT_ADDR` to connect to `http://127.0.0.1:8200`
- The port forward redirects this to the Vault service in the cluster
- To stop the port forward, use: `pkill -f "port-forward.*vault"` or find the process and kill it

**Alternative: Using kubectl exec (No Port Forward Needed)**

Instead of port forwarding, you can also run Vault CLI commands directly inside the Vault pod:

```bash
# Run vault commands inside the pod
kubectl exec -n vault vault-0 -- vault secrets enable -version=2 -path=secret kv
kubectl exec -n vault vault-0 -- vault kv put secret/app-credentials \
  username="admin" \
  password="SuperSecretPassword123!"

# Verify the secret was stored
kubectl exec -n vault vault-0 -- vault kv get secret/app-credentials

# List all secrets
kubectl exec -n vault vault-0 -- vault kv list secret/
```

This method doesn't require port forwarding or setting environment variables, as the Vault CLI runs directly in the pod where Vault is accessible at `http://127.0.0.1:8200`.

**Vault Secret Structure:**

```
Path                      | Key      | Value
--------------------------|----------|----------------------------------------
secret/app-credentials    | username | admin
secret/app-credentials    | password | SuperSecretPassword123!
```

### Step 5: Create ExternalSecretStore

The ExternalSecretStore (or ClusterSecretStore) defines how ESO connects to Vault.

> **📄 YAML Files:** All YAML configurations are available in the [`yamls/` directory](https://github.com/deepak-muley/vault-eso-experiments/tree/main/yamls) of the repository.

First, create a secret containing the Vault root token:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: default
type: Opaque
stringData:
  token: "root"
```

Then create the ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: "vault-token"
          key: "token"
          namespace: "default"
```

**Store Configuration:**

```
Field    | Value                                          | Description
---------|------------------------------------------------|----------------------------------------
server   | http://vault.vault.svc.cluster.local:8200     | Vault service endpoint
path     | secret                                         | KV secrets engine path
version  | v2                                             | KV secrets engine version
auth     | tokenSecretRef                                 | Authentication method (dev mode)
```

**Note:** For production, use Kubernetes authentication instead of token-based auth.

### Step 6: Create ExternalSecret

The ExternalSecret resource tells ESO which secrets to fetch from Vault and how to create Kubernetes secrets.

> **📄 YAML File:** See [`yamls/external-secret.yaml`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/yamls/external-secret.yaml) in the repository.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: app-credentials
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        username: "{{ .username | b64enc }}"
        password: "{{ .password | b64enc }}"
  data:
  - secretKey: username
    remoteRef:
      key: secret/app-credentials
      property: username
  - secretKey: password
    remoteRef:
      key: secret/app-credentials
      property: password
```

**ExternalSecret Configuration:**

```
Field                      | Value                  | Description
---------------------------|------------------------|----------------------------------------
refreshInterval            | 1h                     | How often to sync from Vault
secretStoreRef             | vault-backend           | Reference to ClusterSecretStore
target.name                | app-credentials         | Name of Kubernetes secret to create
data[].remoteRef.key       | secret/app-credentials | Vault path
data[].remoteRef.property  | username/password       | Specific property to fetch
```

### Step 7: Create PushSecret

This is where the magic happens! PushSecret pushes the Kubernetes secret from the management cluster to the workload cluster without requiring ESO on the workload cluster.

> **📄 YAML File:** See [`yamls/push-secret.yaml`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/yamls/push-secret.yaml) in the repository.

**Important:** The Kubernetes provider doesn't support kubeconfig directly. We need to extract authentication components (server URL, CA cert, client cert, and key) from the kubeconfig.

First, prepare the kubeconfig and extract authentication info:

```bash
# Prepare kubeconfig with internal network IP (for kind clusters)
# Script available at: https://github.com/deepak-muley/vault-eso-experiments/blob/main/prepare-workload-kubeconfig.sh
./prepare-workload-kubeconfig.sh

# Extract authentication components (server URL, CA cert, client cert, key)
# Script available at: https://github.com/deepak-muley/vault-eso-experiments/blob/main/extract-kubeconfig-auth.sh
./extract-kubeconfig-auth.sh
```

This creates a secret `workload1-auth` with the authentication components.

Next, create a ClusterSecretStore for the remote Kubernetes cluster:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: kubernetes-remote-store
spec:
  provider:
    kubernetes:
      remoteNamespace: default
      server:
        url: "https://172.31.0.5:6443"  # Internal IP of workload cluster
        caProvider:
          type: Secret
          name: workload1-auth
          key: ca.crt
          namespace: default
      auth:
        cert:
          clientCert:
            name: workload1-auth
            key: client.crt
            namespace: default
          clientKey:
            name: workload1-auth
            key: client.key
            namespace: default
```

Then create the PushSecret:

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: app-credentials-push
  namespace: default
spec:
  refreshInterval: 1h
  deletionPolicy: Delete
  selector:
    secret:
      name: app-credentials
  data:
  - match:
      secretKey: username
      remoteRef:
        remoteKey: app-credentials
        property: username
  - match:
      secretKey: password
      remoteRef:
        remoteKey: app-credentials
        property: password
  secretStoreRefs:
  - name: kubernetes-remote-store
    kind: ClusterSecretStore
```

**PushSecret Configuration:**

```
Field                              | Value                  | Description
-----------------------------------|------------------------|----------------------------------------
selector.secret.name               | app-credentials        | Local secret to push
data[].match.secretKey             | username/password      | Key in local secret
data[].match.remoteRef.remoteKey   | app-credentials        | Name of secret in remote cluster
data[].match.remoteRef.property    | username/password      | Key name in remote secret
secretStoreRefs                    | kubernetes-remote-store| Reference to ClusterSecretStore
```

**Note:** For kind clusters, the server URL must use the internal Docker network IP, not localhost. Use [`prepare-workload-kubeconfig.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/prepare-workload-kubeconfig.sh) to update the kubeconfig accordingly.

**Automation:** The setup process can be automated using the provided scripts from the [repository](https://github.com/deepak-muley/vault-eso-experiments):
- [`prepare-workload-kubeconfig.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/prepare-workload-kubeconfig.sh) - Updates kubeconfig with internal IP
- [`extract-kubeconfig-auth.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/extract-kubeconfig-auth.sh) - Extracts authentication components
- [`create-kubernetes-store.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/create-kubernetes-store.sh) - Creates the ClusterSecretStore with proper configuration

Or use the complete setup script: [`setup.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/setup.sh) which handles all steps automatically.

## Verification

Let's verify that everything is working correctly.

### Check Vault and ESO Status

```bash
# Check Vault pods
kubectl get pods -n vault

# Check ESO pods
kubectl get pods -n external-secrets

# Check ExternalSecret status
kubectl get externalsecret app-credentials

# Check PushSecret status
kubectl get pushsecret app-credentials-push
```

### Verify Secrets in Management Cluster

```bash
# List secrets
kubectl get secret app-credentials

# Decode values
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d
```

### Verify Secrets in Workload Cluster

```bash
# Switch to workload1 context
kind get kubeconfig --name workload1 > /tmp/w1-kubeconfig
export KUBECONFIG=/tmp/w1-kubeconfig

# List secrets
kubectl get secret app-credentials

# Decode values
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d
```

## Expected Results

After successful setup, you should see:

**Management Cluster:**
- Vault pod running in `vault` namespace
- ESO pods running in `external-secrets` namespace
- ExternalSecret `app-credentials` with status `Synced`
- PushSecret `app-credentials-push` with status `Synced`
- Kubernetes secret `app-credentials` with username and password

**Workload Cluster:**
- Kubernetes secret `app-credentials` with username and password (synced from mgmt)

## Key Benefits

```
Benefit                | Description
-----------------------|----------------------------------------
Centralized Management | All secrets managed in one place (Vault)
Automatic Sync         | Secrets automatically synced to Kubernetes
Multi-Cluster Support  | Push secrets to multiple clusters without installing ESO on each
No Workload Overhead   | Workload clusters don't need ESO installed
Declarative            | All configuration via YAML manifests
GitOps Friendly        | Can be managed with GitOps tools
```

## Production Considerations

⚠️ **Important:** The setup above is for development/testing only. For production:

```
Consideration          | Recommendation
-----------------------|----------------------------------------
Vault Authentication   | Use Kubernetes auth method instead of root token
TLS                    | Enable TLS for Vault communication
RBAC                   | Implement proper Role-Based Access Control
Kubeconfig Security    | Use sealed secrets or external secret management for kubeconfig
Audit Logging          | Enable Vault audit logging
High Availability      | Deploy Vault in HA mode with proper storage backend
Network Policies       | Implement network policies for cluster communication
Secret Rotation        | Implement secret rotation policies
```

## Troubleshooting Guide

### Common Issues and Solutions

```
Issue                           | Symptoms                                    | Solution
--------------------------------|---------------------------------------------|----------------------------------------
Vault not accessible            | Connection refused errors                   | Check Vault pod status and service
ExternalSecret not syncing     | Status shows Error                          | Check ESO logs and Vault connectivity
PushSecret not syncing         | Secret not appearing in workload cluster    | Verify ClusterSecretStore and authentication secrets
PushSecret error: requires property | Error message about property in RemoteRef | Add property field to remoteRef when using secretKey
Authentication failed          | Cannot connect to remote cluster            | Verify server URL uses internal IP (not localhost) and auth secrets are correct
Permission denied              | Authentication errors                       | Check service account permissions and Vault policies
```

### Debug Commands

```bash
# Check Vault logs
kubectl logs -n vault -l app.kubernetes.io/name=vault

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Describe ExternalSecret for events
kubectl describe externalsecret app-credentials

# Describe PushSecret for events
kubectl describe pushsecret app-credentials-push

# Test Vault connectivity
kubectl exec -n vault -it vault-0 -- vault status
```

## Conclusion

This setup demonstrates a powerful pattern for managing secrets across multiple Kubernetes clusters:

1. **Centralize** secrets in Vault
2. **Sync** to Kubernetes using External Secrets Operator
3. **Push** to remote clusters using PushSecret

The key advantage is that workload clusters receive secrets without needing to install and configure secret management tools, reducing operational complexity while maintaining security.

## Resources

- **[Complete Code Repository](https://github.com/deepak-muley/vault-eso-experiments)** - All scripts, YAML files, and configurations used in this guide
  - [`setup.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/setup.sh) - Complete automated setup script
  - [`bootstrap-vault.sh`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/bootstrap-vault.sh) - Vault secrets bootstrap script
  - [`yamls/`](https://github.com/deepak-muley/vault-eso-experiments/tree/main/yamls) - All YAML configuration files
  - [`README.md`](https://github.com/deepak-muley/vault-eso-experiments/blob/main/README.md) - Detailed setup instructions
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [PushSecret API Reference](https://external-secrets.io/latest/api/pushsecret/)
- [Kind Documentation](https://kind.sigs.k8s.io/docs/)

## Next Steps

- Explore Vault's Kubernetes authentication method
- Implement secret rotation policies
- Set up monitoring and alerting for secret sync failures
- Integrate with GitOps workflows (ArgoCD, Flux)
- Explore other ESO providers (AWS Secrets Manager, Azure Key Vault, etc.)

---

*This guide provides a foundation for multi-cluster secret management. Adapt the configurations to your specific security and operational requirements.*

