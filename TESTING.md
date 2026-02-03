# Testing Guide for Keycloak Chart

This guide explains how to test the Keycloak Helm chart with external database infrastructure.

## Prerequisites

The chart assumes database infrastructure is managed separately. The following resources must exist **before** installing the chart:

### 1. Database Namespace

The `database` namespace must exist:
```bash
kubectl get namespace database
```

### 2. CNPG PostgreSQL Cluster

A CNPG Cluster with a managed role for Keycloak:
```bash
kubectl get cluster -n database postgresql
```

The cluster must have this managed role configured:
```yaml
managed:
  roles:
  - name: keycloak
    ensure: present
    login: true
    passwordSecret:
      name: keycloak-db-credentials
```

## Test Deployment

### Step 1: Create Database Infrastructure

Create the database infrastructure resources in the `database` namespace:

```bash
cat <<EOF | kubectl apply -f -
---
# Secret for CNPG to read (in database namespace)
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-test-db-credentials
  namespace: database
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/instance: keycloak-test
    cnpg.io/reload: "true"
type: kubernetes.io/basic-auth
stringData:
  username: keycloak
  password: test-password-12345
---
# Database CRD for CNPG to create the database
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: keycloak-test-db
  namespace: database
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/instance: keycloak-test
spec:
  name: keycloak
  cluster:
    name: postgresql
  owner: keycloak
  ensure: present
EOF
```

### Step 2: Verify Infrastructure

Wait for CNPG to create the database and sync the password:

```bash
# Check database status
kubectl get database -n database keycloak-test-db

# Verify the database was created
kubectl exec -n database postgresql-1 -- psql -U postgres -c "\l" | grep keycloak

# Verify the user was created
kubectl exec -n database postgresql-1 -- psql -U postgres -c "\du" | grep keycloak
```

### Step 3: Deploy the Chart

Create test values file:

```bash
cat > /tmp/test-values.yaml <<EOF
replicaCount: 1

database:
  enabled: true
  host: postgresql-rw.database.svc.cluster.local
  password: test-password-12345  # Must match infrastructure secret

ingress:
  enabled: true
  hosts:
    - host: keycloak-test.local
      paths:
        - path: /
          pathType: Prefix

mcpServer:
  oidcClient:
    enabled: true

monitoring:
  enabled: false
  serviceMonitor:
    enabled: false
  prometheusRule:
    enabled: false
EOF
```

Deploy the chart:

```bash
# Install from local directory
helm install keycloak-test /workspace/keycloak-chart \
  --namespace oidc \
  -f /tmp/test-values.yaml

# OR install from OCI registry (after release)
helm install keycloak-test oci://ghcr.io/robotinfra/keycloak \
  --namespace oidc \
  -f /tmp/test-values.yaml
```

### Step 4: Verify Deployment

Check pod status:
```bash
kubectl get pods -n oidc -l app.kubernetes.io/name=keycloak
```

Check logs:
```bash
kubectl logs -n oidc deployment/keycloak-test -c keycloak --tail 50
```

Verify database connection:
```bash
kubectl logs -n oidc deployment/keycloak-test -c keycloak | grep -i "database connection"
```

### Step 5: Test OIDC Client Creation

Check OIDC client setup job:
```bash
kubectl get job -n oidc keycloak-test-oidc-client
kubectl logs -n oidc job/keycloak-test-oidc-client
```

Get OIDC client credentials:
```bash
# Client ID
kubectl get secret keycloak-test-mcp-oidc-client \
  -n oidc \
  -o jsonpath='{.data.clientId}' | base64 -d && echo

# Client Secret
kubectl get secret keycloak-test-mcp-oidc-client \
  -n oidc \
  -o jsonpath='{.data.clientSecret}' | base64 -d && echo
```

### Step 6: Test Login

Get admin credentials:
```bash
kubectl get secret keycloak-test-admin \
  -n oidc \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Port-forward and test:
```bash
kubectl port-forward -n oidc svc/keycloak-test 8080:8080

# Open browser to http://localhost:8080
# Login with username: admin and password from above
```

## Cleanup

```bash
# Delete Helm release
helm uninstall keycloak-test -n oidc

# Delete database infrastructure
kubectl delete database -n database keycloak-test-db
kubectl delete secret -n database keycloak-test-db-credentials
```

## Troubleshooting

### Database Connection Fails

Check if the password in the chart matches the infrastructure secret:
```bash
# Chart secret (in release namespace)
kubectl get secret keycloak-test-db-credentials \
  -n oidc \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Infrastructure secret (in database namespace)
kubectl get secret keycloak-test-db-credentials \
  -n database \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

### OIDC Client Creation Fails

Check job logs:
```bash
kubectl logs -n oidc job/keycloak-test-oidc-client
```

Common issues:
- Keycloak not ready: Job waits up to 10 minutes
- Authentication failure: Check admin credentials
- Client already exists: Job updates existing client

### Pod CrashLoopBackOff

Check startup probe:
```bash
kubectl describe pod -n oidc -l app.kubernetes.io/name=keycloak
kubectl logs -n oidc deployment/keycloak-test -c keycloak
```

Common issues:
- Database connection timeout
- Invalid credentials
- Database not created yet

## Architecture

```
┌─────────────────────────────────────┐
│      Application Namespace          │
│           (oidc)                    │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  Keycloak Deployment          │ │
│  │  - Reads: keycloak-db-        │ │
│  │    credentials secret         │ │
│  └───────────────────────────────┘ │
│  ┌───────────────────────────────┐ │
│  │  OIDC Client Setup Job        │ │
│  │  - Creates mcp-server client  │ │
│  └───────────────────────────────┘ │
└─────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      Database Namespace             │
│          (database)                 │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  CNPG Cluster                 │ │
│  │  - Watches: keycloak-db-      │ │
│  │    credentials secret         │ │
│  │  - Syncs password to PG user  │ │
│  └───────────────────────────────┘ │
│  ┌───────────────────────────────┐ │
│  │  Database CRD                 │ │
│  │  - Creates keycloak database  │ │
│  └───────────────────────────────┘ │
└─────────────────────────────────────┘
```

## Production Deployment

For production, ensure:

1. **Generate strong password** and use it in both secrets
2. **Update CNPG managed role** to reference the secret
3. **Install chart** with matching password
4. **Configure TLS** with cert-manager
5. **Enable monitoring** with Prometheus

Example production values:

```yaml
replicaCount: 2

admin:
  password: ""  # Auto-generated

database:
  host: postgresql-rw.database.svc.cluster.local
  password: ""  # Auto-generated, sync manually to infrastructure

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: keycloak.example.com
      paths:
        - path: /
          pathType: Prefix
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

mcpServer:
  oidcClient:
    enabled: true

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
  prometheusRule:
    enabled: true
```
