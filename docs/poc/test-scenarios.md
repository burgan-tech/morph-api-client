# PoC Test Scenarios

This document describes test flows to validate the Morph SDK against the PoC environment (Keycloak + Google + Mock API).

For a **continuous mock loop** (latency, status codes, verbose logs), use the **Simulation** section on the PoC home page (`/`) and [simulation.md](simulation.md).

## Prerequisites

1. Keycloak running:
   ```bash
   cd poc/keycloak
   docker compose up -d
   ./setup.sh
   ```
2. Mock API running:
   ```bash
   cd poc/mock-api
   npm install && npm start
   ```
3. Google OAuth2 configured per [Google Setup Guide](google-setup.md) (for google scenario only)
4. Quick verification: `cd poc/keycloak && ./test-flows.sh`

### Device id and installation id (PoC)

The mock API and Keycloak-bound requests send **`X-Device-Id`** and **`X-Installation-Id`** (see `morph-config.json`).

- **Mobile target model:** `deviceId` identifies the device; `installationId` is a GUID issued on **first install** and kept until reinstall.
- **Vue web PoC:** we map **browser profile → device id** (persisted in `localStorage`) and **browser tab session → installation id** (`sessionStorage`, so a **new tab behaves like a new install**). Override with `VITE_DEVICE_ID` / `VITE_INSTALLATION_ID` if you need fixed strings.

---

## Scenario 1: Device Authentication (Client Credentials)

**Tests**: Non-interactive token acquisition, device-scoped storage, delegate recovery.

**Flow**:
1. SDK initializes with the `device` context
2. Call `morph.host('main-api').get('/public/config', { auth: 'morph-auth/device' })`
3. SDK acquires a device token via client credentials (no user interaction)
4. Request succeeds with 200

**What to verify**:
- [ ] SDK calls `POST /realms/morph/protocol/openid-connect/token` with `grant_type=client_credentials`
- [ ] Token stored persistently at device scope
- [ ] Subsequent requests reuse stored token
- [ ] Response body contains `{ appName: "Morph PoC", ... }`

**Manual curl**:
```bash
TOKEN=$(curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=client_credentials" \
  -d "client_id=morph-device" \
  -d "client_secret=morph-device-secret" | jq -r '.access_token')

curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/public/config
```

---

## Scenario 2: 2FA Login (Authorization Code)

**Tests**: Interactive login, authorization code exchange, short-lived tokens (5min access, 10min refresh).

**Flow**:
1. Call `morph.host('main-api').get('/accounts', { auth: 'morph-auth/2fa' })`
2. SDK detects no 2fa token
3. SDK invokes `onAuthRequired('morph-auth/2fa', { workflow: 'login', interaction: 'interactive' })`
4. Host app opens Keycloak `/auth` URL in browser
5. User logs in → redirect returns authorization code
6. Host app calls `morph.auth('morph-auth/2fa').submitCode(code)`
7. SDK exchanges code at Keycloak token endpoint, stores tokens
8. Request succeeds

**What to verify**:
- [ ] `onAuthRequired` fires with correct `delegateMetadata`
- [ ] Keycloak login page shown, user authenticates
- [ ] `submitCode()` exchanges code for tokens (5min access, 10min refresh)
- [ ] `await morph.auth('morph-auth/2fa').hasValidToken()` returns `true`
- [ ] Mock API response includes `authLevel: '2fa'`

**Manual curl (password grant simulates auth code for testing)**:
```bash
curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=morph-login" \
  -d "client_secret=morph-login-secret" \
  -d "username=testuser" \
  -d "password=TestPass123!" | jq .
```

---

## Scenario 3: Token Refresh (Rotating)

**Tests**: Proactive refresh before expiry, rotating refresh tokens, refresh mutex.

### 3a: Proactive Refresh

1. After 2FA login, note token `exp` (default realm: ~30s access for `morph-login`)
2. Wait until within `refreshBeforeExpiry` (SDK: **10s** before access expiry for 2fa)
3. Make a request — SDK proactively refreshes
4. New token stored, old refresh token invalidated (rotation)

### 3b: Reactive Refresh

1. Clear access token from storage (simulating expiry)
2. Make a request — SDK detects expired token, uses refresh token
3. Request succeeds with new token

