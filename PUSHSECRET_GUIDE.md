# PushSecret Configuration Guide for Kind Clusters

This guide explains how to configure PushSecret to push secrets from one kind cluster to another.

## Overview

PushSecret uses the Kubernetes provider in a ClusterSecretStore to push secrets to remote Kubernetes clusters. The key components are:

1. **ClusterSecretStore** - Defines the connection to the remote cluster using Kubernetes provider
2. **PushSecret** - Defines which secret to push and where to push it

## Step-by-Step Configuration

### 1. Prepare the Remote Cluster Kubeconfig

For kind clusters, the kubeconfig contains a localhost server URL that won't work from within the cluster. You need to update it to use the internal network address.

```bash
# Get the workload cluster's control plane IP in the Docker network
WORKLOAD_CP_IP=$(docker inspect workload1-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

# Update the kubeconfig to use the internal IP
kind get kubeconfig --name workload1 > /tmp/workload1-kubeconfig-raw
sed "s|server:.*|server: https://${WORKLOAD_CP_IP}:6443|g" /tmp/workload1-kubeconfig-raw > /tmp/workload1-kubeconfig
```

Or use the provided script:
```bash
./prepare-workload-kubeconfig.sh
```

### 2. Create Kubeconfig Secret in Management Cluster

```bash
kubectl create secret generic workload1-kubeconfig \
  --from-file=config=/tmp/workload1-kubeconfig \
  --namespace default
```

### 3. Create ClusterSecretStore with Kubernetes Provider

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: kubernetes-remote-store
spec:
  provider:
    kubernetes:
      remoteNamespace: default  # Target namespace in remote cluster
      auth:
        kubeconfig:
          secretRef:
            name: workload1-kubeconfig
            key: config
            namespace: default
```

**Key Fields:**
- `remoteNamespace`: The namespace in the target cluster where secrets will be created
- `auth.kubeconfig.secretRef`: Reference to the secret containing the remote cluster's kubeconfig

### 4. Create PushSecret Resource

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: app-credentials-push
  namespace: default
spec:
  refreshInterval: 1h
  deletionPolicy: Delete  # Or Retain
  selector:
    secret:
      name: app-credentials  # Local secret to push
  data:
  - match:
      secretKey: username    # Key in local secret
    metadata:
      remoteRef:
        remoteKey: username  # Key name in remote secret
  - match:
      secretKey: password
    metadata:
      remoteRef:
        remoteKey: password
  secretStoreRefs:
  - name: kubernetes-remote-store
    kind: ClusterSecretStore
```

**Key Fields:**
- `selector.secret.name`: Name of the local Kubernetes secret to push
- `data[].match.secretKey`: Key in the local secret to push
- `data[].metadata.remoteRef.remoteKey`: Key name in the remote secret
- `secretStoreRefs`: Reference to the ClusterSecretStore

### 5. Verify PushSecret Status

```bash
# Check PushSecret status
kubectl get pushsecret app-credentials-push

# Describe for detailed status
kubectl describe pushsecret app-credentials-push

# Check if secret exists in remote cluster
kind get kubeconfig --name workload1 > /tmp/w1-kubeconfig
export KUBECONFIG=/tmp/w1-kubeconfig
kubectl get secret app-credentials
```

## Troubleshooting

### PushSecret Not Syncing

1. **Check PushSecret status:**
   ```bash
   kubectl describe pushsecret app-credentials-push
   ```

2. **Check ESO logs:**
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```

3. **Verify kubeconfig is valid:**
   ```bash
   kubectl get secret workload1-kubeconfig -o jsonpath='{.data.config}' | base64 -d > /tmp/check-kubeconfig
   export KUBECONFIG=/tmp/check-kubeconfig
   kubectl get nodes
   ```

4. **Verify network connectivity:**
   - Ensure the mgmt cluster can reach the workload cluster's API server
   - For kind clusters, they should be on the same Docker network

### Common Issues

| Issue | Solution |
|-------|----------|
| Cannot connect to remote API server | Update kubeconfig to use internal IP instead of localhost |
| Authentication failed | Verify kubeconfig secret is correct and accessible |
| Secret not created in remote cluster | Check remoteNamespace and RBAC permissions |
| PushSecret stuck in Pending | Check ESO logs for errors |

## Alternative: Using kubectl Sync

If PushSecret doesn't work for your use case, you can use the alternative sync script:

```bash
./sync-secret-to-workload.sh
```

This script uses kubectl to directly sync secrets between clusters.

## Production Considerations

For production environments:

1. **Use Service Account Authentication**: Instead of kubeconfig, use service accounts with proper RBAC
2. **TLS Verification**: Ensure proper TLS certificates are configured
3. **Network Policies**: Configure network policies to allow cluster-to-cluster communication
4. **Secret Encryption**: Use sealed secrets or encryption at rest for kubeconfig secrets
5. **Monitoring**: Set up alerts for PushSecret sync failures

## References

- [External Secrets Operator PushSecret Documentation](https://external-secrets.io/latest/api/pushsecret/)
- [Kubernetes Provider Documentation](https://external-secrets.io/latest/provider/kubernetes/)

