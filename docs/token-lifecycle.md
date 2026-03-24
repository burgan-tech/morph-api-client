# Token Lifecycle

This document describes how the SDK manages tokens throughout their lifetime: resolution, storage, refresh, recovery, exchange, and logout.

## Auth Context Selection

When a host request specifies `auth` as a priority list (e.g., `['morph-auth/2fa', 'morph-auth/1fa']`), the SDK tries each auth id in order. For each, it attempts to resolve an access token; on failure it moves to the next. The first successful resolution wins.

When `auth` is a single string (or omitted for `defaultAuth`), this step is skipped — the SDK uses that single auth id directly.

## Token Resolution

Every HTTP request through the SDK triggers token resolution for the associated auth context. The resolution algorithm runs inside `TokenLifecycle.resolveAccessToken`, protected by a per-auth-id lock.

```
resolveAccessToken(authId, mode)
│
├─ 1. Read access token from storage (via TokenVault)
│     key = interpolate(tokenTypes.access.storage.key)
│
├─ 2. Token found and not near expiry?
│     ├─ Yes → return token ✓
│     └─ No  → continue
│
├─ 3. Refresh token available?
│     ├─ Yes → attempt refresh (step 4)
│     └─ No  → go to step 5
│
├─ 4. Refresh
│     ├─ Success → store new tokens, return access token ✓
│     └─ Failure → clear vault, check exchangeSources (step 6)
│
├─ 5. Client credentials re-acquire?
│     (expired token, no refresh, grantHint=client_credentials)
│     ├─ Yes → fetch new client_credentials token → return ✓
│     └─ No  → continue to step 6
│
├─ 6. Token exchange from exchangeSource?
│     (config: token.exchangeSource = ["morph-auth/2fa", ...])
│     ├─ For each source: resolve source token → exchange → return ✓
│     └─ All failed → step 7
│
├─ 7. Recovery
│     ├─ recoveryPolicy.onRefreshFail = "delegate"
│     │   → fire onAuthRequired(authId, metadata)
│     │   → throw AuthError('delegation_required')
│     └─ Otherwise → throw AuthError('no_token' or 'refresh_failed')
```

### Consolidated Token Grant

All token endpoint calls (authorization_code, refresh_token, client_credentials, token_exchange) go through a single `executeGrant` method in `TokenLifecycle`. This ensures consistent handling of:
- Client authentication (`client_secret_post` or `private_key_jwt`)
- Header merging (provider + context headers)
- Audience interpolation (skipped for `authorization_code` — some IdPs reject it)
- Scope attachment
- `onTokenExchange` delegate check

### autoAcquireNonInteractive

When `MorphOptions.autoAcquireNonInteractive` is `true` and `onAuthRequired` fires for a context with `interaction: 'non-interactive'`, the SDK automatically calls `acquireWithClientCredentials` for that context. This avoids requiring the host app to handle device-token acquisition in every `onAuthRequired` implementation.

### Proactive vs. Reactive Refresh

**Proactive refresh** — The token is still valid but approaching expiry (`refreshPolicy.refreshBeforeExpiry`). The SDK refreshes the token within the lock and returns the new token. The caller experiences minimal delay.

**Reactive refresh** — The token is already expired. The request is blocked until the refresh completes or fails. If refresh fails, recovery policies take over.

### SDK logging (`onLog`)

Successful **refresh**, **client_credentials renewal**, **token exchange**, **authorization_code** storage, and **401-triggered refresh** emit **`info`** messages (e.g. `Access token refreshed` with `{ authId }`). Failures use **`warn`** / **`error`**.

### Client credentials without a refresh token

Contexts that only use `grant_type=client_credentials` (e.g. `delegateMetadata.grantHint: "client_credentials"`) usually get a **short-lived access token** and **no refresh token**. If the token has expired, the SDK **requests a new access token with client_credentials again** during resolution (no user interaction needed).

## Storage Key Interpolation

Storage keys support runtime variables that are resolved when reading or writing tokens:

- `$key` — Replaced with the context's `key` value. Always available.
- `$subject` — Replaced with the subject claim from the current access token. Requires `identity.subject` to be configured.
- `$actor` — Replaced with the actor claim from the current access token. Requires `identity.actor` to be configured.

**Resolution order matters.** When storing a token for the first time, the SDK decodes the access token JWT to extract `$subject` and `$actor` before computing the storage key.

### Examples

| Config Key Pattern | Context | Resolved Key |
|---|---|---|
| `"device-access-token"` | device | `"device-access-token"` |
| `"1fa.access.$subject"` | 1fa, sub=u42 | `"1fa.access.u42"` |
| `"2fa.refresh.$subject"` | 2fa, sub=u42 | `"2fa.refresh.u42"` |

## Token Storage

Tokens are stored using the `StorageProvider` interface injected at init time. The SDK passes the full `StorageConfig` from the JSON config to every call, so the delegate has all the context it needs.

### Storage Flow

```
persistAndNotify(authId, ref, tokenSet)
│
├─ 1. Decode access token JWT (extract claims for interpolation)
│
├─ 2. For each token type (access, refresh):
│     ├─ Interpolate storage key
│     └─ Write: { value, expiresAt, scope } via StorageProvider
│
└─ 3. Notify onTokenChange callback (if registered)
```

### Scope Behavior

- **device scope** — Tokens persist across user sessions. Not cleared by `logout()` of user contexts.
- **user scope** — Tokens are logically tied to a user identity. Cleared when the user logs out.
- **session scope** — Tokens exist only for the current session. Lost if storage type is `memory` and the app restarts.

