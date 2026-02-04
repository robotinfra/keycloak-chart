#!/bin/bash
# Keycloak Post-Install Setup Script
# For migrating existing installations to use the new OIDC automation
#
# This file is rendered as a Helm template during installation.
# Values are injected at helm install/upgrade time.

set -e

NAMESPACE="{{ .Release.Namespace }}"
RELEASE_NAME="{{ .Release.Name }}"
KEYCLOAK_SERVICE="{{ include "keycloak.fullname" . }}"
ADMIN_SECRET="{{ .Values.admin.existingSecret | default (printf "%s-admin" (include "keycloak.fullname" .)) }}"
DB_SECRET="{{ .Values.database.existingSecret | default (printf "%s-db-credentials" (include "keycloak.fullname" .)) }}"

echo "=== Keycloak Post-Install Setup ==="
echo "Release: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Wait for Keycloak to be ready
echo "1. Waiting for Keycloak..."
kubectl wait --for=condition=ready pod \
  -n "$NAMESPACE" \
  -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance="$RELEASE_NAME" \
  --timeout=300s

POD_NAME=$(kubectl get pod -n "$NAMESPACE" \
  -l app.kubernetes.io/name=keycloak,app.kubernetes.io/instance="$RELEASE_NAME" \
  -o jsonpath='{.items[0].metadata.name}')
echo "   ✓ Pod ready: $POD_NAME"

# Get credentials
echo ""
echo "2. Reading credentials..."
ADMIN_USER=$(kubectl get secret -n "$NAMESPACE" "$ADMIN_SECRET" -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl get secret -n "$NAMESPACE" "$ADMIN_SECRET" -o jsonpath='{.data.password}' | base64 -d)
DB_USER=$(kubectl get secret -n "$NAMESPACE" "$DB_SECRET" -o jsonpath='{.data.username}' | base64 -d)
DB_PASS=$(kubectl get secret -n "$NAMESPACE" "$DB_SECRET" -o jsonpath='{.data.password}' | base64 -d)
echo "   ✓ Credentials retrieved"

# Configure kcadm.sh
echo ""
echo "3. Authenticating with Keycloak..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm {{ .Values.mcpServer.oidcClient.realm }} \
  --user "$ADMIN_USER" \
  --password "$ADMIN_PASS" &>/dev/null
echo "   ✓ Authenticated"

# Check OIDC client
echo ""
echo "4. Checking OIDC client status..."
if kubectl get secret -n "$NAMESPACE" "{{ include "keycloak.fullname" . }}-mcp-client" &>/dev/null; then
    echo "   ✓ OIDC client secret exists (created by Job)"

    CLIENT_ID=$(kubectl get secret -n "$NAMESPACE" "{{ include "keycloak.fullname" . }}-mcp-client" \
      -o jsonpath='{.data.client-id}' | base64 -d)
    CLIENT_SECRET=$(kubectl get secret -n "$NAMESPACE" "{{ include "keycloak.fullname" . }}-mcp-client" \
      -o jsonpath='{.data.client-secret}' | base64 -d)

    echo "   Client ID: $CLIENT_ID"
    echo "   Client Secret: $CLIENT_SECRET"
else
    echo "   ⚠ OIDC client secret not found"
    echo "   The post-install Job should have created it."
    echo "   Check: kubectl get jobs -n $NAMESPACE"
    exit 1
fi

# Display summary
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Keycloak Admin:"
{{- if .Values.ingress.enabled }}
{{- $firstHost := index .Values.ingress.hosts 0 }}
echo "  URL: https://{{ $firstHost.host }}"
{{- else }}
echo "  URL: http://$KEYCLOAK_SERVICE:{{ .Values.service.port }}"
{{- end }}
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASS"
echo ""
echo "Database:"
echo "  Host: {{ .Values.database.host }}"
echo "  Database: {{ .Values.database.name }}"
echo "  Username: $DB_USER"
echo "  Password: $DB_PASS"
echo ""
{{- if .Values.mcpServer.oidcClient.enabled }}
echo "MCP Server OIDC Client:"
echo "  Client ID: $CLIENT_ID"
echo "  Client Secret: $CLIENT_SECRET"
{{- if .Values.ingress.enabled }}
{{- $firstHost := index .Values.ingress.hosts 0 }}
echo "  Issuer: https://{{ $firstHost.host }}/realms/{{ .Values.mcpServer.oidcClient.realm }}"
echo "  Token Endpoint: https://{{ $firstHost.host }}/realms/{{ .Values.mcpServer.oidcClient.realm }}/protocol/openid-connect/token"
{{- else }}
echo "  Issuer: http://$KEYCLOAK_SERVICE:{{ .Values.service.port }}/realms/{{ .Values.mcpServer.oidcClient.realm }}"
echo "  Token Endpoint: http://$KEYCLOAK_SERVICE:{{ .Values.service.port }}/realms/{{ .Values.mcpServer.oidcClient.realm }}/protocol/openid-connect/token"
{{- end }}
echo ""
{{- end }}
echo "💾 Save these credentials securely!"
echo ""
