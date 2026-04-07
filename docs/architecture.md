# Architecture

## Overview

Morph API Client is a **config-driven, multi-context HTTP client** with built-in OAuth2 token lifecycle management. The current implementation targets **TypeScript**; Dart/Flutter parity is planned with an identical JSON config schema and mirrored public API.

The SDK is not a standalone token manager that hands tokens to a separate HTTP client. It **is** the HTTP client. Every outgoing request flows through an authentication pipeline that resolves, attaches, and — when necessary — refreshes tokens transparently. The host application interacts with Morph as it would any HTTP client, with the added guarantee that authentication concerns are handled internally.

## Design Principles

- **Config-driven**: All auth behavior is declared in a JSON configuration object with two top-level sections: `providers` (auth servers and their contexts) and `hosts` (API base URLs). No auth logic is hardcoded in the host application.
- **Multi-context**: Multiple independent auth contexts coexist (e.g., device credentials, user login, step-up auth, external providers). Each context has its own token lifecycle, storage policy, and recovery strategy. Contexts are grouped under auth providers.
- **Separation of concerns**: Auth providers (who issues the tokens) are decoupled from API hosts (where the tokens are used). Multiple hosts can share the same provider, and a single host can accept tokens from multiple providers.
- **Callback delegation**: When the SDK cannot resolve authentication on its own (expired tokens with no refresh path, step-up requirements), it delegates to the host application via registered callbacks. The SDK never renders UI or initiates interactive flows itself.
- **Platform-agnostic core**: The domain model, config parsing, token resolution logic, and HTTP pipeline are identical across planned platforms. Only storage backends and HTTP transport are platform-specific, injected via interfaces.
- **Proactive over reactive**: Tokens are refreshed *before* they expire when a `refreshPolicy` is configured. The SDK does not wait for a 401 to discover an expired token.

## System Layers

```
┌──────────────────────────────────────────────────────┐
│                   Host Application                    │
│   (registers callbacks, makes HTTP calls via SDK)     │
└───────────────────────┬──────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────┐
│              MorphClient  (public facade)              │
│   init() · host() · auth() · getTokenStatus()         │
│   getAuthorizationUrl() · completeOAuthCallback()     │
└───────┬──────────────────────┬───────────────────────┘
        │                      │
┌───────▼───────┐     ┌───────▼────────┐
│  HostClient    │     │   AuthHandle    │
│  per host key  │     │  per auth id    │
└───────┬───────┘     └───────┬────────┘
        │                      │
┌───────▼──────────────────────▼───────────────────────┐
│            MorphRuntime  (coordinator, ~260 lines)     │
│   config queries · OAuth flow · delegates to modules   │
└───────┬──────────────────────┬───────────────────────┘
        │                      │
┌───────▼───────────┐ ┌───────▼────────────────────────┐
│   HostPipeline     │ │      TokenLifecycle             │
│   (~180 lines)     │ │      (~400 lines)               │
│                    │ │                                  │
│  fetchWithTrace    │ │  executeGrant (consolidated)     │
│  401 recovery      │ │  refresh · client_creds ·        │
│  timeout / abort   │ │  token exchange · submitCode     │
│  trace emission    │ │  locks · resolve access token    │
│                    │ │  logout · 401 recovery           │
└───────┬───────────┘ └───────┬────────────────────────┘
        │                      │
        │              ┌───────▼──────────┐
        │              │   TokenVault      │
        │              │   storage I/O     │
        │              └───────┬──────────┘
        │                      │
┌───────▼──────────────────────▼───────────────────────┐
│              Platform Abstractions                     │
│   StorageProvider · NetworkDelegate                    │
│   (injected at init, platform-specific impls)          │
└──────────────────────────────────────────────────────┘
```

### Module Responsibilities

