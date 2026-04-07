# API Reference

This document defines the public API surface for the Morph API Client SDK (TypeScript). Every method and property includes a practical usage example.

> **Dart/Flutter parity is planned.** The public API will mirror TS with language-appropriate idioms (`snake_case`, `Future<T>`).

Auth contexts are referenced using the `provider/context` format (e.g., `'burgan-auth/2fa'`). This is unambiguous — the same context name can exist in different providers.

---

## MorphClient

The main entry point. Created via the static `init` factory.

### MorphClient.init

Creates and configures the SDK. Validates the config, initializes all providers, auth contexts, hosts, refresh schedulers, and session monitors.

```typescript
import { MorphClient } from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';
import { browserStoragePlugin } from '@morph/browser-storage';
import { loggerPlugin } from '@morph/logger';
import config from './morph-config.json';

const logger = loggerPlugin({ level: 'info' });

const morph = MorphClient.init(config, {

  plugins: [
    logger,
    oauth2Plugin({
      logger,
      storage: browserStoragePlugin({ prefix: 'myapp:tk:', logger }),
      callbacks: {
        onAuthRequired: (authId, metadata) => {
          if (metadata.interaction === 'non-interactive') {
            morph.auth(authId).acquireWithClientCredentials();
          } else if (metadata.interaction === 'interactive') {
            router.navigate('/login', { authId });
          }
        },
        onTokenChange: (authId, tokens) => {
          if (authId === 'burgan-auth/1fa') setIsLoggedIn(!!tokens);
          if (authId === 'burgan-auth/2fa') setCanTransfer(!!tokens);
        },
      },
      variables: {
        deviceClientId: 'abc-123',
        deviceId: getDeviceId(),
        installationId: getInstallationId(),
      },
      autoAcquireNonInteractive: true,
    }),
  ],

  // --- Core-level options (shared, not plugin-specific) ---

  networkDelegate: {
    async getNetworkConfig(hostname) {
      const PINS: Record<string, string[]> = {
        'api.burgan.com.tr':     ['sha256/AAAA...', 'sha256/BBBB...'],
        'payment.burgan.com.tr': ['sha256/CCCC...', 'sha256/DDDD...'],
      };
      return {
        certificatePins: PINS[hostname] ?? undefined,
        proxy: __DEV__ ? { url: 'http://localhost:8888' } : undefined,
      };
    },
  },

  onSignPayload: async (payload, authId) => {
    return await cryptoModule.sign(payload, privateKey);
  },

  onDecryptResponse: async (encryptedBody, authId) => {
    return await cryptoModule.decrypt(encryptedBody, decryptionKey);
  },
});
```

Throws `ConfigValidationError` if the config is invalid.

**What goes where:**
- **Logger** (`loggerPlugin({ ... })`): Create once, pass to every plugin via `logger` option. Controls log level, prefix, and output format.
- **Plugin options** (`oauth2Plugin({ ... })`): `logger`, `storage`, `callbacks`, `variables`, `onTokenExchange`, `onClientJwtAssertion`, `autoAcquireNonInteractive`
- **Core options** (`MorphOptions`): `onLog`, `onHttpTrace`, `onSignPayload`, `onDecryptResponse`, `networkDelegate`, shared `variables` (like `deviceId`)

Include **`deviceId`** and **`installationId`** in `variables` when the JSON config interpolates them (e.g. `X-Device-Id`, `X-Installation-Id`). On mobile, `installationId` is usually a GUID created on first install after download; the Vue web PoC simulates that with browser-local and session-scoped ids.

---

### morph.host(key)

Returns a `HostClient` bound to a specific API host. Create once, reuse everywhere.

```typescript
const api = morph.host('main-api');         // https://api.burgan.com.tr
const payments = morph.host('payment-api'); // https://payment.burgan.com.tr

const accounts = await api.get('/accounts');
const receipt = await payments.post('/pay', { amount: 100 });
```

Throws `UnknownHostError` if the key does not match any configured host.

---

### morph.auth(authId)

Returns an `AuthHandle` for managing tokens. Accepts two formats:

- `'burgan-auth/1fa'` — specific context
- `'burgan-auth'` — all contexts under the provider (provider-level operations)

```typescript
// Context-level: specific auth context
await morph.auth('burgan-auth/1fa').submitCode(authorizationCode);
await morph.auth('burgan-auth/1fa').exchangeToken('burgan-auth/2fa');
await morph.auth('burgan-auth/1fa').hasValidToken();  // async, may refresh
await morph.auth('burgan-auth/1fa').refreshTokens();  // manual refresh_token (or client_credentials re-acquire)
await morph.auth('burgan-auth/1fa').peekTokens();      // stored tokens only, no refresh (debug / JWT decode)
await morph.auth('burgan-auth/1fa').logout();

// Provider-level: all contexts under the provider
await morph.auth('burgan-auth').logout();          // logout device + 1fa + 2fa at once
await morph.auth('burgan-auth').clearTokens();     // clear all, silent
await morph.auth('burgan-auth').hasValidToken();   // true if ANY context can authenticate
```

