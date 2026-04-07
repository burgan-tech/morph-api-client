# PoC Guide

Step-by-step walkthrough of the Vue PoC application. This guide assumes you have the full stack running.

---

## Prerequisites

```bash
make install        # install all npm dependencies
make build          # build the core SDK
cp poc/ts-vue/.env.example poc/ts-vue/.env   # create env with client secrets
make up             # start Keycloak + setup + mock API + Vue dev server
```

After `make up` completes, three services are running:

| Service | URL |
|---------|-----|
| Vue PoC | http://127.0.0.1:5173 |
| Mock API | http://localhost:3000 |
| Keycloak Admin | http://localhost:8080/admin (admin/admin) |

Test users in Keycloak:

| Username | Password |
|----------|----------|
| testuser | TestPass123! |
| admin | AdminPass123! |

---

## The Home Page

Open **http://127.0.0.1:5173/** in your browser. The Home page has four main sections:

### 1. Status Table

Shows every auth context configured in the SDK. Each row displays:

- **Auth ID** (e.g., `morph-auth/device`, `morph-auth/2fa`, `morph-auth/1fa`)
- **Status**: `--` (no token), `OK` (valid token), `expired`
- **Action buttons** depending on the context type

Initially all rows show `--` because no tokens have been acquired yet.

### 2. Action Buttons per Context

Each context has different actions:

| Context | Button | What It Does |
|---------|--------|--------------|
| `morph-auth/device` | **Acquire token** | Calls `client_credentials` grant to Keycloak |
| `morph-auth/2fa` | **Keycloak login** | Redirects the browser to Keycloak login page |
| `morph-auth/1fa` | **Exchange** | Exchanges a 2fa token for a 1fa session token |
| `google-auth/google` | **Google login** | Redirects to Google OAuth (needs `VITE_GOOGLE_*` env vars) |

### 3. Mock API Playground

Click "Mock API" to open a modal with buttons for each simulation step. You can run individual API calls and see the HTTP traces (request/response headers, body, timing).

### 4. Simulation Panel

A loop that repeatedly runs API calls to test token refresh, exchange, and recovery. More on this below.

---

## Step 1: Acquire a Device Token

1. Find the **Device** row in the Status table
2. Click **Acquire token**
3. The SDK calls Keycloak with `grant_type=client_credentials` using the `morph-device` client
4. The row updates to show **OK** with a JWT preview button

This is a non-interactive flow -- no user login required. The device token is used for pre-login API calls.

If you see "Invalid client credentials", your `.env` file is missing or the Vite dev server needs a restart after creating it.

---

## Step 2: Sign In with Keycloak

1. Find the **Login (2fa)** row in the Status table
2. Click **Keycloak login**
3. The browser redirects to `http://localhost:8080/realms/morph/protocol/openid-connect/auth`
4. Keycloak shows the login form
5. Enter `testuser` / `TestPass123!` and submit
6. Keycloak redirects back to `http://127.0.0.1:5173/oauth/callback?code=...&state=...`
7. The SDK exchanges the authorization code for tokens
8. You are redirected back to Home with the **Login (2fa)** row showing **OK**

Behind the scenes:
- The SDK encodes the `authId` (`morph-auth/2fa`) in the OAuth `state` parameter
- The callback page decodes the state, determines which context to use, and calls `morph.completeOAuthCallback()`
- The token exchange goes through the Vite proxy (`/__keycloak`) to avoid CORS issues
- Both access token and refresh token are stored in `sessionStorage`

---

## Step 3: Exchange for a Session Token

After signing in with 2fa, you can get a 1fa session token:

1. Find the **Session (1fa)** row in the Status table
2. The **Subject** dropdown should show `Login (2fa) morph-auth/2fa` as the source
3. Click **Exchange**
4. The SDK takes the 2fa access token and calls Keycloak's token endpoint with `grant_type=urn:ietf:params:oauth:grant-type:token-exchange`
5. The **Session (1fa)** row updates to show **OK**

The 1fa token has `exchangeSource: ["morph-auth/2fa"]` in the config, so the SDK can also perform this exchange **automatically** during token resolution when an API call needs a 1fa token.

---

## Step 4: JWT Preview

Click the **JWT** button on any row with a token to see the decoded JWT payload:

