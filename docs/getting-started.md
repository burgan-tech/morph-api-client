# Getting Started

> **Dart/Flutter parity is planned.** This guide covers the TypeScript SDK. The Dart implementation will share the same JSON config schema and mirror the public API with language-appropriate idioms.

## Installation

```bash
npm install @morph/core @morph/oauth2 @morph/browser-storage
```

---

## Configuration

Create a JSON configuration file with two sections: `providers` (auth servers) and `hosts` (API servers). This can be embedded in your app bundle, loaded from a remote config service, or defined inline.

```json
{
  "providers": [
    {
      "key": "my-auth",
      "type": "oauth2",
      "baseUrl": "https://auth.example.com/realms/main",
      "contexts": [
        {
          "key": "device",
          "clientId": "$deviceClientId",
          "clientSecret": "$deviceClientSecret",
          "token": { "endpoint": "/protocol/openid-connect/token" },
          "recoveryPolicy": { "onUnauthorized": "delegate", "onRefreshFail": "clear" },
          "delegateMetadata": { "workflow": "device-auth", "grantHint": "client_credentials", "interaction": "non-interactive" },
          "tokenTypes": {
            "access": {
              "expiryPolicy": "token",
              "storage": { "scope": "device", "type": "persistent", "protection": "secure", "key": "device-access-token" }
            }
          }
        },
        {
          "key": "user",
          "clientId": "$userClientId",
          "clientSecret": "$userClientSecret",
          "identity": { "subject": "sub" },
          "authorization": {
            "endpoint": "/protocol/openid-connect/auth",
            "redirectUri": "$oauthRedirectUri"
          },
          "token": { "endpoint": "/protocol/openid-connect/token" },
          "logout": { "endpoint": "/protocol/openid-connect/logout" },
          "refreshPolicy": { "strategy": "rotating", "refreshBeforeExpiry": "15s" },
          "recoveryPolicy": { "onUnauthorized": "refresh", "onRefreshFail": "delegate" },
          "delegateMetadata": { "workflow": "login", "grantHint": "authorization_code", "interaction": "interactive" },
          "tokenTypes": {
            "access": {
              "expiryPolicy": "token",
              "storage": { "scope": "user", "type": "persistent", "protection": "encrypted", "key": "user.access.$subject" }
            },
            "refresh": {
              "expiryPolicy": "token",
              "storage": { "scope": "user", "type": "persistent", "protection": "encrypted", "key": "user.refresh.$subject" }
            }
          }
        }
      ]
    }
  ],
  "hosts": [
    {
      "key": "api",
      "baseUrl": "https://api.example.com",
      "allowedAuth": ["my-auth/device", "my-auth/user"],
      "defaultAuth": "my-auth/user",
      "headers": {
        "X-Device-Id": "$deviceId"
      }
    }
  ]
}
```

See [Configuration Reference](configuration.md) for a full field reference.

---

## Initialization

```typescript
import { MorphClient } from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';
import { createBrowserSessionStorage } from '@morph/browser-storage';
import config from './morph-config.json';

const morph = MorphClient.init(config, {
  auth: oauth2Plugin,
  storage: createBrowserSessionStorage('myapp:tk:'),

  callbacks: {
    onAuthRequired: (authId, metadata) => {
      if (metadata.interaction === 'non-interactive') {
        morph.auth(authId).acquireWithClientCredentials();
      } else if (metadata.interaction === 'interactive') {
        router.navigate('/login', { authId });
      }
    },
    onLogout: (authId, reason) => {
      console.log(`Logged out of ${authId}: ${reason}`);
      if (authId === 'my-auth/user') {
        router.navigate('/login');
      }
    },
  },

  variables: {
    deviceClientId: 'device-client-abc',
    deviceClientSecret: 'device-secret-xyz',
    userClientId: 'user-client-def',
    userClientSecret: 'user-secret-uvw',
    oauthRedirectUri: `${window.location.origin}/oauth/callback`,
    deviceId: getDeviceId(),
  },
});
```

---

## Making API Calls

All HTTP calls go through a **host**. The host determines the base URL and provides a default auth context.

```typescript
const api = morph.host('api');

// GET request — uses host's defaultAuth ("my-auth/user")
const accounts = await api.get('/accounts');
console.log(accounts.statusCode); // 200
console.log(accounts.body);       // parsed response body

// POST request
const transfer = await api.post('/transfers', {
  fromAccount: 'ACC-001',
  toAccount: 'ACC-002',
  amount: 100.00,
  currency: 'TRY',
});

// Override auth context for a specific request
const publicConfig = await api.get('/public/config', { auth: 'my-auth/device' });
```

---

## Providing Tokens After Auth Flow

When the SDK calls `onAuthRequired`, the host application starts the appropriate auth flow. After the redirect returns an authorization code, submit it to the SDK:

```typescript
// User completed login, browser redirect returned a code
await morph.auth('my-auth/user').submitCode(authorizationCode);
// SDK calls the token endpoint with grant_type=authorization_code,
// stores access_token + refresh_token in my-auth/user
```

For PKCE flows (e.g., external providers):

```typescript
await morph.auth('google-auth/google').submitCode(code, { codeVerifier: pkceVerifier });
```

For non-interactive flows (device tokens), the SDK can acquire tokens autonomously:

```typescript
await morph.auth('my-auth/device').acquireWithClientCredentials();
```

For step-up auth, the SDK exchanges one token for another. Called on the **source**, target is the parameter:

```typescript
// "I'm 1fa, exchange my token for 2fa"
await morph.auth('my-auth/1fa').exchangeToken('my-auth/2fa');
```

---

## Checking Auth State

`hasValidToken()` is **async** — it may attempt a refresh if the stored token is expired:

```typescript
if (await morph.auth('my-auth/user').hasValidToken()) {
  // user is authenticated, proceed to main screen
} else {
  // redirect to login
}
```

For synchronous UI state, use the `onTokenChange` callback:

```typescript
let isLoggedIn = false;

const morph = MorphClient.init(config, {
  // ...
  callbacks: {
    // ...
    onTokenChange: (authId, tokens) => {
      if (authId === 'my-auth/user') isLoggedIn = !!tokens;
    },
  },
});
```

---

## Logout

```typescript
// User-initiated logout
await morph.auth('my-auth/user').logout();
// This will:
// 1. POST to the provider's logout endpoint
// 2. Clear all tokens for the context
// 3. Invoke onLogout('my-auth/user', 'user_initiated')

// Provider-level: logout all contexts at once
await morph.auth('my-auth').logout();
```

---

## Cleanup

When the SDK is no longer needed (e.g., app termination, component disposal):

```typescript
morph.dispose();
```

This cancels all pending operations and prevents resource leaks.

---

## Next Steps

- [Architecture](architecture.md) — System design, module structure, and how the layers interact.
- [Configuration Reference](configuration.md) — Detailed reference for every config field.
- [Token Lifecycle](token-lifecycle.md) — Deep dive into token resolution, refresh, and recovery.
- [API Reference](api-reference.md) — Complete public API documentation.
- [Platform Adapters](platform-adapters.md) — How to implement `StorageProvider` for your platform.