Throws `UnknownContextError` if the authId does not match any configured provider or provider/context.

---

### morph.getTokenStatus()

Returns one row per configured `provider/context`: vault snapshot only (no token endpoint). Includes `grantHint` from config, `accessLikelyValid`, access JWT `claims` when decodable, and refresh JWT `refreshClaims` when the stored refresh string looks like a JWT (opaque refresh tokens have no payload to show).

```typescript
const rows = await morph.getTokenStatus();
for (const r of rows) {
  console.log(r.authId, r.accessLikelyValid, r.jwtExp, r.hasRefreshToken, r.grantHint);
}
```

---

### morph.getProviderMeta(providerKey)

Returns a **sanitized** copy of one provider from config: `baseUrl`, `networkPolicy`, `headers`, and every **context** with `authId`, endpoints, `refreshPolicy`, `tokenTypes`, etc. **`clientSecret` is never included.** Throws `UnknownProviderError` if `providerKey` is not in config.

```typescript
const meta = morph.getProviderMeta('morph-auth');
console.log(meta.contexts.map((c) => c.authId));
```

Use for debug panels and PoC “provider config” views — not a substitute for securing secrets in production builds.


### morph.isAuthContextReady(authId)

Returns whether a `provider/context` auth id is configured for an OAuth2 **authorize** redirect: `delegateMetadata.grantHint === 'authorization_code'`, resolvable `clientId` / `clientSecret` via `MorphOptions.variables`, and non-empty `authorization.endpoint` + `authorization.redirectUri` (also interpolated with `variables`).

### morph.isProviderEnvReady(providerKey)

Returns true if **every** context on that provider with `grantHint` `authorization_code` passes `isAuthContextReady`.

### morph.getAuthorizationUrl(authId, opts?)

Builds the full browser URL for the IdP authorize step from `ProviderConfig.baseUrl`, `AuthContextConfig.authorization` (`endpoint`, `redirectUri`, optional `responseType`, `extraParams`), `scopes`, and interpolated `clientId` / `redirectUri`. Optional `opts.state` defaults to an SDK-encoded value that embeds `authId` (used by `completeOAuthCallback`). The host app should update `variables` (e.g. current `redirect_uri`) before calling if the tab origin can change in dev.

### morph.completeOAuthCallback(params)

Generic OAuth callback handler. Decodes `authId` from the SDK-encoded `state` parameter, exchanges the `code`, and returns the result. Works from any route — dedicated `/oauth/callback` pages or the app root. If `state` is missing or not SDK-encoded, falls back to `MorphConfig.rootCallbackAuthId`.

```typescript
const result = await morph.completeOAuthCallback({
  code: route.query.code,
  state: route.query.state,
  error: route.query.error,
  errorDescription: route.query.error_description,
});
if (result.status === 'success') router.replace('/');
```

### morph.completeOAuthReturn()

Convenience for the **app root** (`/?code=` or `?error=`). Reads query params from `window.location`, delegates to `completeOAuthCallback`, and strips OAuth params from the address bar via `history.replaceState`. Returns `{ status: 'none' }` if there is no `code`/`error` on the root path. Requires a browser (`window`).

```typescript
const r = await morph.completeOAuthReturn();
if (r.status === 'success') console.log(r.message);
```

### morph.dispose()

Tears down the client. Cancels all refresh schedulers, session monitors, and pending requests.

```typescript
useEffect(() => {
  return () => morph.dispose();
}, []);
```

---

## HostClient

A host-bound HTTP client returned by `morph.host(key)`. Requests use the host's `baseUrl` and `defaultAuth` unless overridden.

### HTTP Methods

#### get — Fetch data

```typescript
const api = morph.host('main-api');

// Simple GET with default auth (burgan-auth/2fa from config)
const accounts = await api.get('/accounts');
console.log(accounts.body);         // [{ id: 'ACC-001', balance: 15420.50 }, ...]
console.log(accounts.resolvedAuth); // 'burgan-auth/2fa'

// GET with query parameters
const filtered = await api.get('/transactions', {
  queryParams: { from: '2024-01-01', to: '2024-03-01', limit: '50' },
});

// GET with auth fallback: prefer 2fa, accept 1fa
const notifications = await api.get('/notifications/count', {
  auth: ['burgan-auth/2fa', 'burgan-auth/1fa'],
});
```

#### post — Create or submit data

```typescript
const transfer = await api.post('/transfers', {
  fromAccount: 'ACC-001',
  toAccount: 'ACC-002',
  amount: 500.00,
  currency: 'TRY',
  description: 'Rent payment',
}, { auth: 'burgan-auth/2fa' });

console.log(transfer.body.transferId); // 'TRF-12345'
```

