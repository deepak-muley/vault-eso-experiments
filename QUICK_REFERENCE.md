# Quick Reference Guide

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup.sh` | Complete setup automation | `./setup.sh` |
| `verify.sh` | Verify installation and secrets | `./verify.sh` |
| `cleanup.sh` | Delete all kind clusters | `./cleanup.sh` |

## YAML Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `yamls/external-secret-store.yaml` | Defines Vault connection | Applied after Vault installation |
| `yamls/external-secret.yaml` | Fetches secrets from Vault | Applied after SecretStore |
| `yamls/push-secret.yaml` | Pushes secrets to workload cluster | Applied after ExternalSecret syncs |
| `yamls/kind-cluster-configs.yaml` | Kind cluster configurations | Reference for manual cluster creation |
| `yamls/vault-service.yaml` | Vault service (reference) | Documentation only |

## Common Commands

### Cluster Management

```bash
# List clusters
kind get clusters

# Get kubeconfig
kind get kubeconfig --name Mgmt > /tmp/mgmt-kubeconfig
export KUBECONFIG=/tmp/mgmt-kubeconfig

# Switch context
kubectl config use-context kind-Mgmt
```

### Vault Operations

```bash
# Port forward
kubectl port-forward -n vault svc/vault 8200:8200

# Set environment
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# List secrets
vault kv list secret/

# Get secret
vault kv get secret/app-credentials

# Put secret
vault kv put secret/app-credentials username=admin password=secret
```

### ESO Operations

```bash
# Check ExternalSecret status
kubectl get externalsecret

# Check PushSecret status
kubectl get pushsecret

# Describe for events
kubectl describe externalsecret app-credentials
kubectl describe pushsecret app-credentials-push

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Secret Operations

```bash
# Get secret
kubectl get secret app-credentials

# Decode values
kubectl get secret app-credentials -o jsonpath='{.data.username}' | base64 -d
kubectl get secret app-credentials -o jsonpath='{.data.password}' | base64 -d

# Get full YAML
kubectl get secret app-credentials -o yaml
```

## Troubleshooting

| Issue | Command |
|-------|---------|
| Vault not ready | `kubectl get pods -n vault` |
| ESO not ready | `kubectl get pods -n external-secrets` |
| ExternalSecret error | `kubectl describe externalsecret app-credentials` |
| PushSecret error | `kubectl describe pushsecret app-credentials-push` |
| Check Vault logs | `kubectl logs -n vault -l app.kubernetes.io/name=vault` |
| Check ESO logs | `kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets` |

## Resource Names

| Resource | Name | Namespace |
|----------|------|-----------|
| Vault | `vault` | `vault` |
| ESO | `external-secrets` | `external-secrets` |
| ClusterSecretStore | `vault-backend` | - |
| ExternalSecret | `app-credentials` | `default` |
| PushSecret | `app-credentials-push` | `default` |
| Kubernetes Secret (Mgmt) | `app-credentials` | `default` |
| Kubernetes Secret (workload1) | `app-credentials` | `default` |
| Vault Token Secret | `vault-token` | `default` |
| Workload Kubeconfig Secret | `workload1-kubeconfig` | `default` |

## Vault Paths

| Path | Purpose |
|------|---------|
| `secret/app-credentials` | Stores username and password |
| `secret/` | KV secrets engine path (v2) |

## Cluster Names

| Cluster | Purpose |
|---------|---------|
| `Mgmt` | Management cluster with Vault and ESO |
| `workload1` | Workload cluster receiving synced secrets |

