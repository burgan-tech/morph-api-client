# Configuration Reference

## Overview

Morph API Client is initialized with a JSON configuration **object** containing two top-level sections plus an optional root field:

- **`providers`** — Auth servers and their auth contexts (who issues tokens, how they are managed)
- **`hosts`** — API base URLs and their relationship to auth contexts (where tokens are used)
- **`rootCallbackAuthId`** — Optional fallback for root-path OAuth returns (`/?code=`)

```json
{
  "providers": [
    {
      "key": "morph-auth",
      "type": "oauth2",
      "baseUrl": "https://auth.example.com/realms/main",
      "contexts": [
        { "key": "device", "..." : "..." },
        { "key": "1fa", "..." : "..." },
        { "key": "2fa", "..." : "..." }
      ]
    },
    {
      "key": "google-auth",
      "type": "oauth2",
      "baseUrl": "https://accounts.google.com",
      "contexts": [
        { "key": "google", "..." : "..." }
      ]
    }
  ],
  "hosts": [
    {
      "key": "main-api",
      "baseUrl": "https://api.example.com",
      "allowedAuth": ["morph-auth/device", "morph-auth/1fa", "morph-auth/2fa"],
      "defaultAuth": "morph-auth/2fa"
    },
    {
      "key": "google-api",
      "baseUrl": "https://www.googleapis.com",
      "allowedAuth": ["google-auth/google"],
      "defaultAuth": "google-auth/google"
    }
  ],
  "rootCallbackAuthId": "morph-auth/1fa"
}
```

The configuration is validated during `MorphClient.init()`. Invalid configurations produce descriptive errors at initialization time, not at request time. In addition to the JSON config, `MorphClient.init()` requires a `plugins` array with at least an auth plugin and a storage plugin. See [Getting Started](getting-started.md) for initialization and [Writing Plugins](writing-plugins.md) for custom plugins.

---

## Top-Level Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `providers` | `ProviderConfig[]` | Yes | Auth servers and their contexts. |
| `hosts` | `HostConfig[]` | Yes | API base URLs and their allowed auth contexts. |
| `rootCallbackAuthId` | `string` | No | When an IdP redirects to the app root (`/?code=…`) instead of a dedicated callback route, `completeOAuthReturn()` exchanges the code for this `provider/context` auth id. |

---

## Provider Fields

A provider represents a single auth server. It groups related auth contexts and holds shared defaults that contexts inherit.

### Provider Top-Level

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | `string` | Yes | Unique identifier for this provider. Used as the first segment of auth ids: `morph.auth("morph-auth/device")`. |
| `type` | `string` | Yes | Auth protocol. Currently only `"oauth2"` is supported. |
| `baseUrl` | `string` | Yes | Base URL for auth endpoints. Supports `$variable` interpolation. All `endpoint` paths in contexts are resolved relative to this URL. |
| `authorizationBrowserBaseUrl` | `string` | No | If set (supports `$variable`), `getAuthorizationUrl()` uses this origin instead of `baseUrl` for browser redirects. Use when `baseUrl` is a same-origin dev proxy so the IdP login page and its assets load from the real host. |
| `tokenHttpBaseUrl` | `string` | No | If set (supports `$variable`), token endpoint, refresh, token-exchange, and logout HTTP calls use this base instead of `baseUrl`. Use for same-origin CORS proxies (e.g. Vite dev proxy) while keeping `baseUrl` as the real issuer. |

### Provider Shared Defaults

These fields can be set at provider level and are **inherited** by all contexts within the provider. A context can override any of them.

| Field | Type | Required | Description |
|---|---|---|---|
| `networkPolicy` | `NetworkPolicy` | No | Default timeout and retry for auth HTTP calls. See NetworkPolicy section. |
| `headers` | `Record<string, string>` | No | Default headers for all token endpoint requests through this provider's contexts. Values support `$variable` interpolation. |

---

## Context Fields

A context represents a single authentication scheme within a provider. Each context has its own token lifecycle, storage policy, and recovery strategy. The full auth id is `providerKey/contextKey` (e.g., `morph-auth/2fa`).