#### put — Replace a resource

```typescript
await api.put('/profile', {
  name: 'Ahmet Yilmaz',
  email: 'ahmet@example.com',
  phone: '+905551234567',
}, { auth: 'burgan-auth/1fa' });
```

#### patch — Partially update a resource

```typescript
await api.patch('/profile/preferences', {
  pushNotifications: true,
  emailDigest: 'weekly',
}, { auth: ['burgan-auth/2fa', 'burgan-auth/1fa'] });
```

#### delete — Remove a resource

```typescript
await api.delete('/beneficiaries/BEN-789', { auth: 'burgan-auth/2fa' });
```

#### head — Check resource existence or get metadata

```typescript
const health = await api.head('/health');
console.log(health.statusCode); // 200
console.log(health.headers['x-response-time']); // '12ms'

const docCheck = await api.head('/documents/DOC-123', { auth: 'burgan-auth/1fa' });
if (docCheck.statusCode === 200) {
  console.log(`Document exists, size: ${docCheck.headers['content-length']} bytes`);
}
```

#### options — Check CORS or supported methods

```typescript
const opts = await api.options('/transfers');
console.log(opts.headers['allow']); // 'GET, POST, OPTIONS'
```

#### request — Full control

```typescript
const res = await api.request({
  method: isUpdate ? 'PUT' : 'POST',
  path: '/orders/ORD-123',
  auth: 'burgan-auth/2fa',
  body: orderData,
  headers: { 'X-Idempotency-Key': crypto.randomUUID() },
  timeout: '30s',
});
```

---

### api.key

```typescript
const api = morph.host('main-api');
console.log(api.key); // 'main-api'
```

### api.defaultAuth

```typescript
console.log(api.defaultAuth); // 'burgan-auth/2fa'
```

---

## AuthHandle

Manages tokens for a single auth context. Created via `morph.auth(authId)`. Three methods to acquire tokens — each for a different grant type. The SDK owns all token endpoint calls.

### auth.submitCode(code, opts?)

Submits an authorization code. The SDK exchanges it at the token endpoint using credentials from config (`clientId`, `clientSecret`, `audience`, `redirectUri`). All token endpoint calls include client credentials automatically — the host app never needs to pass them per-call. Resulting tokens are stored in **this** context. Optional `opts.redirectUriOverride` sends that exact string as `redirect_uri` (must match the authorize request). Duplicate in-flight exchanges for the same `code` are deduplicated.

```typescript
// User completed login, browser redirect returned a code
await morph.auth('burgan-auth/1fa').submitCode(authorizationCode);
// SDK calls POST burgan-auth.baseUrl + token.endpoint with:
//   grant_type=authorization_code, code=..., redirect_uri=<from config>,
//   client_id=<from config>, audience=<from config>
// Stores access_token + refresh_token in burgan-auth/1fa

// With PKCE (edevlet)
await morph.auth('edevlet-auth/edevlet').submitCode(code, { codeVerifier: pkceVerifier });
```

---

### auth.acquireWithClientCredentials()

For non-interactive contexts. The SDK calls the token endpoint with `clientId` + `clientSecret` from config (resolved via `$variable`). Resulting tokens are stored in **this** context.

```typescript
await morph.auth('burgan-auth/device').acquireWithClientCredentials();
// SDK calls POST with grant_type=client_credentials
//   client_id=<config.clientId>, client_secret=<config.clientSecret>,
//   audience=<config.audience>

// Config for device context:
// {
//   "key": "device",
//   "clientId": "$deviceClientId",
//   "clientSecret": "$deviceClientSecret",  ← resolved from variables
//   "audience": "$apiAudience",
//   "token": { "endpoint": "/oauth/token" }
// }
```

---

### auth.exchangeToken(targetAuthId)

Exchanges **this** context's access token for the **target** context's token. Called on the source, target is the parameter. Resulting tokens are stored in the **target** context.

```typescript
// "I'm 1fa, exchange my token for 2fa"
await morph.auth('burgan-auth/1fa').exchangeToken('burgan-auth/2fa');
// SDK takes 1fa's access token, calls POST to 2fa's token.exchangeEndpoint with:
//   grant_type=token_exchange, subject_token=<1fa access token>
// Stores result in burgan-auth/2fa
```

When `token.exchangeSource` is configured on the target context, the SDK can perform this exchange **automatically** during token resolution — no host app call needed:

```typescript
// Config on target context (e.g. 1fa session):
// { "token": { "exchangeEndpoint": "/auth/exchange", "exchangeSource": "burgan-auth/2fa" } }
// or multiple subject sources: "exchangeSource": ["burgan-auth/2fa", "burgan-auth/other"]
//
// Auto-exchange in token resolution:
// request needs 1fa → refresh fails or no token → 2fa token exists →
// SDK auto-calls token exchange internally → 1fa token acquired → request proceeds
```

