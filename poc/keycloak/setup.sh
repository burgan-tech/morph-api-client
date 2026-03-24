#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Morph PoC — Keycloak Setup
#
# Prerequisites: docker, curl, python3 (for JSON parsing)
#
# What this script does:
#   1. Waits for Keycloak to be ready
#   2. Verifies the 'morph' realm was imported (via docker --import-realm)
#   3. Ensures token exchange is enabled on morph-login and morph-session
#   4. Ensures redirect URIs and web origins are set on morph-login
#   5. Ensures the audience mapper exists on morph-login
#   6. Applies PoC simulation lifetimes (short token TTLs)
#   7. Runs test-flows.sh to verify everything works
#
# Usage:
#   docker compose up -d
#   bash setup.sh
#
# If realm import didn't work (re-run), destroy volumes first:
#   docker compose down -v && docker compose up -d && bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

KC_URL="${KC_URL:-http://localhost:8080}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_PASS="${KC_PASS:-admin}"
REALM="morph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1   || fail "curl is required but not installed."
command -v python3 >/dev/null 2>&1 || fail "python3 is required but not installed (used for JSON parsing)."

echo "=== Morph PoC — Keycloak Setup ==="
echo "Keycloak: $KC_URL"
echo ""

# ── 1. Wait for Keycloak ─────────────────────────────────────────────────
echo "Waiting for Keycloak to be ready..."
MAX_WAIT=60
for i in $(seq 1 $MAX_WAIT); do
  if curl -sf "$KC_URL/realms/master" > /dev/null 2>&1; then
    info "Keycloak is ready (attempt $i)."
    break
  fi
  if [ "$i" -eq $MAX_WAIT ]; then
    fail "Keycloak not ready after ${MAX_WAIT}s. Is it running? Check: docker compose logs keycloak"
  fi
  sleep 1
done

# ── 2. Get admin token ────────────────────────────────────────────────────
ADMIN_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=$KC_ADMIN" \
  -d "password=$KC_PASS" 2>&1) || fail "Cannot get admin token. Check KC_ADMIN/KC_PASS."

ADMIN_TOKEN=$(echo "$ADMIN_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null) \
  || fail "Admin token response is not valid JSON. Keycloak might still be starting."

info "Admin token acquired."

# ── 3. Check realm exists ─────────────────────────────────────────────────
REALM_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM" 2>/dev/null || echo "000")

if [ "$REALM_STATUS" != "200" ]; then
  echo ""
  fail "Realm '$REALM' not found (HTTP $REALM_STATUS).
  This means --import-realm did not run or the volume has stale data.
  Fix: docker compose down -v && docker compose up -d && bash setup.sh"
fi

info "Realm '$REALM' found."

# ── Helper: get client internal id ────────────────────────────────────────
get_client_id() {
  local clientId="$1"
  local result
  result=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients?clientId=$clientId" 2>&1) \
    || fail "Cannot list clients. Admin token may have expired."
  echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if not d: print(''); sys.exit(0)
print(d[0]['id'])
" 2>/dev/null || echo ""
}

# ── Helper: update client ─────────────────────────────────────────────────
update_client() {
  local clientId="$1"
  local internal_id="$2"
  local python_transform="$3"

  local current
  current=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients/$internal_id" 2>&1) \
    || fail "Cannot read client '$clientId'."

  local updated
  updated=$(echo "$current" | python3 -c "$python_transform" 2>&1) \
    || fail "Python transform failed for '$clientId': $updated"

  local http_code
  http_code=$(echo "$updated" | curl -sf -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    "$KC_URL/admin/realms/$REALM/clients/$internal_id" -d @- 2>/dev/null || echo "000")

  if [ "$http_code" != "204" ]; then
    fail "Failed to update '$clientId' (HTTP $http_code)."
  fi
}

# ── 4. Verify all 4 clients exist ────────────────────────────────────────
echo ""
echo "Checking clients..."
for cid in morph-device morph-login morph-session morph-api; do
  cid_internal=$(get_client_id "$cid")
  if [ -z "$cid_internal" ]; then
    fail "Client '$cid' not found in realm. The realm import may be incomplete.
  Fix: docker compose down -v && docker compose up -d && bash setup.sh"
  fi
  info "Client '$cid' exists."
done

# ── 5. Configure morph-session (token exchange) ──────────────────────────
echo ""
echo "Configuring morph-session..."
SESSION_ID=$(get_client_id "morph-session")

update_client "morph-session" "$SESSION_ID" '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["oauth2.token.exchange.grant.enabled"] = "true"
a["access.token.lifespan"] = "20"
a["client.session.idle.timeout"] = "60"
print(json.dumps(c))
'
info "morph-session: token exchange enabled, 20s access, 60s idle."

# ── 6. Configure morph-login (token exchange + redirects + audience) ─────
echo ""
echo "Configuring morph-login..."
LOGIN_ID=$(get_client_id "morph-login")

update_client "morph-login" "$LOGIN_ID" '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["oauth2.token.exchange.grant.enabled"] = "true"
a["access.token.lifespan"] = "30"
a["client.session.idle.timeout"] = "60"
c["redirectUris"] = [
    "http://localhost:3000/callback/keycloak",
    "http://localhost:3000/*",
    "http://localhost:5173/",
    "http://127.0.0.1:5173/",
    "http://localhost:5173/oauth/callback",
    "http://127.0.0.1:5173/oauth/callback",
    "http://localhost:5173/auth/callback",
    "http://127.0.0.1:5173/auth/callback",
    "http://localhost:5173/*",
    "http://127.0.0.1:5173/*",
]
c["webOrigins"] = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]
print(json.dumps(c))
'
info "morph-login: token exchange, redirect URIs, web origins updated."

