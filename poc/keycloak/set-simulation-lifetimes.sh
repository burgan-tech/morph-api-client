#!/usr/bin/env bash
# Re-apply PoC short lifetimes (same as morph-realm.json defaults):
#   morph-device: 15s access (client_credentials, no refresh)
#   morph-login (2fa): 30s access, 60s client session idle (refresh)
#   morph-session (1fa): 20s access, 60s client session idle
# Revert long-lived PoC: ./restore-simulation-lifetimes.sh
set -euo pipefail

KC_URL="${KC_URL:-http://localhost:8080}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_PASS="${KC_PASS:-admin}"
REALM="${KC_REALM:-morph}"

echo "=== Morph PoC — Keycloak simulation lifetimes ==="

for i in $(seq 1 30); do
  if curl -sf "$KC_URL/realms/master" > /dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Keycloak not ready."
    exit 1
  fi
  sleep 2
done

ADMIN_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=$KC_ADMIN" \
  -d "password=$KC_PASS" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

put_client() {
  local clientId="$1"
  local internal_id
  internal_id=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients?clientId=$clientId" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])")
  curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients/$internal_id" | python3 -c "$2" | curl -sf -X PUT \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    "$KC_URL/admin/realms/$REALM/clients/$internal_id" -d @- > /dev/null
  echo "  updated $clientId"
}

put_client morph-device '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "15"
print(json.dumps(c))
'

put_client morph-login '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "30"
a["client.session.idle.timeout"] = "60"
print(json.dumps(c))
'

put_client morph-session '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "20"
a["client.session.idle.timeout"] = "60"
print(json.dumps(c))
'

echo "Done. Re-login in the browser so new token lifetimes apply."