### Context Top-Level

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | `string` | Yes | Unique identifier for this auth context within the provider. Combined with provider key to form auth id: `morph-auth/device`. Also available as the `$key` interpolation variable. |
| `clientId` | `string` | No | OAuth2 client identifier. Supports `$variable` interpolation. |
| `clientSecret` | `string` | No | OAuth2 client secret. Supports `$variable` interpolation. **Never exposed** via `getProviderMeta()`. |
| `clientAuth` | `string` | No | Client authentication method: `"client_secret_post"` (default) or `"private_key_jwt"`. When `private_key_jwt`, the auth plugin calls `onClientJwtAssertion` (passed via `oauth2Plugin({ onClientJwtAssertion })`) to obtain a signed assertion. |

### identity

Defines how to extract identity claims from the access token (JWT). Used for storage key interpolation and session tracking.

| Field | Type | Required | Description |
|---|---|---|---|
| `identity.subject` | `string` | No | JWT claim name for the subject identifier. Exposed as `$subject`. Typically `"sub"`. |
| `identity.actor` | `string` | No | JWT claim name for the acting party. Exposed as `$actor`. Typically `"act"`. |

If `identity` is omitted, the context does not extract user identity from tokens. Storage keys using `$subject` or `$actor` will fail validation.

### authorization

Configuration for the OAuth2 authorization endpoint. Only needed for contexts that use the authorization code flow.

| Field | Type | Required | Description |
|---|---|---|---|
| `authorization.endpoint` | `string` | No | Path to the authorization endpoint, relative to provider `baseUrl` (or absolute URL). Supports `$variable`. Example: `"/protocol/openid-connect/auth"`. |
| `authorization.redirectUri` | `string` | No | OAuth2 redirect URI. Supports `$variable` + `$key`. Example: `"$oauthRedirectUri"`. |
| `authorization.responseType` | `string` | No | OAuth `response_type` parameter. Default: `"code"`. |
| `authorization.extraParams` | `Record<string, string>` | No | Extra query parameters for the authorize request (provider-specific). Example: `{ "access_type": "offline" }`. |

### token

Configuration for the OAuth2 token endpoint.

| Field | Type | Required | Description |
|---|---|---|---|
| `token.endpoint` | `string` | Yes | Path to the token endpoint, relative to provider `baseUrl` (or `tokenHttpBaseUrl`). Supports `$variable`. Example: `"/protocol/openid-connect/token"`. |
| `token.exchangeEndpoint` | `string` | No | Path to the token exchange endpoint. Used for RFC 8693 token exchange (step-up auth). If omitted, exchange requests use `token.endpoint`. |
| `token.exchangeSource` | `string \| string[]` | No | Auth id(s) whose access token may be exchanged for this context's tokens. When set, the SDK can **auto-exchange** during token resolution — if refresh fails or no token is available, the SDK tries exchanging from each listed source before delegating. Example: `"morph-auth/2fa"` or `["morph-auth/2fa", "morph-auth/other"]`. |

### logout

Configuration for the logout endpoint.

| Field | Type | Required | Description |
|---|---|---|---|
| `logout.endpoint` | `string` | No | Path to the logout endpoint, relative to provider `baseUrl`. Example: `"/protocol/openid-connect/logout"`. |

If omitted, `logout()` only clears tokens locally without making a server call.

### scopes

| Field | Type | Required | Description |
|---|---|---|---|
| `scopes` | `string[]` | No | OAuth2 scopes to request. Sent as the `scope` parameter in token and authorization requests. Example: `["openid", "profile", "email", "offline_access"]`. |

### pkce

| Field | Type | Required | Description |
|---|---|---|---|
| `pkce.codeChallengeMethod` | `string` | No | PKCE code challenge method (e.g., `"S256"`). When present, `getAuthorizationUrl()` generates PKCE parameters automatically. |

### audience

| Field | Type | Required | Description |
|---|---|---|---|
| `audience` | `string` | No | OAuth2 audience (resource indicator). Supports `$variable` + `$key`. Sent as the `audience` parameter in token requests (except `authorization_code` grants — some IdPs reject it). |

### sessionPolicy

Controls automatic logout based on app lifecycle events.

| Field | Type | Required | Description |
|---|---|---|---|
| `sessionPolicy.logoutOnBackgroundAfter` | `Duration` | No | Auto-logout if the app stays in the background longer than this. Example: `"1m"`. |
| `sessionPolicy.logoutOnInactivityAfter` | `Duration` | No | Auto-logout if no API requests are made through this context for this duration. Example: `"5m"`. |

