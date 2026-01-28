# MCP Server Integration

The Keycloak Helm chart includes an integrated MCP (Model Context Protocol) server as a mandatory sidecar container, enabling AI/LLM integration with Keycloak.

## Overview

The MCP server runs alongside Keycloak in the same pod, providing:
- Direct access to Keycloak admin API
- AI-friendly interface for managing users, roles, realms, etc.
- Pre-configured connection to local Keycloak instance
- Exposed via the same ingress as Keycloak

## Configuration

### Basic Setup

The MCP server is **mandatory** and always deployed. Configuration:

```yaml
mcpServer:
  image:
    repository: quay.io/sshaaf/keycloak-mcp-server
    tag: "latest"
  port: 8081
  path: /mcp  # URL path where MCP is exposed
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
```

### Ingress Integration

The MCP server is automatically exposed via the main Keycloak ingress:

**Keycloak Admin Console**: `https://id.example.com/`
**MCP Server**: `https://id.example.com/mcp`

The ingress is configured to route:
- `/mcp` → MCP server (port 8081)
- `/` → Keycloak (port 8080)

### Authentication (Optional)

Basic authentication can be enabled for the MCP endpoint:

```yaml
mcpServer:
  auth:
    enabled: true
    username: mcp
    password: ""  # Auto-generated if empty
```

When enabled:
- Creates a secret: `keycloak-mcp-auth`
- Requires HTTP Basic auth to access `/mcp`
- Username and password stored in secret

**Get credentials:**
```bash
kubectl get secret keycloak-mcp-auth -n oidc \
  -o jsonpath='{.data.username}' | base64 -d
kubectl get secret keycloak-mcp-auth -n oidc \
  -o jsonpath='{.data.password}' | base64 -d
```

## Accessing the MCP Server

### Via Ingress (Recommended)

```bash
# Without auth
curl https://id.example.com/mcp

# With auth
curl -u mcp:password https://id.example.com/mcp
```

### Via Port Forward

```bash
kubectl port-forward svc/keycloak -n oidc 8081:8081
curl http://localhost:8081
```

## MCP Client Configuration

Configure your MCP client to use the Keycloak MCP server:

### Without Authentication

```json
{
  "mcpServers": {
    "keycloak": {
      "type": "sse",
      "url": "https://id.example.com/mcp/sse"
    }
  }
}
```

### With Authentication

```json
{
  "mcpServers": {
    "keycloak": {
      "type": "sse",
      "url": "https://id.example.com/mcp/sse",
      "headers": {
        "Authorization": "Basic <base64-encoded-credentials>"
      }
    }
  }
}
```

## Environment Variables

The MCP server sidecar is pre-configured with:

```yaml
env:
  - name: KC_URL
    value: "http://localhost:8080"
  - name: KC_REALM
    value: "master"
  - name: OIDC_CLIENT_ID
    value: "mcp-server"
  - name: QUARKUS_HTTP_PORT
    value: "8081"
```

These connect the MCP server to the local Keycloak instance.

## Path Configuration

The MCP server path can be customized:

```yaml
mcpServer:
  path: /api/mcp  # Custom path
```

**Important**: The path must start with `/` and should not conflict with Keycloak paths.

## Security Considerations

1. **Same Pod Access**: MCP server and Keycloak share the same pod, so MCP has localhost access to Keycloak
2. **Ingress Routing**: Both services exposed through same ingress host
3. **Optional Auth**: Basic auth can protect the MCP endpoint
4. **TLS**: Traffic to MCP is encrypted via ingress TLS

## Troubleshooting

### MCP Server Not Responding

Check sidecar logs:
```bash
kubectl logs deployment/keycloak -c mcp-server -n oidc
```

### Path Conflicts

Ensure MCP path doesn't conflict with Keycloak:
- ❌ Bad: `/admin`, `/realms`, `/auth` (Keycloak paths)
- ✅ Good: `/mcp`, `/api/mcp`, `/mcp-server`

### Authentication Issues

Verify auth secret exists:
```bash
kubectl get secret keycloak-mcp-auth -n oidc
```

Test without auth first:
```bash
kubectl port-forward svc/keycloak -n oidc 8081:8081
curl http://localhost:8081  # Bypasses ingress auth
```

## Architecture

```
┌─────────────────────────────────────┐
│         Ingress (TLS)               │
│    id.example.com                   │
└─────────────┬───────────────────────┘
              │
    ┌─────────┴─────────┐
    │         │         │
    │ /mcp    │   /     │
    │         │         │
    ▼         ▼         │
┌───────────────────────┴─────────┐
│   Pod: keycloak                 │
│  ┌──────────────────────────┐   │
│  │ Container: mcp-server    │   │
│  │ Port: 8081               │   │
│  │ Path: /                  │   │
│  └──────────────────────────┘   │
│  ┌──────────────────────────┐   │
│  │ Container: keycloak      │   │
│  │ Port: 8080               │   │
│  │ Path: /                  │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

## References

- [Keycloak MCP Server](https://github.com/sshaaf/keycloak-mcp-server)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
