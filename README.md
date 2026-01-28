# Keycloak Helm Chart

Keycloak Helm chart with CloudNativePG (CNPG) PostgreSQL database and MCP server integration for Kubernetes.

## Features

- **Keycloak** - Modern identity and access management solution
- **CloudNativePG Database** - Managed PostgreSQL using CNPG operator
- **MCP Server Sidecar** - Keycloak MCP server for AI/LLM integration
- **High Availability** - StatefulSet with clustering support
- **Ingress** - TLS-enabled ingress with cert-manager
- **Prometheus Metrics** - ServiceMonitor for Prometheus Operator
- **Security** - Non-root containers, security contexts, and secrets management

## Prerequisites

- Kubernetes 1.19+
- Helm 3.8+
- CloudNativePG Operator installed
- NGINX Ingress Controller
- cert-manager (optional, for TLS)
- Prometheus Operator (optional, for metrics)

## Installation

### Quick Start

```bash
# Install with default values
helm install keycloak oci://ghcr.io/bclermont/keycloak-chart

# Install with custom values
helm install keycloak oci://ghcr.io/bclermont/keycloak-chart \
  --set ingress.hosts[0].host=keycloak.example.com \
  --set ingress.tls[0].hosts[0]=keycloak.example.com
```

### Configuration

Key configuration options:

```yaml
# Admin credentials
admin:
  username: admin
  password: ""  # Auto-generated if empty

# Database configuration
database:
  enabled: true
  cnpg:
    instances: 3
    storage:
      size: 10Gi
      storageClass: longhorn

# MCP Server sidecar
mcpServer:
  enabled: true
  port: 8081

# Ingress
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: keycloak.example.com
      paths:
        - path: /
          pathType: Prefix

# Prometheus metrics
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
```

See [values.yaml](values.yaml) for all configuration options.

## Components

### Keycloak

The chart deploys Keycloak as a StatefulSet with:
- High availability clustering via JGroups
- Health, readiness, and startup probes
- Configurable resource limits
- PostgreSQL database backend

### CloudNativePG Database

Uses the CNPG operator to provision a PostgreSQL cluster:
- Multi-instance for high availability
- Automatic failover
- Backup support (configurable)
- Dedicated database and user for Keycloak

### MCP Server Sidecar

Optional sidecar container providing MCP (Model Context Protocol) server:
- Exposes Keycloak admin API via MCP
- Pre-configured to connect to local Keycloak
- Accessible on port 8081 by default
- Based on https://github.com/sshaaf/keycloak-mcp-server

### Prometheus Monitoring

When enabled, creates a ServiceMonitor for Prometheus Operator:
- Scrapes `/metrics` endpoint
- Configurable scrape interval
- Keycloak exposes various JVM and application metrics

## Accessing Keycloak

After installation:

1. **Get admin password:**
   ```bash
   kubectl get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d
   ```

2. **Access via ingress:**
   ```
   https://keycloak.example.com
   ```

3. **Access MCP server (if enabled):**
   ```bash
   kubectl port-forward svc/keycloak 8081:8081
   # MCP server available at http://localhost:8081
   ```

## Database Management

The chart creates a CNPG Database resource that references a PostgreSQL cluster named `postgresql` in the `database` namespace. Ensure this cluster exists:

```bash
# Check CNPG cluster
kubectl get cluster -n database postgresql

# Check database status
kubectl get database keycloak-db
```

## Monitoring

Access Keycloak metrics:

```bash
# Port-forward to access metrics
kubectl port-forward svc/keycloak 8080:8080

# View metrics
curl http://localhost:8080/metrics
```

Metrics are automatically scraped by Prometheus if ServiceMonitor is enabled.

## Upgrading

```bash
helm upgrade keycloak oci://ghcr.io/bclermont/keycloak-chart \
  --reuse-values \
  --set image.tag=26.0.5
```

## Uninstalling

```bash
helm uninstall keycloak
```

**Note:** The CNPG database will persist. To delete:

```bash
kubectl delete database keycloak-db
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Keycloak replicas | `2` |
| `image.repository` | Keycloak image repository | `quay.io/keycloak/keycloak` |
| `image.tag` | Keycloak image tag | `26.0.5` |
| `admin.username` | Admin username | `admin` |
| `admin.password` | Admin password (auto-generated if empty) | `""` |
| `database.enabled` | Enable CNPG database | `true` |
| `database.cnpg.instances` | Number of PostgreSQL instances | `3` |
| `database.cnpg.storage.size` | Database storage size | `10Gi` |
| `mcpServer.enabled` | Enable MCP server sidecar | `true` |
| `mcpServer.port` | MCP server port | `8081` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `nginx` |
| `monitoring.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `true` |

See [values.yaml](values.yaml) for complete parameter list.

## Architecture

```
┌─────────────────────────────────────┐
│         Ingress (TLS)               │
│    keycloak.example.com             │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│     Keycloak Service                │
│       (ClusterIP)                   │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│    Keycloak StatefulSet             │
│  ┌───────────────────────────────┐  │
│  │  Keycloak Container           │  │
│  │  - Port 8080 (HTTP)           │  │
│  │  - Port 9000 (Health)         │  │
│  │  - Metrics enabled            │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  MCP Server Container         │  │
│  │  - Port 8081                  │  │
│  │  - Connects to localhost:8080 │  │
│  └───────────────────────────────┘  │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│   CloudNativePG PostgreSQL          │
│   - 3 instances (HA)                │
│   - Auto-failover                   │
│   - Dedicated database: keycloak    │
└─────────────────────────────────────┘
```

## Troubleshooting

### Database connection issues

Check database status:
```bash
kubectl get database keycloak-db
kubectl logs statefulset/keycloak -c keycloak
```

### Cluster not forming

Verify headless service:
```bash
kubectl get svc keycloak-headless
kubectl exec keycloak-0 -- nslookup keycloak-headless
```

### MCP server not responding

Check sidecar logs:
```bash
kubectl logs statefulset/keycloak -c mcp-server
```

## License

This chart is provided as-is. Keycloak is licensed under Apache License 2.0.

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Keycloak MCP Server](https://github.com/sshaaf/keycloak-mcp-server)