### refreshPolicy

Controls proactive token refresh behavior.

| Field | Type | Required | Description |
|---|---|---|---|
| `refreshPolicy.strategy` | `"rotating" \| "static"` | No | `"rotating"`: each refresh includes a new refresh token. `"static"`: same refresh token is reused. |
| `refreshPolicy.refreshBeforeExpiry` | `Duration` | No | How long before expiry to proactively refresh. Example: `"15s"`. |

### networkPolicy

Controls timeout and retry behavior for auth-related HTTP calls. **Inherits from provider** if not set on the context.

| Field | Type | Required | Description |
|---|---|---|---|
| `networkPolicy.timeout` | `Duration` | No | Maximum time to wait for a response. Example: `"10s"`. |
| `networkPolicy.retry.count` | `number` | No | Maximum number of retry attempts on transient failure. |
| `networkPolicy.retry.delay` | `Duration` | No | Delay between retries. Example: `"200ms"`. |

### headers

| Field | Type | Required | Description |
|---|---|---|---|
| `headers` | `Record<string, string>` | No | Additional headers for token endpoint requests through this context. **Merged with** provider-level headers (context wins on conflict). Values support `$variable` + `$key` interpolation. |

### recoveryPolicy

Defines what the SDK does when it encounters an authentication failure.

| Field | Type | Required | Description |
|---|---|---|---|
| `recoveryPolicy.onUnauthorized` | `RecoveryAction` | No | Action when a 401 response is received from an API host. |
| `recoveryPolicy.onRefreshFail` | `RecoveryAction` | No | Action when a token refresh attempt fails. |

**RecoveryAction values:**

- `"refresh"` — Attempt to refresh the access token, then retry the original request.
- `"delegate"` — Invoke the host app's `onAuthRequired` callback with `delegateMetadata`.
- `"logout"` — Call the logout endpoint (if configured), clear all tokens, invoke `onLogout`.
- `"clear"` — Silently clear all tokens without server call or callback.

### delegateMetadata

Metadata passed to the host application when the SDK delegates an authentication decision. The SDK does not interpret these fields — they are passed through to `onAuthRequired`.

| Field | Type | Required | Description |
|---|---|---|---|
| `delegateMetadata.workflow` | `string` | No | Auth workflow identifier. Examples: `"device-auth"`, `"login"`, `"step-up-auth"`. |
| `delegateMetadata.grantHint` | `string` | No | Hint about the OAuth2 grant type needed. Examples: `"authorization_code"`, `"client_credentials"`, `"token_exchange"`. |
| `delegateMetadata.interaction` | `InteractionMode` | No | Expected user interaction level: `"non-interactive"`, `"interactive"`, `"redirect"`. |

### tokenTypes

Defines the token types this context manages. Every context must define at least an `access` token type.

| Field | Type | Required | Description |
|---|---|---|---|
| `tokenTypes.access` | `TokenTypeConfig` | Yes | Configuration for the access token. |
| `tokenTypes.refresh` | `TokenTypeConfig` | No | Configuration for the refresh token. |

### TokenTypeConfig

| Field | Type | Required | Description |
|---|---|---|---|
| `format` | `"jwt"` \| `"opaque"` | No | Token format. Default `"jwt"`. When `"opaque"`, the SDK skips JWT decode — `getClaims()` returns `null` and `getTokenStatus()` omits `claims`/`jwtExp`. Use `"opaque"` for providers like Google whose access tokens are not JWTs. |
| `header` | `{ name, scheme }` | No | Custom token header. Default: `{ name: "Authorization", scheme: "Bearer" }`. |
| `expiryPolicy` | `string` | Yes | How the SDK determines when the token expires: `"token"` (JWT `exp` claim), `"fixed"`, `"sliding"`. |
| `maxTtl` | `Duration` | No | Maximum TTL cap (e.g., `"5m"`). If the JWT `exp` is further out, the SDK uses this instead. |
| `storage` | `StorageConfig` | Yes | Where and how the token is stored. |

### StorageConfig