# ── 7. Audience mapper on morph-login ────────────────────────────────────
MAPPER_COUNT=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients/$LOGIN_ID/protocol-mappers/models" \
  | python3 -c "
import sys, json
mappers = json.load(sys.stdin)
print(sum(1 for m in mappers if m.get('name') == 'morph-session-audience'))
" 2>/dev/null || echo "0")

if [ "$MAPPER_COUNT" = "0" ]; then
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
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
        "introspection.token.claim": "true",
        "userinfo.token.claim": "false"
      }
    }' 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "204" ]; then
    info "Audience mapper 'morph-session-audience' created."
  else
    fail "Failed to create audience mapper (HTTP $HTTP_CODE)."
  fi
else
  info "Audience mapper 'morph-session-audience' already exists."
fi

# ── 8. Configure morph-device ────────────────────────────────────────────
echo ""
echo "Configuring morph-device..."
DEVICE_ID=$(get_client_id "morph-device")

update_client "morph-device" "$DEVICE_ID" '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "15"
print(json.dumps(c))
'
info "morph-device: 15s access token."

# ── 9. Verify with test-flows.sh ─────────────────────────────────────────
echo ""
echo "━━━ Running verification tests ━━━"
echo ""
if [ -f "$SCRIPT_DIR/test-flows.sh" ]; then
  if bash "$SCRIPT_DIR/test-flows.sh"; then
    echo ""
    info "All verification tests passed."
  else
    echo ""
    fail "Verification tests failed! Check the output above."
  fi
else
  warn "test-flows.sh not found — skipping verification."
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Setup Complete${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Keycloak Admin:  $KC_URL/admin  (admin/admin)"
echo "Realm:           $REALM"
echo "OIDC Discovery:  $KC_URL/realms/$REALM/.well-known/openid-configuration"
echo ""
echo "Clients:"
echo "  morph-device   (client_credentials)  secret: morph-device-secret   ATL: 15s"
echo "  morph-login    (authorization_code)   secret: morph-login-secret    ATL: 30s  idle: 60s"
echo "  morph-session  (token_exchange)       secret: morph-session-secret  ATL: 20s  idle: 60s"
echo "  morph-api      (bearer-only resource server)"
echo ""
echo "Test Users:"
echo "  testuser / TestPass123!"
echo "  admin    / AdminPass123!"
echo ""
echo "Redirect URIs on morph-login include:"
echo "  http://localhost:5173/oauth/callback"
echo "  http://127.0.0.1:5173/oauth/callback"
echo "  http://localhost:5173/*   (wildcard)"
echo ""
echo "Troubleshooting:"
echo "  - Re-run:         bash setup.sh"
echo "  - Full reset:     docker compose down -v && docker compose up -d && bash setup.sh"
echo "  - Test only:      bash test-flows.sh"
echo "  - Short TTLs:     bash set-simulation-lifetimes.sh"
echo "  - Restore TTLs:   bash restore-simulation-lifetimes.sh"