- **Access tab**: Shows claims like `sub`, `iss`, `azp`, `exp`, `aud`
- **Refresh tab**: Shows refresh token claims (if the token is a JWT; opaque tokens show a note)

The **IdP Refresh** button in the modal manually triggers a token refresh against Keycloak.

---

## Step 5: Run the Simulation

The Simulation panel at the bottom of the page runs a loop of API calls:

### Configuration

- **Interval (ms)**: How often each tick runs (default: 5000ms)
- **Verbose console**: Enables detailed SDK logging in the browser console
- **404 probe**: Adds a 404 test request to each tick

### What Each Tick Does

Each tick runs these steps in order:

| Step | Type | Auth | Description |
|------|------|------|-------------|
| GET /public/config | fetch | none | Raw fetch to mock API (no SDK) |
| GET /health | fetch | none | Raw fetch to mock API (no SDK) |
| GET /profile (1fa) | host | `morph-auth/1fa` | SDK resolves 1fa token, calls mock API |
| GET /accounts (2fa) | host | `morph-auth/2fa` | SDK resolves 2fa token, calls mock API |
| POST /transfers (2fa) | host | `morph-auth/2fa` | SDK resolves 2fa token, POST to mock API |
| GET /profile + headers | host | `morph-auth/1fa` | SDK resolves 1fa token, adds custom headers |
| GET /public/config (device) | host | `morph-auth/device` | SDK resolves device token |

### Status Codes in the Log

| Status | Meaning |
|--------|---------|
| `200` | Successful API call |
| `401` | Unauthorized (token invalid/expired, SDK will try recovery) |
| `404` | Not found (expected for the 404 probe) |
| `AUTH` | SDK could not resolve a token for this context |
| `SKIP` | Conditional block skipped (condition not met) |
| `STOP` | Simulation stopped (session dead check triggered) |
| `NET` | Network error (service unreachable) |
| `ERR` | Unexpected error |

### Session Dead Check

If **both** `morph-auth/1fa` and `morph-auth/2fa` fail with `AUTH` in the same tick, the simulation stops and shows:

> Keycloak session is dead (refresh: invalid_grant / Token is not active). Simulation stopped -- sign in again from Home.

This means your tokens have expired and cannot be refreshed. Go to Home and sign in with Keycloak again.

### Starting the Simulation

1. Sign in with Keycloak and acquire device tokens first (Steps 1-3 above)
2. Click **Start**
3. Watch the log table fill with results
4. Click **Stop** to end the loop

---

## Token Refresh Behavior

With the default PoC token lifetimes (set by `setup.sh`):

| Context | Access Token | Refresh Idle | Proactive Refresh |
|---------|-------------|--------------|-------------------|
| device | 15s | (no refresh) | 5s before expiry |
| 2fa (login) | 30s | 60s | 10s before expiry |
| 1fa (session) | 20s | 60s | 8s before expiry |

The SDK refreshes tokens **before** they expire (proactive refresh). If the simulation is running, you will see tokens being refreshed transparently in the verbose console output.

To use longer-lived tokens during development:

```bash
make keycloak-restore-tokens    # 5min access, 10min refresh
```

To re-apply short tokens for testing refresh flows:

```bash
make keycloak-short-tokens      # 15s/30s/20s
```

---

## Vite Proxy for CORS

In development, the browser cannot POST directly to Keycloak (CORS). The Vite dev server proxies token requests:

```
Browser POST /__keycloak/realms/morph/protocol/openid-connect/token
    |
    v
Vite proxy rewrites path, forwards to http://localhost:8080
    |
    v
Keycloak processes the token request
```

This proxy is configured in `poc/ts-vue/vite.config.ts` and is only active in dev mode. The SDK config uses the `tokenHttpBaseUrl` field (resolved via `$pocKeycloakTokenHttpBase` variable) to route token HTTP through the proxy while keeping `baseUrl` as the real Keycloak issuer for JWT validation.

---

## Next Steps

- [Overview](overview.md) -- System architecture and auth flow diagrams
- [Troubleshooting](troubleshooting.md) -- Common errors and fixes
- [Configuration](configuration.md) -- Full SDK config reference
- [API Reference](api-reference.md) -- Complete SDK API documentation