| Field | Type | Required | Description |
|---|---|---|---|
| `storage.scope` | `StorageScope` | Yes | `"device"`, `"user"`, or `"session"`. |
| `storage.type` | `StorageType` | Yes | `"memory"` or `"persistent"`. |
| `storage.protection` | `ProtectionLevel` | Yes | `"none"`, `"secure"`, or `"encrypted"`. |
| `storage.key` | `string` | Yes | Storage key. Supports `$key`, `$subject`, `$actor` interpolation. |

---

## Host Fields

Hosts define the API servers that the application calls. They reference auth ids (`provider/context`) to determine which auth contexts are valid.

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | `string` | Yes | Unique identifier for this host. Used in API calls: `morph.host("main-api")`. |
| `baseUrl` | `string` | Yes | Base URL for API requests. Example: `"https://api.example.com"`. |
| `allowedAuth` | `string[]` | Yes | List of `provider/context` auth ids valid for this host. The SDK rejects requests that use an auth id not in this list. |
| `defaultAuth` | `string` | No | Default auth id used when no explicit `auth` is specified in a request. Must be one of the `allowedAuth` entries. |
| `headers` | `Record<string, string>` | No | Default headers sent on every request to this host. Values support `$variable` interpolation. Per-request headers override these for the same header name. |

---

## Inheritance Rules

Contexts inherit from their parent provider:

1. **networkPolicy** — If a context defines `networkPolicy`, it completely replaces the provider's. No deep merge.
2. **headers** — Context headers are **merged** with provider headers. On key conflict, the context value wins.
3. **All other fields** — Only exist at the context level (no provider-level equivalent).

---

## Variable Interpolation

All string values that support interpolation use the `$variable` syntax. Variables are resolved at runtime from `MorphOptions.variables`.

### Runtime Variables

- `$key` — The context's `key` value. Always available.
- `$subject` — The subject claim from the access token via `identity.subject`. Only available after a token is stored.
- `$actor` — The actor claim from the access token via `identity.actor`. Only available after a token is stored.
- Any key from `MorphOptions.variables` — e.g., `$deviceId`, `$keycloakOidcBase`, `$googleClientId`.

**Examples:**
- `"$deviceClientId"` → resolved from `variables.deviceClientId` at init
- `"user.refresh.$subject"` → `"user.refresh.user-123"` (where `user-123` is the JWT `sub` claim)
- `"$keycloakOidcBase/token"` → `"http://localhost:8080/realms/morph/protocol/openid-connect/token"`

---

## Duration Format

All duration fields accept a string with a numeric value and unit suffix:

- `"200ms"` — milliseconds
- `"10s"` — seconds
- `"1m"` — minutes
- `"1h"` — hours

---

## Sample Config Explained

See `docs/poc/poc-config.json` for the full PoC configuration.

### Provider: morph-auth

Keycloak auth server. Shared defaults: timeout, headers.

- **device** — Non-interactive device-level auth (`client_credentials`). Persistent device-scoped storage with `private_key_jwt` client auth.
- **2fa** — Interactive login (`authorization_code`). Rotating refresh with 15s proactive window. 401 → refresh, refresh fail → delegate.
- **1fa** — Session-level token via token exchange from 2fa (`token.exchangeSource: "morph-auth/2fa"`). Auto-exchanged during resolution.

### Provider: google-auth

Google OAuth2 with PKCE. Absolute authorization URL, token endpoint via variables.

- **google** — Redirect-based auth with PKCE. Session-scoped memory-only tokens.

### Host: main-api

Mock API at localhost:3000. Accepts `morph-auth/device`, `morph-auth/1fa`, `morph-auth/2fa`. Defaults to `morph-auth/2fa`. Sends `X-Device-Id` and `X-Installation-Id` headers.

### Host: google-api

Google APIs. Accepts only `google-auth/google`.

---

## Scope-Based Authorization

The SDK's role in scope management is limited to **requesting scopes at token time**. It does not validate or enforce scopes at API call time — that is the API server's responsibility.

Different permission levels are modeled as different auth contexts, each with its own scopes:

| Context | Scopes | Access Level |
|---|---|---|
| `device` | (none or minimal) | Public API, pre-login content |
| `1fa` | `openid profile email offline_access` | User profile, read accounts |
| `2fa` | (elevated via token exchange) | Transfers, payments, sensitive ops |
| `google` | `openid profile email` | Identity verification |

Scope escalation is handled through context escalation (device → 2fa → 1fa via exchange), not by re-requesting the same token with different scopes.
