#!/bin/bash
set -euo pipefail

KC_URL="${KC_URL:-http://localhost:8080}"
REALM="morph"
TOKEN_URL="$KC_URL/realms/$REALM/protocol/openid-connect/token"
PASS=0
FAIL=0

check() {
  local name=$1
  local result=$2
  if echo "$result" | python3 -c "import sys,json; json.load(sys.stdin)['access_token']" > /dev/null 2>&1; then
    local expires=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in','?'))")
    echo "  ✓ $name (expires_in: ${expires}s)"
    PASS=$((PASS+1))
  else
    local err=$(echo "$result" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('error','unknown'),'-',r.get('error_description',''))" 2>/dev/null || echo "$result")
    echo "  ✗ $name — $err"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Morph PoC — OAuth2 Flow Tests ==="
echo "Keycloak: $KC_URL/realms/$REALM"
echo ""

# --- 1. Device Token ---
echo "1. Device Token (client_credentials)"
DEVICE_RESULT=$(curl -sf -X POST "$TOKEN_URL" \
  -d "grant_type=client_credentials" \
  -d "client_id=morph-device" \
  -d "client_secret=morph-device-secret" 2>&1 || echo '{"error":"curl_failed"}')
check "client_credentials" "$DEVICE_RESULT"

# --- 2. 2FA Login ---
echo ""
echo "2. 2FA Login (password grant — simulates authorization_code)"
LOGIN_RESULT=$(curl -sf -X POST "$TOKEN_URL" \
  -d "grant_type=password" \
  -d "client_id=morph-login" \
  -d "client_secret=morph-login-secret" \
  -d "username=testuser" \
  -d "password=TestPass123!" 2>&1 || echo '{"error":"curl_failed"}')
check "password grant" "$LOGIN_RESULT"

REFRESH_2FA=$(echo "$LOGIN_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null || echo "")
if [ -n "$REFRESH_2FA" ]; then
  REFRESH_EXPIRES=$(echo "$LOGIN_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_expires_in','?'))")
  echo "  ℹ refresh_token acquired (expires_in: ${REFRESH_EXPIRES}s)"
fi

# --- 3. Token Refresh ---
echo ""
echo "3. Token Refresh (rotating)"
if [ -n "$REFRESH_2FA" ]; then
  REFRESH_RESULT=$(curl -sf -X POST "$TOKEN_URL" \
    -d "grant_type=refresh_token" \
    -d "client_id=morph-login" \
    -d "client_secret=morph-login-secret" \
    -d "refresh_token=$REFRESH_2FA" 2>&1 || echo '{"error":"curl_failed"}')
  check "refresh_token" "$REFRESH_RESULT"

  # Verify old refresh token is revoked (rotating)
  REUSE_RESULT=$(curl -sf -X POST "$TOKEN_URL" \
    -d "grant_type=refresh_token" \
    -d "client_id=morph-login" \
    -d "client_secret=morph-login-secret" \
    -d "refresh_token=$REFRESH_2FA" 2>&1 || echo '{"error":"curl_failed"}')
  if echo "$REUSE_RESULT" | python3 -c "import sys,json; assert 'error' in json.load(sys.stdin)" 2>/dev/null; then
    echo "  ✓ old refresh token rejected (rotation working)"
    PASS=$((PASS+1))
  else
    echo "  ✗ old refresh token still accepted (rotation NOT working)"
    FAIL=$((FAIL+1))
  fi
else
  echo "  ⊘ skipped (no refresh token from step 2)"
fi

# --- 4. Token Exchange: 2FA → 1FA ---
echo ""
echo "4. Token Exchange: 2FA → 1FA (RFC 8693)"
TOKEN_2FA=$(curl -sf -X POST "$TOKEN_URL" \
  -d "grant_type=password" \
  -d "client_id=morph-login" \
  -d "client_secret=morph-login-secret" \
  -d "username=testuser" \
  -d "password=TestPass123!" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")

if [ -n "$TOKEN_2FA" ]; then
  EXCHANGE_RESULT=$(curl -sf -X POST "$TOKEN_URL" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
    -d "client_id=morph-session" \
    -d "client_secret=morph-session-secret" \
    -d "subject_token=$TOKEN_2FA" \
    -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
    -d "requested_token_type=urn:ietf:params:oauth:token-type:access_token" 2>&1 || echo '{"error":"curl_failed"}')
  check "token_exchange" "$EXCHANGE_RESULT"
else
  echo "  ⊘ skipped (no 2FA token)"
fi

# --- 5. JWT Validation ---
echo ""
echo "5. JWT Token Inspection"
if [ -n "$TOKEN_2FA" ]; then
  echo "$TOKEN_2FA" | python3 -c "
import sys, json, base64
token = sys.stdin.read().strip()
parts = token.split('.')
payload = json.loads(base64.urlsafe_b64decode(parts[1] + '=='))
print('  ✓ JWT decoded:')
print('    iss:', payload.get('iss'))
print('    sub:', payload.get('sub'))
print('    azp:', payload.get('azp'))
print('    exp:', payload.get('exp'))
print('    aud:', payload.get('aud'))
"
fi

# --- 6. OIDC Endpoints ---
echo ""
echo "6. OIDC Endpoints"
DISCOVERY=$(curl -sf "$KC_URL/realms/$REALM/.well-known/openid-configuration")
echo "$DISCOVERY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('  ✓ token_endpoint:', d['token_endpoint'])
print('  ✓ authorization_endpoint:', d['authorization_endpoint'])
print('  ✓ end_session_endpoint:', d['end_session_endpoint'])
print('  ✓ jwks_uri:', d['jwks_uri'])
"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