- **MorphRuntime** — Thin coordinator. Owns config queries (`getHost`, `parseAuthRef`, `getTokenStatus`, `getProviderMeta`), OAuth flow orchestration (`getAuthorizationUrl`, `completeOAuthCallback`, `completeOAuthReturn`), and delegates token/HTTP work to sub-modules.
- **TokenLifecycle** — All token operations: consolidated `executeGrant` helper (replaces 4 separate grant functions), lock management, refresh, client credentials, token exchange, `resolveAccessToken` (the core resolution algorithm), and `handle401Recovery` (for the host pipeline's 401 path).
- **HostPipeline** — Host HTTP requests: URL resolution, header merging, `fetchWithTrace` (timeout + abort + trace), 401 recovery delegation, response parsing, and sign/decrypt delegate calls.
- **TokenVault** — Storage I/O: key interpolation, serialization, and delegation to the injected `StorageProvider`.

### Dependency Graph

```
MorphRuntime ──► TokenLifecycle
MorphRuntime ──► HostPipeline
HostPipeline ──► TokenLifecycle  (resolveAccessToken, handle401Recovery)
AuthHandle   ──► MorphRuntime    (parseAuthRef) + TokenLifecycle (token ops)
HostClient   ──► HostPipeline    (hostFetch)
```

No circular dependencies. `TokenLifecycle` is a leaf dependency.

## HTTP Pipeline

Every request follows this pipeline:

1. **Auth resolution** — `HostPipeline.hostFetch` determines the auth context to use (host's `defaultAuth` or explicit override). Validates against `host.allowedAuth`. Calls `TokenLifecycle.resolveAccessToken` to obtain a valid access token.

2. **Request building** — Resolves URL from host `baseUrl` + path. Merges host headers (`$variable` interpolated), request headers, and the access token header (`Authorization: Bearer <token>` or context-configured header name/scheme).

3. **Fetch with trace** — Single `fetch()` call with timeout via `AbortController`. On completion (success or failure), emits a structured `MorphHttpTraceEvent` via `onHttpTrace` callback.

4. **401 recovery** — If the response is 401 and `recoveryPolicy.onUnauthorized === 'refresh'`, delegates to `TokenLifecycle.handle401Recovery` (attempts refresh in a lock, clears vault on failure). Then calls `resolveAccessToken` again and retries the request **once**.

5. **Delegate 401** — If the response is (still) 401 and `recoveryPolicy.onUnauthorized === 'delegate'`, fires `onAuthRequired` and throws `AuthError`.

6. **Response handling** — Parses response text as JSON when `Content-Type` is `application/json`. Optionally decrypts via `onDecryptResponse`. Returns `MorphResponse<T>`.

## Auth Provider Model

Auth contexts are grouped under **providers**. A provider represents a single auth server and holds shared configuration inherited by its contexts.

```
providers
├── morph-auth  (baseUrl: .../realms/morph)
│   ├── device   (non-interactive, device-scoped)
│   ├── 2fa      (interactive login, session-scoped)
│   └── 1fa      (session token via exchange from 2fa, user-scoped)
│
└── google-auth (baseUrl: accounts.google.com)
    └── google   (redirect, PKCE, session-scoped)
```

While contexts within a provider share the auth server, each context operates independently with its own token lifecycle, storage policies, and recovery strategies.

### Context Descriptions

- **device** — Machine-level credentials. Acquired non-interactively (client credentials). Stored persistently at device scope. Used for unauthenticated-user API calls (public content, pre-login flows).

- **2fa** — Interactive user login. Acquired via authorization code flow (browser redirect to Keycloak). Session-scoped in-memory tokens. Subject to session timeouts (background, inactivity).

- **1fa** — Long-lived session token. Acquired via token exchange from the 2fa context (`token.exchangeSource: "morph-auth/2fa"`). User-scoped persistent encrypted storage. Auto-exchanged during token resolution.

- **google** — External OAuth2 provider. Full authorization code flow with PKCE. Session-scoped tokens.

The SDK does not enforce a hierarchy between contexts — each operates independently. The progressive chain (device → 2fa login → 1fa via exchange) is expressed through the host application's auth flow logic and the `delegateMetadata.grantHint` values.

## Host Model

Hosts represent the API servers that the application calls. Each host has:

- A `baseUrl` where API requests are sent
- An `allowedAuth` list of `provider/context` auth ids valid for this host
- A `defaultAuth` context used when no explicit auth is specified
- Optional `headers` with `$variable` interpolation

```
hosts
├── main-api     (baseUrl: localhost:3000)
│   └── allowedAuth: [morph-auth/device, morph-auth/1fa, morph-auth/2fa, google-auth/google]
│
└── google-api   (baseUrl: googleapis.com)
    ├── allowedAuth: [google-auth/google]
    └── defaultAuth: google-auth/google
```

The `allowedAuth` list enables **request-time validation**: if a request through `google-api` specifies `auth: "morph-auth/2fa"`, the SDK rejects it because that auth id is not in `allowedAuth`. This catches misconfiguration early.

## Project Structure

```
morph-api-client/
├── core/                            # morph-api-client npm package
│   └── src/
│       ├── client/                  # MorphClient, HostClient, AuthHandle (facades)
│       ├── config/                  # validate (CtxRef, hostByKey), interpolate ($variable)
│       ├── tokens/                  # TokenLifecycle, TokenVault
│       ├── http/                    # HostPipeline
│       ├── oauth/                   # tokenHttp (grant HTTP), oauthAuthorize (URL builder)
│       ├── util/                    # jwt, expiry, url, oauthState, oauthReturn, httpTrace
│       ├── storage/                 # createBrowserSessionStorage, createBrowserLocalStorage
│       ├── runtime.ts              # MorphRuntime coordinator
│       ├── types.ts                # Public interfaces
│       ├── errors.ts               # Error classes
│       └── index.ts                # Public exports
├── poc/
│   ├── ts-vue/                     # Vue 3 PoC app
│   ├── keycloak/                   # Docker Keycloak realm
│   └── mock-api/                   # Mock REST API
└── docs/                           # Design & API documentation
```

## Transport Security

The SDK owns the HTTP transport layer — it builds requests, attaches tokens, handles retries. However, two transport-level concerns are **platform-specific** and must come from the host application:

- **SSL Certificate Pinning** — Pin values must be embedded in the app binary, not delivered via remote config.
- **Proxy Configuration** — Needed for debug proxies during development.

The SDK resolves this via the `NetworkDelegate` interface. The delegate is called **lazily on first request to each host** (not at init time) to minimize startup latency:

```
First request to api.example.com:
│
├─ SDK: networkDelegate.getNetworkConfig("api.example.com")
├─ Host app: returns { certificatePins: ["sha256/..."], proxy: null }
├─ SDK: configures internal HTTP client for this hostname
├─ SDK: caches the result
└─ SDK: proceeds with the request

Subsequent requests:
└─ SDK: uses cached config, no delegate call
```

If no `NetworkDelegate` is provided, or if it returns `null` for a hostname, the SDK proceeds without pinning or proxy — standard TLS validation applies.

## Key Design Decisions

### Why separate providers from hosts?

Auth providers (who issues the tokens) and API hosts (where the tokens are used) have a many-to-many relationship. Multiple API hosts can share the same auth provider. A single host can accept tokens from different providers. Coupling them 1:1 would force duplication or artificial constraints.

### Why config-driven?

Auth requirements change frequently — new providers, adjusted timeouts, different recovery strategies per environment. A declarative config means these changes require no code modifications. The same SDK binary serves staging, production, and partner environments with different configs.

### Why callback delegation instead of built-in auth flows?

Authentication UX varies wildly: biometric prompts, WebView redirects, OTP screens, external provider redirects. The SDK cannot and should not own these flows. Instead, it tells the host app *what* is needed (`delegateMetadata`) and the host app decides *how* to fulfill it.

### Why per-context storage policies?

Different tokens have different security and lifecycle requirements:
- Device tokens are long-lived and only need secure storage.
- 2fa tokens are session-scoped and can live in memory (ephemeral login session).
- 1fa access and refresh tokens are user-scoped and need persistent encrypted storage to survive app restarts.
- Google tokens are session-scoped and can live in memory.

A single storage strategy cannot serve all of these correctly.

### Why the runtime split (TokenLifecycle + HostPipeline)?

The original `runtime.ts` was a 1088-line "god class" handling config queries, token lifecycle, OAuth flow, and host HTTP in a single file. The split into focused modules:
- **TokenLifecycle** (404 lines) — cohesive token operations
- **HostPipeline** (181 lines) — cohesive HTTP operations
- **MorphRuntime** (262 lines) — thin coordinator

reduces cognitive load, eliminates code duplication (consolidated `executeGrant` replaced 4 repetitive grant functions), and makes the dependency graph explicit.