## Refresh Flow

When a token refresh is needed, the SDK executes the following flow within a per-auth-id lock:

```
executeRefresh(authId, ref, refreshToken)
│
├─ 1. Build request via executeGrant:
│     grant_type=refresh_token, refresh_token=<value>
│     headers: provider + context headers
│     audience, scope (from config)
│
├─ 2. Call onTokenExchange delegate (may override)
│
├─ 3. POST to tokenUrl (tokenHttpBaseUrl or baseUrl + token.endpoint)
│
├─ 4. Response
│     ├─ Success → return new TokenSet
│     │   If strategy=static: preserve original refresh token
│     │   If strategy=rotating: use new refresh token from response
│     │
│     └─ Failure → throw (caller handles recovery)
│
└─ 5. Concurrency: lock prevents parallel refresh for same auth id
```

### Rotating vs. Static Refresh

- **rotating** — Each refresh response includes a new refresh token. The old refresh token is immediately invalidated server-side. The SDK stores the new refresh token atomically with the new access token.
- **static** — The same refresh token is reused for all refreshes until it expires independently.

## Token Exchange

For contexts with `token.exchangeSource` or `token.exchangeEndpoint`, the SDK supports RFC 8693 token exchange — acquiring a new token by presenting an existing token from a different context.

```
exchangeToken(sourceAuthId → targetAuthId)
│
├─ 1. Resolve access token from source context
│
├─ 2. POST via executeGrant to target's exchange endpoint:
│     grant_type=urn:ietf:params:oauth:grant-type:token-exchange
│     subject_token=<source access token>
│     subject_token_type=urn:ietf:params:oauth:token-type:access_token
│
├─ 3. Store resulting tokens in target context
│
└─ 4. Return new access token
```

### Auto-Exchange in Token Resolution

When `token.exchangeSource` is configured on a context, the SDK can perform exchange **automatically** during token resolution (step 6 in the resolution flowchart). This happens when:
- The context has no token, or
- Refresh failed and exchange sources are available

The SDK tries each listed source in order until one succeeds. If all fail, recovery policies take over.

## Recovery

When the SDK encounters an authentication failure, it follows the context's `recoveryPolicy`.

### On 401 Response (onUnauthorized)

```
handle401Recovery(authId, ref)   [inside HostPipeline]
│
├─ "refresh"
│   ├─ Lock authId
│   ├─ Load tokens from vault
│   ├─ Has refresh token?
│   │   ├─ Yes → attempt refresh → persist on success
│   │   └─ No  → fire onAuthRequired
│   ├─ Then: resolveAccessToken → retry request once
│   └─ Failure → emitRefreshFailCallbacks
│
├─ "delegate"
│   ├─ Fire onAuthRequired(authId, delegateMetadata)
│   └─ Throw AuthError('delegation_required')
│
├─ "logout"
│   ├─ POST to logout endpoint (if configured)
│   ├─ Clear all tokens for this context
│   └─ Invoke onLogout(authId, "unauthorized")
│
└─ "clear"
    └─ Clear all tokens for this context (no server call)
```

### On Refresh Failure (onRefreshFail)

```
emitRefreshFailCallbacks(ref, authId, mode)
│
├─ "delegate"
│   └─ Fire onAuthRequired(authId, delegateMetadata)
│
├─ "logout"
│   ├─ POST to logout endpoint
│   ├─ Clear tokens
│   └─ Invoke onLogout(authId, "refresh_failed")
│
└─ "clear"
    └─ Clear tokens silently
```

Additionally, `onLogout(authId, 'refresh_failed')` is always called when refresh fails (regardless of the specific recovery action).

### Retry Semantics

When `onUnauthorized = "refresh"` succeeds, the original request is retried **exactly once** with the new token. If the retry also returns 401, the SDK does **not** enter a refresh loop.

## Session Monitoring

Contexts with `sessionPolicy` are subject to automatic logout based on app lifecycle events.

### Background Timeout

```
logoutOnBackgroundAfter: "1m"

App goes to background → start timer
├─ Returns before timer? → cancel, no action
└─ Timer fires → mark for logout → on next foreground:
    ├─ POST to logout endpoint
    ├─ Clear tokens
    └─ Invoke onLogout(authId, "session_expired")
```

### Inactivity Timeout

```
logoutOnInactivityAfter: "5m"

After each request → reset timer
└─ Timer fires (no requests for duration):
    ├─ POST to logout endpoint
    ├─ Clear tokens
    └─ Invoke onLogout(authId, "session_expired")
```

## Logout Flow

When `morph.auth(authId).logout()` is called by the host app, or when the SDK triggers an automatic logout:

```
logout(authId, reason)
│
├─ 1. Logout endpoint configured?
│     ├─ Yes → POST to tokenHttpBaseUrl + logout.endpoint
│     │        Include refresh token if available
│     │        Apply networkPolicy (best-effort, don't block on failure)
│     └─ No  → skip server call
│
├─ 2. Clear all tokens for this context via vault
│
├─ 3. Invoke onTokenChange(authId, null)
│
└─ 4. Invoke onLogout(authId, reason)
      reason: "user_initiated" | "unauthorized" |
              "refresh_failed" | "session_expired"
```

### Provider-Level Logout

`morph.auth('morph-auth').logout()` iterates all contexts under the provider and calls `logout` on each one sequentially.

### Logout is Best-Effort for Server Calls

The server-side logout call follows `networkPolicy` but does **not** block the local token clearing. If the server call fails, tokens are still cleared locally and `onLogout` still fires. This ensures the user is never stuck in a "logged in" state due to a network issue.