`exchangeSource` may be a **string** or **string[]**. When it is an array, the SDK tries each subject context **in order** until one exchange succeeds.

```json
{ "token": { "exchangeEndpoint": "/token", "exchangeSource": ["morph-auth/2fa", "morph-auth/other"] } }
```

---

### morph.getExchangeSources(targetAuthId)

Returns the configured `token.exchangeSource` for **this** context as an ordered list of subject auth ids (string or array in config is normalized). Use on the **target** row: show a dropdown of sources, then call `exchangeToken` on the chosen source.

```typescript
morph.getExchangeSources('morph-auth/1fa'); // e.g. ['morph-auth/2fa', 'morph-auth/other']
const src = pickFromUi; // user-selected auth id from that list
await morph.auth(src).exchangeToken('morph-auth/1fa');
```

---

### morph.getExchangeTargets(sourceAuthId)

Returns sorted context auth ids whose `token.exchangeSource` includes `sourceAuthId` (reverse index). The argument must be a full context id (`provider/contextKey`). Prefer `getExchangeSources` on the destination when building target-row exchange UIs.

```typescript
morph.getExchangeTargets('morph-auth/2fa'); // e.g. ['morph-auth/1fa']
```

---

### auth.setTokens(tokens)

Low-level escape hatch: directly stores pre-acquired tokens. Use when tokens come from an external source the SDK can't call.

```typescript
await morph.auth('burgan-auth/1fa').setTokens({
  accessToken: externalTokenResponse.access_token,
  refreshToken: externalTokenResponse.refresh_token,
});
```

For normal flows, prefer `submitCode()`, `acquireWithClientCredentials()`, or `exchangeToken()` — they handle the token endpoint call, `onTokenExchange` delegate check, and storage atomically.

---

### auth.clearTokens()

Removes tokens silently. No server call, no `onLogout` callback.

```typescript
await morph.auth('burgan-auth/2fa').clearTokens();
```

---

### auth.logout()

Full logout: hits the logout endpoint, clears tokens, cancels timers, fires `onLogout`.

```typescript
async function handleLogout() {
  await morph.auth('burgan-auth/2fa').clearTokens();
  await morph.auth('burgan-auth/1fa').logout();
  // onLogout('burgan-auth/1fa', 'user_initiated') fires
  router.navigate('/login');
}
```

---

### auth.hasValidToken()

Async check: "can this context authenticate right now?" Attempts refresh if needed — returns the **real** answer, not an optimistic guess.

- Valid access token in cache → `true` (no network call)
- Access expired + refresh token exists → **attempts refresh** → returns result
- No tokens at all → `false` (no network call)

Does **not** trigger `onAuthRequired` — only uses what it already has. If refresh fails (token revoked, server-side logout, fraud), returns `false`.

```typescript
async function getInitialRoute(): Promise<string> {
  if (await morph.auth('burgan-auth/2fa').hasValidToken()) return '/dashboard';
  if (await morph.auth('burgan-auth/1fa').hasValidToken()) return '/dashboard-limited';
  if (await morph.auth('burgan-auth/device').hasValidToken()) return '/login';
  return '/onboarding';
}

// Refresh token revoked server-side (fraud detection) → false, not a lie
const isLoggedIn = await morph.auth('burgan-auth/1fa').hasValidToken();
```

For synchronous UI state (render loops, build methods), pass `onTokenChange` to `oauth2Plugin`:

```typescript
let isLoggedIn = false;
let canTransfer = false;

oauth2Plugin({
  storage: browserStoragePlugin('myapp:tk:'),
  callbacks: {
    onTokenChange: (authId, tokens) => {
      if (authId === 'burgan-auth/1fa') isLoggedIn = !!tokens;
      if (authId === 'burgan-auth/2fa') canTransfer = !!tokens;
    },
  },
})
// Then in UI: use isLoggedIn / canTransfer (sync, always fresh)
```

---

### auth.refreshTokens()

Explicit token-endpoint call for **this context** (must use a `provider/context` auth id, not provider-only):

- If a **refresh token** is stored → `grant_type=refresh_token` (rotating/static rules from config still apply).
- Else if the context is **client_credentials** (e.g. device) → new access token via `client_credentials`.
- Else → throws (no refresh path).

On failure, behavior matches automatic refresh: vault may be cleared and `onLogout` / delegate callbacks can run. If the context has `token.exchangeSource` (e.g. 1FA) and refresh fails, the SDK tries **each** listed source in order via token exchange before giving up.

```typescript
await morph.auth('burgan-auth/2fa').refreshTokens();
await morph.auth('burgan-auth/device').refreshTokens(); // re-acquire device token
```

Unlike `hasValidToken()`, this **always** hits the IdP when preconditions are met (no “already valid” short-circuit).

---

### auth.getClaims()

