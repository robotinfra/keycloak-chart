#!/bin/bash
# Keycloak Post-Install Setup Script
# Automates database password sync and OIDC client creation
#
# Usage: ./post-install.sh [namespace] [cluster-context]
# Example: ./post-install.sh oidc cc

set -e

NAMESPACE="${1:-oidc}"
CONTEXT="${2:-cc}"
DB_NAMESPACE="database"

echo "=== Keycloak Post-Install Setup ==="
echo "Namespace: $NAMESPACE"
echo "Context: $CONTEXT"
echo ""

# Switch to correct context
kubectl config use-context "$CONTEXT"

# Wait for secrets to be created
echo "1. Waiting for secrets to be created..."
until kubectl get secret -n "$NAMESPACE" keycloak-admin &>/dev/null && \
      kubectl get secret -n "$NAMESPACE" keycloak-db-credentials &>/dev/null; do
    echo "   Waiting for secrets..."
    sleep 5
done
echo "   ✓ Secrets found"

# Get passwords
echo ""
echo "2. Reading credentials from secrets..."
ADMIN_PASS=$(kubectl get secret -n "$NAMESPACE" keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
DB_USER=$(kubectl get secret -n "$NAMESPACE" keycloak-db-credentials -o jsonpath='{.data.username}' | base64 -d)
DB_PASS=$(kubectl get secret -n "$NAMESPACE" keycloak-db-credentials -o jsonpath='{.data.password}' | base64 -d)
echo "   ✓ Credentials retrieved"

# Update PostgreSQL user password
echo ""
echo "3. Syncing database password..."
kubectl exec -n "$DB_NAMESPACE" postgresql-1 -- psql -U postgres -c \
  "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" &>/dev/null
echo "   ✓ Database password synchronized"

# Wait for Keycloak pod to be ready
echo ""
echo "4. Waiting for Keycloak pod..."
kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak --timeout=300s
POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "   ✓ Pod ready: $POD_NAME"

# Wait for Keycloak to be fully started
echo ""
echo "5. Waiting for Keycloak to be ready..."
until kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- curl -sf http://localhost:8080/health/ready &>/dev/null; do
    echo "   Waiting for Keycloak health check..."
    sleep 5
done
echo "   ✓ Keycloak is ready"

# Configure kcadm.sh
echo ""
echo "6. Configuring Keycloak admin CLI..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master \
  --user admin --password "$ADMIN_PASS" &>/dev/null
echo "   ✓ Admin CLI configured"

# Check if mcp-server client exists
echo ""
echo "7. Checking for OIDC client..."
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
   /opt/keycloak/bin/kcadm.sh get clients -r master --fields clientId 2>/dev/null | grep -q "\"mcp-server\""; then
    echo "   ✓ OIDC client 'mcp-server' already exists"

    # Get client UUID
    CLIENT_UUID=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
      /opt/keycloak/bin/kcadm.sh get clients -r master -q clientId=mcp-server --fields id 2>/dev/null | \
      grep -o '"id" : "[^"]*"' | cut -d'"' -f4)

    if [ -n "$CLIENT_UUID" ]; then
        # Get client secret
        CLIENT_SECRET=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
          /opt/keycloak/bin/kcadm.sh get "clients/$CLIENT_UUID/client-secret" -r master 2>/dev/null | \
          grep -o '"value" : "[^"]*"' | cut -d'"' -f4)

        echo "   Client UUID: $CLIENT_UUID"
        echo "   Client Secret: $CLIENT_SECRET"
    fi
else
    echo "   Creating OIDC client 'mcp-server'..."

    # Get ingress hostname
    INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].spec.rules[0].host}')
    if [ -z "$INGRESS_HOST" ]; then
        INGRESS_HOST="id.robotinfra.com"
        echo "   Warning: Could not detect ingress host, using default: $INGRESS_HOST"
    else
        echo "   Using ingress host: $INGRESS_HOST"
    fi

    # Create client
    CLIENT_UUID=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
      /opt/keycloak/bin/kcadm.sh create clients -r master \
      -s clientId=mcp-server \
      -s 'name=MCP Server' \
      -s 'description=OIDC client for MCP server authentication' \
      -s enabled=true \
      -s clientAuthenticatorType=client-secret \
      -s "redirectUris=[\"https://$INGRESS_HOST/mcp/*\"]" \
      -s "webOrigins=[\"https://$INGRESS_HOST\"]" \
      -s publicClient=false \
      -s directAccessGrantsEnabled=true \
      -s standardFlowEnabled=true \
      -s serviceAccountsEnabled=false \
      -s authorizationServicesEnabled=false \
      -i 2>/dev/null)

    echo "   ✓ OIDC client created"
    echo "   Client UUID: $CLIENT_UUID"

    # Get client secret
    CLIENT_SECRET=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
      /opt/keycloak/bin/kcadm.sh get "clients/$CLIENT_UUID/client-secret" -r master 2>/dev/null | \
      grep -o '"value" : "[^"]*"' | cut -d'"' -f4)

    echo "   Client Secret: $CLIENT_SECRET"
fi

# Test MCP server authentication
echo ""
echo "8. Testing MCP server authentication..."
TEST_TOKEN=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c mcp-server -- \
  curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=mcp-server" \
  -d "client_secret=$CLIENT_SECRET" 2>/dev/null | \
  grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -n "$TEST_TOKEN" ]; then
    echo "   ✓ Authentication successful"

    # Test MCP endpoint
    HTTP_CODE=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -c mcp-server -- \
      curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $TEST_TOKEN" \
      http://localhost:8081/q/health 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✓ MCP server health check passed"
    else
        echo "   ⚠ MCP server returned HTTP $HTTP_CODE"
    fi
else
    echo "   ✗ Failed to get authentication token"
    exit 1
fi

# Save credentials
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Keycloak Admin:"
echo "  URL: https://$INGRESS_HOST"
echo "  Username: admin"
echo "  Password: $ADMIN_PASS"
echo ""
echo "Database:"
echo "  Host: postgresql-rw.database.svc.cluster.local"
echo "  Database: keycloak"
echo "  Username: $DB_USER"
echo "  Password: $DB_PASS"
echo ""
echo "MCP Server OIDC Client:"
echo "  Client ID: mcp-server"
echo "  Client Secret: $CLIENT_SECRET"
echo "  Token Endpoint: https://$INGRESS_HOST/realms/master/protocol/openid-connect/token"
echo ""
echo "💾 Save these credentials securely!"
echo ""