### 3c: Rotation Verification

1. Note the current refresh token
2. Refresh once — get new refresh token
3. Try reusing the OLD refresh token — must be rejected

**What to verify**:
- [ ] Proactive refresh fires within configured `refreshBeforeExpiry` (2fa **10s**, 1fa **8s**; check onLog)
- [ ] New access token stored, old one replaced
- [ ] Old refresh token rejected after rotation
- [ ] Concurrent requests coalesce into single refresh call

**Manual curl**:
```bash
# Get tokens
RESULT=$(curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=morph-login" -d "client_secret=morph-login-secret" \
  -d "username=testuser" -d "password=TestPass123!")
REFRESH=$(echo $RESULT | jq -r '.refresh_token')

# Refresh
NEW=$(curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=refresh_token" -d "client_id=morph-login" -d "client_secret=morph-login-secret" \
  -d "refresh_token=$REFRESH")
echo $NEW | jq .

# Reuse old refresh (should fail)
curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=refresh_token" -d "client_id=morph-login" -d "client_secret=morph-login-secret" \
  -d "refresh_token=$REFRESH" | jq .
```

---

## Scenario 4: Token Exchange — 2FA → 1FA (RFC 8693)

**Tests**: Keycloak native token exchange, 1FA session token from 2FA (default realm: 1FA access **20s**, refresh window **60s** client idle; SDK `maxTtl` still caps stored metadata).

**Flow**:
1. Ensure 2FA is authenticated (Scenario 2)
2. SDK auto-exchanges via `exchangeSource: ['morph-auth/2fa']` (or a single string) on 1fa config when resolving 1FA
3. Or manually: `morph.auth('morph-auth/2fa').exchangeToken('morph-auth/1fa')`
4. 1FA token stored persistently with encryption (30-day maxTtl)

**What to verify**:
- [ ] Exchange returns 1FA token (authLevel: '1fa', client: 'morph-session')
- [ ] 1FA access token stored persistently with encryption (user scope)
- [ ] 1FA JWT `exp` reflects `morph-session` access lifespan (default **20s**; 2FA access default **30s** — compare `exp` on both tokens)
- [ ] Mock API accepts 1FA token: `authLevel: '1fa'`

**Manual curl**:
```bash
# Get 2FA token
TOKEN_2FA=$(curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=morph-login" -d "client_secret=morph-login-secret" \
  -d "username=testuser" -d "password=TestPass123!" | jq -r '.access_token')

# Exchange 2FA → 1FA
curl -s -X POST http://localhost:8080/realms/morph/protocol/openid-connect/token \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "client_id=morph-session" \
  -d "client_secret=morph-session-secret" \
  -d "subject_token=$TOKEN_2FA" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  -d "requested_token_type=urn:ietf:params:oauth:token-type:access_token" | jq .

# Use 1FA token on mock API
TOKEN_1FA=$(!! | jq -r '.access_token')
curl -H "Authorization: Bearer $TOKEN_1FA" http://localhost:3000/profile
```

---

## Scenario 5: 401 Recovery

**Tests**: RecoveryPolicy handling.

### 5a: Recovery via Refresh (2FA context)

1. Use expired 2FA access token
2. Mock API returns 401
3. SDK follows `recoveryPolicy.onUnauthorized = 'refresh'`
4. SDK refreshes token, retries request → success

### 5b: Recovery via Delegate (Device context)

1. Clear device token
2. Make request with `{ auth: 'morph-auth/device' }`
3. SDK follows `recoveryPolicy.onUnauthorized = 'delegate'`
4. `onAuthRequired` fires with `interaction: 'non-interactive'`
5. Host app calls `morph.auth('morph-auth/device').acquire()`

### 5c: Refresh Failure → Delegate (1FA context)

1. Invalidate 1FA refresh token
2. Wait for access token expiry
3. SDK attempts refresh → fails
4. SDK follows `recoveryPolicy.onRefreshFail = 'delegate'`
5. `onAuthRequired('morph-auth/1fa', { workflow: 'token-exchange', ... })` fires