Returns decoded JWT claims from the stored access token, or `null` if no token is stored, the token format is `"opaque"`, or the token is not a valid JWT. No network, no refresh — reads from vault only. For providers like Google whose access tokens are opaque, set `tokenTypes.access.format: "opaque"` in config — `getClaims()` will return `null` without attempting decode.

```typescript
const claims = await morph.auth('morph-auth/1fa').getClaims();
if (claims) {
  console.log(claims.sub);  // 'user-123'
  console.log(claims.exp);  // 1711234567 (unix seconds)
  console.log(claims.azp);  // 'my-client-id'
}
```

Use `getClaims()` when you need to display user info, check token claims for routing decisions, or inspect provider-specific fields. The raw token never leaves the SDK.

For all contexts at once (debug panels), use `morph.getTokenStatus()` which includes `claims` and `refreshClaims` per row.

---

### auth.peekTokens()

Low-level escape hatch: returns the stored `TokenSet` (raw tokens) for this context without network. Prefer `getClaims()` for claim inspection — it avoids exposing raw tokens to application code.

```typescript
const t = await morph.auth('morph-auth/1fa').peekTokens();
console.log(t?.expiresAt);
```

---

### auth.authId

The full `provider/context` identifier this handle is bound to.

```typescript
const handle = morph.auth('burgan-auth/1fa');
console.log(handle.authId); // 'burgan-auth/1fa'
```

---

## Types

### MorphConfig

```typescript
interface MorphConfig {
  providers: ProviderConfig[];
  hosts: HostConfig[];
  /** Root-path `/?code=` handler: see {@link MorphClient.completeOAuthReturn}. */
  rootCallbackAuthId?: string;
}
```

---

### ProviderConfig

```typescript
interface ProviderConfig {
  key: string;
  type: 'oauth2';
  baseUrl: string;
  /** If set, {@link MorphClient.getAuthorizationUrl} uses this origin instead of `baseUrl` (supports `$variable`). Use when `baseUrl` is a same-origin dev proxy so the IdP login page and `/resources/...` load from the real Keycloak host. */
  authorizationBrowserBaseUrl?: string;
  /** If set (supports `$variable`), token, refresh, token-exchange, and logout HTTP use this base instead of `baseUrl` (e.g. same-origin Vite proxy while `baseUrl` stays the real issuer). */
  tokenHttpBaseUrl?: string;
  networkPolicy?: NetworkPolicy;
  headers?: Record<string, string>;
  contexts: AuthContextConfig[];
}
```

---

### HostConfig

```typescript
interface HostConfig {
  key: string;
  baseUrl: string;
  allowedAuth: string[]; // e.g. ['morph-auth/1fa', 'morph-auth/2fa']
  defaultAuth?: string;
  /** Sent on every host request; values support `$variable` interpolation (see MorphOptions.variables). */
  headers?: Record<string, string>;
}
```

Per-request `HostRequestOptions.headers` are merged after host defaults; the same header name on the request wins. The access-token header (`Authorization` or context-specific) is applied last.

```typescript
const mainApi: HostConfig = {
  key: 'main-api',
  baseUrl: 'https://api.example.com',
  allowedAuth: ['morph-auth/device', 'morph-auth/1fa', 'morph-auth/2fa'],
  defaultAuth: 'morph-auth/2fa',
  headers: {
    'X-Device-Id': '$deviceId',
    'X-Installation-Id': '$installationId',
  },
};
```

**Note:** `ProviderConfig.headers` apply only to OAuth token HTTP calls for that provider, not to `morph.host(...).get()` traffic. Put device/installation identifiers on the **host** if the API should receive them on resource requests.

---

### MorphOptions

```typescript
interface MorphOptions {
  // Plugins — declare capabilities at init time
  plugins: MorphPlugin[];
  variables?: Record<string, string>;

  // Core-level delegates (shared, not plugin-specific)
  networkDelegate?: NetworkDelegate;
  onSignPayload?: (payload: string, authId: string) => Promise<string>;
  onDecryptResponse?: (encryptedBody: string, authId: string) => Promise<string>;
  onLog?: (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;
  onHttpTrace?: (event: MorphHttpTraceEvent) => void;
}
```

**Plugins:**
- `plugins` — Array of `MorphPlugin` instances. Plugins declare `provides` and `requires` for automatic dependency resolution (topological sort). The combined set must include exactly one plugin that calls `ctx.provideAuth()` and one that calls `ctx.provideStorage()`. Order does not matter. See [Writing Plugins](writing-plugins.md).
- `variables` — Shared variable map for `$variable` interpolation in config (host headers, etc.). Plugin-specific variables (client secrets) should be passed to the plugin directly.

**Core delegates (shared):**
- `networkDelegate` -- SSL pins, mTLS cert, proxy per hostname. Lazy, per first request.
- `onSignPayload` -- JWS signing. Called when `sign: true`. Returns signature string.
- `onDecryptResponse` -- Response decryption. Called when `encrypted: true`. Returns decrypted plaintext.
- `onLog` -- Low-level log hook. Prefer `loggerPlugin()` and pass the `logger` instance to each plugin.
- `onHttpTrace` -- Structured host HTTP trace. Fired once per `fetch()`.

