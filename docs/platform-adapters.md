# Platform Adapters

The SDK defines two interfaces that the host application provides via plugins: **StorageProvider** (required, registered by a storage plugin like `browserStoragePlugin()`) and **NetworkDelegate** (optional, passed directly in `MorphOptions`). Logging is handled via the `onLog` callback on `MorphOptions`. See [Writing Plugins](writing-plugins.md) for how to create custom storage plugins.

> **Dart/Flutter parity is planned.** This document currently covers TypeScript. The Dart SDK will expose the same interfaces with language-appropriate idioms.

---

## StorageProvider

The storage provider is responsible for persisting and retrieving token data. A `StorageProvider` is registered by a storage plugin (via `ctx.provideStorage()`) during `MorphClient.init()`. The SDK passes the full `StorageConfig` from the config JSON to every call, so the delegate has all the context it needs to make storage decisions.

### Interface

```typescript
interface StorageProvider {
  read(key: string, config: StorageConfig): Promise<string | null>;
  write(key: string, value: string, config: StorageConfig): Promise<void>;
  delete(key: string, config: StorageConfig): Promise<void>;
  deleteByPrefix(prefix: string, config: StorageConfig): Promise<void>;
}

interface StorageConfig {
  scope: 'device' | 'user' | 'session';
  type: 'memory' | 'persistent';
  protection: 'none' | 'secure' | 'encrypted';
  key: string;
}
```

### StorageConfig Fields

The `config` parameter is passed straight from the JSON config's `tokenTypes.access.storage` (or `tokenTypes.refresh.storage`):

- **scope** — `"device"` (shared across users, survives logout), `"user"` (tied to a user, cleared on user logout), `"session"` (current session only, cleared on any logout).
- **type** — `"memory"` (in-memory only, lost on app restart) or `"persistent"` (survives app restarts).
- **protection** — `"none"` (plain text), `"secure"` (platform secure storage: Keychain/Keystore), `"encrypted"` (app-level encryption on top of secure storage).

The delegate decides **how** to implement each combination. For example:

| type | protection | Browser | Flutter (planned) |
|---|---|---|---|
| memory | any | `Map` in memory | `Map` in memory |
| persistent | none | `localStorage` | `SharedPreferences` |
| persistent | secure | `localStorage` (best effort) | `FlutterSecureStorage` |
| persistent | encrypted | `localStorage` + Web Crypto | `FlutterSecureStorage` + AES |

### Method Descriptions

- **read(key, config)** — Returns the stored value for the given key, or `null` if not found.
- **write(key, value, config)** — Stores the value under the given key. Idempotent — writing the same key twice overwrites.
- **delete(key, config)** — Removes the value for the given key. No-op if not found.
- **deleteByPrefix(prefix, config)** — Removes all entries whose key starts with the prefix. Used during logout to clear all tokens for a context.

### Token Serialization

The `value` parameter is always a JSON string. The SDK serializes the token data as:

```json
{
  "token": "eyJhbGciOiJSUzI1NiIs...",
  "expiresAt": 1711234567
}
```

The storage provider stores and returns this string as-is. Deserialization is handled by the SDK.

---

## SDK-Provided Browser Storage Plugin

For web applications, the `@morph/browser-storage` package provides a ready-made plugin:

```typescript
import { MorphClient } from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';
import { browserStoragePlugin } from '@morph/browser-storage';

MorphClient.init(config, {
  plugins: [
    browserStoragePlugin('myapp:tk:'),           // sessionStorage (default)
    // browserStoragePlugin('myapp:tk:', 'local'), // or localStorage
    oauth2Plugin(),
  ],
});
```

The plugin creates a `StorageProvider` that prefixes all keys with the given string and delegates to the browser's `sessionStorage` or `localStorage`. It ignores `StorageConfig.protection` (browser storage has no encryption layer -- use a custom plugin for encrypted storage).

For production apps with sensitive tokens, write a custom storage plugin using the `MorphPlugin` interface. See [Writing Plugins](writing-plugins.md).

---

## Custom Browser Implementation Example

