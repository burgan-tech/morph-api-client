#!/usr/bin/env bash
# Restore PoC defaults (aligned with morph-realm.json).
set -euo pipefail

KC_URL="${KC_URL:-http://localhost:8080}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_PASS="${KC_PASS:-admin}"
REALM="${KC_REALM:-morph}"

echo "=== Morph PoC — restore default token lifetimes ==="

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
  echo "  restored $clientId"
}

put_client morph-device '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "300"
print(json.dumps(c))
'

put_client morph-login '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "300"
a["client.session.idle.timeout"] = "600"
print(json.dumps(c))
'

put_client morph-session '
import sys, json
c = json.load(sys.stdin)
a = c.setdefault("attributes", {})
a["access.token.lifespan"] = "2592000"
# Long-lived PoC: remove tight idle so realm/SSO defaults apply for refresh
if "client.session.idle.timeout" in a:
  del a["client.session.idle.timeout"]
print(json.dumps(c))
'

echo "Done."