**Logging:** Use `@morph/logger` -- create one `loggerPlugin()` instance and pass it as the `logger` option to `oauth2Plugin`, `browserStoragePlugin`, etc. All plugins route their log output through the shared logger.

**Plugin-level options (passed to each plugin factory):**
- `logger` -- `MorphPlugin | LogFn` -- the shared logger for this plugin
- `storage` -- `StorageProvider | MorphPlugin` -- inline storage (oauth2Plugin only)
- `callbacks` -- `Partial<MorphCallbacks>` -- auth lifecycle (oauth2Plugin only)
- `variables` -- plugin-specific variables (client secrets, redirect URIs)
- `onTokenExchange`, `onClientJwtAssertion`, `autoAcquireNonInteractive` -- oauth2Plugin only

---

### MorphHttpTraceEvent

```typescript
interface MorphHttpTraceEvent {
  kind: 'host_http';
  hostKey: string;
  method: string;
  url: string;
  path: string;
  authId: string;
  requestHeaders: Record<string, string>;
  statusCode: number;
  responseHeaders: Record<string, string>;
  responseBody: unknown;
  durationMs: number;
  networkError?: string;
}
```

---

### MorphCallbacks

Passed to `oauth2Plugin({ callbacks })`. All callbacks are `void` and receive `authId` in `provider/context` format. All fields are **optional** -- the plugin provides defaults.

```typescript
interface MorphCallbacks {
  onAuthRequired: (authId: string, metadata: DelegateMetadata) => void;
  onLogout: (authId: string, reason: LogoutReason) => void;
  onTokenChange?: (authId: string, tokens: TokenSet | null) => void;
}
```

**Defaults (when not overridden):**
- `onAuthRequired` -- logs via the resolved `logger` at `warn` level (or no-op if no logger)
- `onLogout` -- logs via the resolved `logger` at `info` level (or no-op if no logger)
- `onTokenChange` -- not set (no-op)

**Override only what you need:**

```typescript
oauth2Plugin({
  storage: browserStoragePlugin('myapp:tk:'),
  callbacks: {
    onLogout: (authId, reason) => {
      if (reason === 'session_expired') showToast('Session expired.');
      if (authId === 'burgan-auth/1fa') router.navigate('/login');
    },
    onTokenChange: (authId, tokens) => {
      if (authId === 'burgan-auth/1fa') setIsLoggedIn(!!tokens);
    },
  },
})
```

---

### TokenExchangeGrant

Passed to the `onTokenExchange` functional delegate. Contains everything the delegate needs to perform a custom exchange.

```typescript
interface TokenExchangeGrant {
  type: 'authorization_code' | 'client_credentials' | 'token_exchange' | 'refresh_token';
  authId: string;           // target context: 'burgan-auth/1fa'
  code?: string;            // for authorization_code
  codeVerifier?: string;    // for PKCE
  sourceAuthId?: string;    // for token_exchange: 'burgan-auth/1fa'
  sourceToken?: string;     // for token_exchange: the actual token
  refreshToken?: string;    // for refresh_token
}
```

```typescript
// Passed to oauth2Plugin (not MorphOptions)
oauth2Plugin({
  storage: browserStoragePlugin('myapp:tk:'),
  onTokenExchange: async (grant) => {
    if (grant.type === 'token_exchange' && grant.authId === 'burgan-auth/2fa') {
      const res = await fetch('/api/custom-step-up', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${grant.sourceToken}` },
      });
      const tokens = await res.json();
      return { accessToken: tokens.access_token, refreshToken: tokens.refresh_token };
    }
    return null; // standard OAuth2 exchange
  },
})
```

---

### DelegateMetadata

Forwarded from config's `delegateMetadata`. The SDK does not interpret these fields.

```typescript
interface DelegateMetadata {
  workflow: string;
  grantHint: string;
  interaction: InteractionMode;
}
```

```typescript
onAuthRequired: (authId, metadata) => {
  // metadata = { workflow: 'step-up-auth', grantHint: 'token_exchange', interaction: 'interactive' }

  if (metadata.workflow === 'device-auth') {
    morph.auth(authId).acquireWithClientCredentials();
  } else if (metadata.workflow === 'login') {
    router.navigate('/login', { authId });
    // later: morph.auth(authId).submitCode(code)
  } else if (metadata.workflow === 'step-up-auth') {
    // Only fires if auto-exchange failed or exchangeSource not configured.
    // Otherwise SDK auto-exchanges (e.g. 2fa→1fa for session) without this callback.
    morph.auth('burgan-auth/2fa').exchangeToken('burgan-auth/1fa');
  } else if (metadata.workflow === 'edevlet-login') {
    window.location.href = `/auth/redirect?authId=${authId}`;
    // later: morph.auth(authId).submitCode(code, { codeVerifier })
  }
}
```

---

### TokenSet

```typescript
interface TokenSet {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;       // unix timestamp (seconds)
  metadata?: Record<string, unknown>;
}
```

```typescript
// Normally handled by submitCode() / acquireWithClientCredentials().
// Escape hatch:
await morph.auth('burgan-auth/1fa').setTokens({
  accessToken: 'eyJhbGciOiJSUzI1NiIs...',
  refreshToken: 'v1.MjAyNS0wMS0wMQ...',
});
```

---

### HostRequestOptions

```typescript
interface HostRequestOptions {
  auth?: string | string[];            // provider/context format, array = priority fallback
  headers?: Record<string, string>;
  queryParams?: Record<string, string>;
  timeout?: string;
  sign?: boolean;                      // sign payload with JWS via onSignPayload delegate
  encrypted?: boolean;                 // response is encrypted, decrypt via onDecryptResponse delegate
}
```

**Auth resolution:**

- **Omitted** — Uses the host's `defaultAuth`.
- **Single string** (`auth: 'burgan-auth/2fa'`) — Strict. Recovery on failure.
- **Priority list** (`auth: ['burgan-auth/2fa', 'burgan-auth/1fa']`) — First available wins.

```typescript
const api = morph.host('main-api');