```typescript
const memoryStore = new Map<string, string>();

const storage: StorageProvider = {
  async read(key, config) {
    if (config.type === 'memory') return memoryStore.get(key) ?? null;
    const raw = localStorage.getItem(key);
    if (raw === null) return null;
    if (config.protection === 'encrypted') return decrypt(raw, encryptionKey);
    return raw;
  },

  async write(key, value, config) {
    if (config.type === 'memory') { memoryStore.set(key, value); return; }
    if (config.protection === 'encrypted') {
      localStorage.setItem(key, await encrypt(value, encryptionKey));
    } else {
      localStorage.setItem(key, value);
    }
  },

  async delete(key, config) {
    if (config.type === 'memory') { memoryStore.delete(key); return; }
    localStorage.removeItem(key);
  },

  async deleteByPrefix(prefix, config) {
    if (config.type === 'memory') {
      for (const k of memoryStore.keys()) if (k.startsWith(prefix)) memoryStore.delete(k);
      return;
    }
    for (let i = localStorage.length - 1; i >= 0; i--) {
      const k = localStorage.key(i);
      if (k?.startsWith(prefix)) localStorage.removeItem(k);
    }
  },
};
```

---

## In-Memory Storage (Dev/Test)

For development and testing, write a simple in-memory storage plugin:

```typescript
import { MorphClient, type MorphPlugin } from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';

function memoryStoragePlugin(): MorphPlugin {
  const store = new Map<string, string>();
  return {
    name: 'memory-storage',
    provides: ['storage'],
    install(ctx) {
      ctx.provideStorage({
        read: async (key) => store.get(key) ?? null,
        write: async (key, value) => { store.set(key, value); },
        delete: async (key) => { store.delete(key); },
        deleteByPrefix: async (prefix) => {
          for (const k of store.keys()) if (k.startsWith(prefix)) store.delete(k);
        },
      });
    },
  };
}

const morph = MorphClient.init(config, {
  plugins: [
    oauth2Plugin({ storage: memoryStoragePlugin() }),
  ],
});
```

In-memory storage is not suitable for production -- all tokens are lost when the process terminates.

---

## NetworkDelegate

Optional interface for providing transport security configuration. The SDK owns the HTTP transport layer — it builds requests, attaches tokens, handles retries. The only transport-level information it needs from the host app is **SSL certificate pins** and **proxy settings**.

### How It Works

The SDK calls `getNetworkConfig(hostname)` **lazily on the first request** to each unique hostname. This avoids adding latency to `MorphClient.init()`. The result is cached for the lifetime of the client.

```
morph.host('main-api').get('/accounts')
  │
  ├─ hostname = "api.example.com"
  ├─ cache miss → call networkDelegate.getNetworkConfig("api.example.com")
  ├─ host app returns { certificatePins: [...], proxy: null }
  ├─ SDK configures HTTP client for this hostname, caches result
  └─ request proceeds

morph.host('main-api').get('/transfers')
  │
  ├─ hostname = "api.example.com"
  ├─ cache hit → skip delegate call
  └─ request proceeds with cached config
```

If `networkDelegate` is not provided or returns `null`, standard TLS validation applies (no pinning, no proxy).

### Interface

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
  cert: string;
  key: string;
  passphrase?: string;
}
```

### Browser

In browser environments, SSL pinning is not possible — the browser handles TLS entirely. A browser `NetworkDelegate` would typically return `null`:

```typescript
const morph = MorphClient.init(config, {
  // No networkDelegate needed for browser apps
  // ...
});
```

### Platform Behavior Summary

| Platform | SSL Pinning | Proxy | mTLS |
|---|---|---|---|
| Browser | Not possible (browser TLS) | Not applicable | Not applicable |
| Node.js | Custom TLS `checkServerIdentity` | `Agent` with proxy | Client cert via `Agent` |
| Flutter (planned) | `CertificatePinner` / `BadCertificateCallback` | `HttpClient.findProxy` | Client cert via `SecurityContext` |

---

## Logging

The SDK uses a single `onLog` callback on `MorphOptions` for all diagnostic output:

```typescript
const morph = MorphClient.init(config, {
  onLog: (level, message, error, context) => {
    console.log(`[morph:${level}] ${message}`, context ?? '');
    if (error) console.error(error);
  },
  // ...
});
```

### Log Levels

- **debug** — Token resolution steps, storage reads/writes, low-level details.
- **info** — Successful token refresh, client_credentials renewal, token exchange, authorization_code storage, 401-driven refresh.
- **warn** — Proactive refresh failure, exchange failure, logout endpoint failure.
- **error** — Unrecoverable failures.

All log messages include `authId` in the context map for filtering.

### Default Behavior

If `onLog` is not provided, the SDK produces no diagnostic output. There is no fallback to `console.log`.

See also `onHttpTrace` in [API Reference](api-reference.md) for structured host HTTP request/response tracing (separate from `onLog`).