**What to verify**:
- [ ] 401 triggers configured recovery action
- [ ] Refresh + retry works transparently
- [ ] Delegate triggers `onAuthRequired` with correct metadata
- [ ] Failed refresh cascades to `onRefreshFail` policy

---

## Scenario 6: Logout

**Tests**: Keycloak logout endpoint, token clearing, callback invocation.

**Flow**:
1. Authenticate with 2FA (Scenario 2)
2. Call `morph.auth('morph-auth/2fa').logout()`
3. SDK calls Keycloak `/logout` endpoint
4. All 2FA tokens cleared from storage
5. `onLogout('morph-auth/2fa', 'user_initiated')` fires

**Provider-level logout**:
1. Call `morph.auth('morph-auth').logout()`
2. ALL morph-auth contexts (device + 2fa + 1fa) cleared

**What to verify**:
- [ ] Keycloak logout endpoint called
- [ ] All tokens for context (or provider) cleared
- [ ] `onLogout` callback fires with correct authId and reason
- [ ] `await hasValidToken()` returns `false` after logout

---

## Scenario 7: E-Devlet Flow (Google OAuth2 + PKCE)

**Tests**: External provider, authorization code + PKCE, Google API as resource.

**Flow**:
1. Call `morph.host('google-api').get('/oauth2/v3/userinfo', { auth: 'google-auth/google' })`
2. SDK detects no google token
3. SDK invokes `onAuthRequired('google-auth/google', { workflow: 'google-login', interaction: 'redirect' })`
4. Host app opens Google `/o/oauth2/v2/auth` with PKCE
5. User logs in to Google, consents, gets redirected
6. Host app calls `morph.auth('google-auth/google').submitCode(code, { codeVerifier })`
7. SDK exchanges code at Google token endpoint, stores tokens
8. Request retries — Google userinfo returns profile

**What to verify**:
- [ ] PKCE code_verifier/code_challenge generated (S256)
- [ ] Google authorization code flow completes
- [ ] Tokens stored in memory (session scope)
- [ ] Google userinfo endpoint returns valid user data

---

## Scenario 8: Multi-Host / Multi-Auth

**Tests**: Different auth levels on same host, different hosts.

**Flow**:
1. Authenticate with 2FA (Scenario 2) + exchange to 1FA (Scenario 4)
2. `morph.host('main-api').get('/accounts', { auth: 'morph-auth/2fa' })` → authLevel: 2fa
3. `morph.host('main-api').get('/accounts', { auth: 'morph-auth/1fa' })` → authLevel: 1fa
4. `morph.host('main-api').get('/accounts', { auth: 'morph-auth/device' })` → authLevel: device
5. Priority fallback: `auth: ['morph-auth/2fa', 'morph-auth/1fa']` → uses best available

**What to verify**:
- [ ] Same host, different auth → different `authLevel` in response
- [ ] `resolvedAuth` in MorphResponse matches the context used
- [ ] Priority fallback selects the first available context

---

## Scenario 9: Auth Validation (allowedAuth)

**Tests**: SDK rejects unauthorized auth contexts for a host.

**Flow**:
1. `google-api` host has `allowedAuth: ['google-auth/google']`
2. Call `morph.host('google-api').get('/oauth2/v3/userinfo', { auth: 'morph-auth/1fa' })`
3. SDK rejects with `InvalidAuthForHostError` before any HTTP call

**What to verify**:
- [ ] Request rejected **before** any network call
- [ ] Error type is `InvalidAuthForHostError`
- [ ] Error includes `authId`, `hostKey`, `allowedAuth`
- [ ] Valid auth for host (e.g., `google-auth/google`) works fine

---

## Results Tracking

| Scenario | Status | Notes |
|---|---|---|
| 1. Device auth (client_credentials) | | |
| 2. 2FA login (authorization_code) | | |
| 3a. Proactive refresh | | |
| 3b. Reactive refresh | | |
| 3c. Rotation verification | | |
| 4. Token exchange 2FA→1FA | | |
| 5a. Recovery via refresh | | |
| 5b. Recovery via delegate | | |
| 5c. Refresh fail → delegate | | |
| 6. Logout (context + provider) | | |
| 7. E-devlet (Google + PKCE) | | |
| 8. Multi-host / multi-auth | | |
| 9. Auth validation (allowedAuth) | | |