await api.get('/accounts');                                                   // defaultAuth
await api.post('/transfers', body, { auth: 'burgan-auth/2fa' });              // strict 2fa
await api.get('/notifications', { auth: ['burgan-auth/2fa', 'burgan-auth/1fa'] }); // fallback
await api.get('/transactions', { queryParams: { page: '1', limit: '20' } });
await api.post('/reports/generate', params, { auth: 'burgan-auth/1fa', timeout: '60s' });
await api.post('/transfers', body, { auth: 'burgan-auth/2fa', sign: true });         // JWS signed request
const secret = await api.get('/cards/pin', { auth: 'burgan-auth/2fa', encrypted: true }); // encrypted response
```

---

### HostFullRequestOptions

```typescript
interface HostFullRequestOptions {
  method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';
  path: string;
  auth?: string | string[];  // provider/context format
  body?: any;
  headers?: Record<string, string>;
  queryParams?: Record<string, string>;
  timeout?: string;
  sign?: boolean;
  encrypted?: boolean;
}
```

---

### MorphResponse

```typescript
interface MorphResponse<T = any> {
  statusCode: number;
  headers: Record<string, string>;
  body: T;
  resolvedAuth: string;   // provider/context that was actually used
  raw: Response;
}
```

```typescript
const res = await api.get('/accounts', { auth: ['burgan-auth/2fa', 'burgan-auth/1fa'] });

if (res.resolvedAuth === 'burgan-auth/1fa') {
  showBanner('Limited view. Verify identity for full access.');
}
```

---

### Enums

**LogoutReason**

```typescript
type LogoutReason = 'user_initiated' | 'unauthorized' | 'refresh_failed' | 'session_expired';
```

```typescript
onLogout: (authId, reason) => {
  switch (reason) {
    case 'user_initiated':   showToast('You have been signed out.');        break;
    case 'unauthorized':     showToast('Your session is no longer valid.'); break;
    case 'refresh_failed':   showToast('Please sign in again.');            break;
    case 'session_expired':  showToast('Session expired due to inactivity.'); break;
  }
}
```

**InteractionMode**

```typescript
type InteractionMode = 'interactive' | 'non-interactive' | 'redirect';
```

---

### NetworkDelegate

```typescript
interface NetworkDelegate {
  getNetworkConfig(hostname: string): Promise<NetworkConfig | null>;
}

interface NetworkConfig {
  certificatePins?: string[];
  proxy?: ProxyConfig;
  clientCertificate?: ClientCertificate;
}

interface ProxyConfig {
  url: string;
}

