# Keycloak Chart - Chart Maintenance

## Purpose

Production-ready Keycloak Helm chart with CloudNativePG database integration,
MCP server sidecar, and comprehensive Prometheus metrics support.

## Chart Maintenance

### Testing Changes

```bash
# Lint chart
helm lint .

# Test template rendering
helm template keycloak . --debug

# Test with custom values
helm template keycloak . \
  --set ingress.hosts[0].host=keycloak.example.com \
  --set database.cnpg.instances=1

# Verify rendering
helm upgrade --install keycloak . --dry-run --debug
```

### Creating Pull Requests

1. Make changes to templates or values
2. Update `Chart.yaml` version if needed
3. Run `helm lint .` to validate
4. Test template rendering
5. Commit changes
6. Create PR: `gh pr create`
7. Wait for CI to pass

### Release Process

1. Create and push a version tag:
   ```bash
   git tag -a v0.2.0 -m "Release v0.2.0"
   git push origin v0.2.0
   ```

2. GitHub Actions will automatically:
   - Lint the chart
   - Update Chart.yaml version to match tag
   - Package the Helm chart
   - Push to GHCR: `oci://ghcr.io/bclermont/keycloak`
   - Create GitHub release

## Chart Structure

- `templates/` - Kubernetes manifests
  - `statefulset.yaml` - Keycloak + MCP server sidecar
  - `service.yaml` - ClusterIP and headless services
  - `ingress.yaml` - NGINX ingress with TLS
  - `database.yaml` - CNPG Database CRD
  - `servicemonitor.yaml` - Prometheus ServiceMonitor
  - `secret.yaml` - Admin credentials
  - `_helpers.tpl` - Template helpers
  - `NOTES.txt` - Post-install instructions
- `Chart.yaml` - Chart metadata and version
- `values.yaml` - Default configuration
- `docs/METRICS.md` - Prometheus metrics documentation
- `.github/workflows/ci.yaml` - Comprehensive CI/CD workflow
- `.github/dependabot.yaml` - Automated dependency updates

## Features

- **High Availability**: StatefulSet with JGroups clustering
- **Database**: CloudNativePG PostgreSQL integration
- **MCP Server**: AI/LLM integration via sidecar
- **Monitoring**: Prometheus metrics and ServiceMonitor
- **Security**: Non-root containers, auto-generated secrets
- **Ingress**: TLS-enabled ingress with cert-manager

## Configuration

Key values to customize:

```yaml
# Ingress
ingress:
  hosts:
    - host: keycloak.example.com

# Database
database:
  cnpg:
    instances: 3
    storage:
      size: 10Gi

# MCP Server
mcpServer:
  enabled: true

# Monitoring
monitoring:
  serviceMonitor:
    enabled: true
```

## Repository

<https://github.com/bclermont/keycloak-chart>
