#!/bin/bash
set -euo pipefail

KC_URL="${KC_URL:-http://localhost:8080}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_PASS="${KC_PASS:-admin}"
REALM="morph"

echo "=== Morph PoC — Keycloak Setup ==="
echo "Keycloak: $KC_URL"
echo ""

# Wait for Keycloak to be ready
echo "Waiting for Keycloak..."
for i in $(seq 1 30); do
  if curl -sf "$KC_URL/realms/master" > /dev/null 2>&1; then
    echo "Keycloak is ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Keycloak not ready after 30 attempts."
    exit 1
  fi
  sleep 2
done

# Get admin token
ADMIN_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=$KC_ADMIN" \
  -d "password=$KC_PASS" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Admin token acquired."

# Check if realm exists (imported via docker-compose volume)
REALM_EXISTS=$(curl -sf -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM")

if [ "$REALM_EXISTS" != "200" ]; then
  echo "ERROR: Realm '$REALM' not found. Ensure morph-realm.json is mounted and --import-realm is used."
  exit 1
fi

echo "Realm '$REALM' found."

# Enable token exchange on morph-session (may already be set by import, but ensure it)
SESSION_ID=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=morph-session" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients/$SESSION_ID" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['attributes']['oauth2.token.exchange.grant.enabled'] = 'true'
print(json.dumps(c))
" | curl -sf -X PUT -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  "$KC_URL/admin/realms/$REALM/clients/$SESSION_ID" -d @- > /dev/null

echo "Token exchange enabled on morph-session."

# Enable token exchange on morph-login
LOGIN_ID=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=morph-login" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients/$LOGIN_ID" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['attributes']['oauth2.token.exchange.grant.enabled'] = 'true'
# Vue PoC (Vite): must match morph-config $oauthCallbackUri (default …/oauth/callback) and legacy root return
c['redirectUris'] = [
  'http://localhost:3000/callback/keycloak',
  'http://localhost:3000/*',
  'http://localhost:5173/',
  'http://127.0.0.1:5173/',
  'http://localhost:5173/oauth/callback',
  'http://127.0.0.1:5173/oauth/callback',
  'http://localhost:5173/auth/callback',
  'http://127.0.0.1:5173/auth/callback',
  'http://localhost:5173/*',
  'http://127.0.0.1:5173/*',
]
c['webOrigins'] = [
  'http://localhost:3000',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]
print(json.dumps(c))
" | curl -sf -X PUT -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  "$KC_URL/admin/realms/$REALM/clients/$LOGIN_ID" -d @- > /dev/null

echo "Token exchange + redirect URIs updated on morph-login."

# Verify audience mapper exists on morph-login
MAPPER_COUNT=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients/$LOGIN_ID/protocol-mappers/models" \
  | python3 -c "
import sys, json
mappers = json.load(sys.stdin)
count = sum(1 for m in mappers if m.get('name') == 'morph-session-audience')
print(count)
")

if [ "$MAPPER_COUNT" = "0" ]; then
  curl -sf -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    "$KC_URL/admin/realms/$REALM/clients/$LOGIN_ID/protocol-mappers/models" \
    -d '{
      "name": "morph-session-audience",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-audience-mapper",
      "config": {
        "included.client.audience": "morph-session",
        "id.token.claim": "false",
        "access.token.claim": "true",
        "lightweight.claim": "false",
        "introspection.token.claim": "true"
      }
    }' > /dev/null
  echo "Audience mapper created on morph-login."
else
  echo "Audience mapper already exists on morph-login."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/set-simulation-lifetimes.sh" ]; then
  echo ""
  echo "Applying PoC short token lifetimes (morph-device, morph-login, morph-session)..."
  KC_URL="$KC_URL" KC_REALM="$REALM" bash "$SCRIPT_DIR/set-simulation-lifetimes.sh"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Keycloak Admin:  $KC_URL/admin  (admin/admin)"
echo "Realm:           $REALM"
echo "OIDC Discovery:  $KC_URL/realms/$REALM/.well-known/openid-configuration"
echo ""
echo "PoC short token lifetimes were applied above (morph-device 15s access; morph-login 30s + 60s idle;"
echo "  morph-session 20s + 60s idle). Long-lived PoC: restore-simulation-lifetimes.sh"
echo "  Re-apply short only: ./set-simulation-lifetimes.sh"
echo ""
echo "Clients:"
echo "  morph-device   (client_credentials)  secret: morph-device-secret"
echo "  morph-login    (authorization_code)   secret: morph-login-secret"
echo "  morph-session  (token_exchange)       secret: morph-session-secret"
echo "  morph-api      (bearer-only resource server)"
echo ""
echo "Test Users:"
echo "  testuser / TestPass123!"
echo "  admin / AdminPass123!"
echo ""
echo "PoC Vue redirect URIs on morph-login include http://localhost:5173/oauth/callback (and / for legacy)."
echo "Re-run this script after changing ports; or edit redirect URIs in Admin Console → Clients → morph-login."