interface ClientCertificate {
  cert: string;          // PEM format
  key: string;           // private key, PEM format
  passphrase?: string;
}
```

```typescript
const networkDelegate: NetworkDelegate = {
  async getNetworkConfig(hostname) {
    const PINS: Record<string, string[]> = {
      'api.burgan.com.tr':     ['sha256/AAAA...', 'sha256/BBBB...'],
      'payment.burgan.com.tr': ['sha256/CCCC...', 'sha256/DDDD...'],
    };

    // mTLS: provide client certificate for hosts that require it
    const MTLS_HOSTS = ['api.burgan.com.tr', 'payment.burgan.com.tr'];
    const clientCert = MTLS_HOSTS.includes(hostname)
      ? await loadClientCertFromKeychain()  // platform keychain/keystore
      : undefined;

    return {
      certificatePins: PINS[hostname],
      proxy: __DEV__ ? { url: 'http://localhost:8888' } : undefined,
      clientCertificate: clientCert,
    };
  },
};
```

---

## OAuth helpers

### buildOAuth2AuthorizationUrl

Builds the query string for an OAuth 2.0 **authorize** redirect (`client_id`, `redirect_uri`, `response_type`, `scope`, `state`, plus any `extraParams`). Combine with `authorization.endpoint` from config: if `endpoint` is an **absolute** URL, it is used as-is (so authorize still hits the real IdP when `provider.baseUrl` is rewritten for dev token proxying). Optional fields on `AuthContextConfig.authorization`: `responseType`, `extraParams`.

```typescript
import { buildOAuth2AuthorizationUrl } from '@morph/core';
```

---

## Error Types

### ConfigValidationError

```typescript
try {
  const morph = MorphClient.init(badConfig, options);
} catch (e) {
  if (e instanceof ConfigValidationError) {
    console.error('Invalid config:', e.errors);
  }
}
```

### UnknownHostError

```typescript
try {
  morph.host('nonexistent-api');
} catch (e) {
  if (e instanceof UnknownHostError) {
    console.error(`No host: ${e.key}`);
  }
}
```

### UnknownContextError

```typescript
try {
  morph.auth('nonexistent/ctx');
} catch (e) {
  if (e instanceof UnknownContextError) {
    console.error(`No auth context: ${e.authId}`);
  }
}
```

### InvalidAuthForHostError

```typescript
try {
  // edevlet-auth not listed on payment-api's providers
  await payments.get('/pay', { auth: 'edevlet-auth/edevlet' });
} catch (e) {
  if (e instanceof InvalidAuthForHostError) {
    console.error(`${e.authId} not valid for ${e.hostKey}`);
    console.error(`Allowed providers: ${e.allowedProviders.join(', ')}`);
  }
}
```

### AuthError

```typescript
const res = await api.get('/accounts');
if (res instanceof AuthError) {
  // res.authId = 'burgan-auth/2fa'
  // res.reason = 'no_token' | 'refresh_failed' | 'delegation_required'
  showLoginPrompt();
}
```

### TokenEndpointError

Thrown when a token endpoint (refresh, client_credentials, authorization_code exchange, token exchange) returns a non-2xx HTTP response.

```typescript
import { TokenEndpointError } from '@morph/core';

try {
  await morph.auth('morph-auth/1fa').submitCode(code);
} catch (e) {
  if (e instanceof TokenEndpointError) {
    console.error(`Token endpoint ${e.statusCode}: ${e.responseText}`);
  }
}
```

---

## Utilities


### Browser Storage Factories

Ready-made `StorageProvider` implementations for web apps, available as a plugin or standalone factory.

```typescript
import { MorphClient } from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';
import { browserStoragePlugin } from '@morph/browser-storage';

// As a plugin (recommended) — order does not matter
MorphClient.init(config, {
  plugins: [
    browserStoragePlugin('myapp:tk:'),           // sessionStorage (default)
    oauth2Plugin(),
  ],
  // ...
});

// localStorage variant
MorphClient.init(config, {
  plugins: [
    browserStoragePlugin('myapp:tk:', 'local'),
    oauth2Plugin(),
  ],
  // ...
});
```

Standalone factories are also available for custom plugins or direct dependency injection:

```typescript
import { createBrowserSessionStorage, createBrowserLocalStorage } from '@morph/browser-storage';

const sessionStore = createBrowserSessionStorage('myapp:tk:');
const localStore = createBrowserLocalStorage('myapp:tk:');

// Pass directly to oauth2Plugin via explicit DI
plugins: [oauth2Plugin({ storage: sessionStore })]
```

### OAuth State Helpers

Encode/decode `authId` in the OAuth `state` parameter. Used internally by `getAuthorizationUrl` and `completeOAuthCallback`. Exposed for custom flows.

```typescript
import { encodeOAuthState, decodeOAuthState } from '@morph/core';

const state = encodeOAuthState('morph-auth/2fa'); // 'morph1.eyJhIjo...'
const decoded = decodeOAuthState(state);          // { authId: 'morph-auth/2fa' }
decodeOAuthState('random-opaque-state');           // null
```

### cleanOAuthReturnFromBrowser

Strips OAuth return query params (`code`, `state`, `session_state`, `iss`, `scope`, `error`, `error_description`) from the current browser URL via `history.replaceState`. No-op outside browser.

```typescript
import { cleanOAuthReturnFromBrowser } from '@morph/core';
cleanOAuthReturnFromBrowser();
```

### normalizeLoopbackOrigin

Normalizes IPv6 loopback origins to `http://localhost:PORT` for consistent `redirect_uri` matching.

```typescript
import { normalizeLoopbackOrigin } from '@morph/core';
normalizeLoopbackOrigin('http://[::1]:5173'); // 'http://localhost:5173'
normalizeLoopbackOrigin('http://localhost:5173'); // unchanged
```
