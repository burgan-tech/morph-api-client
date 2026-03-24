# Morph API Client

Config-driven, multi-context HTTP client with built-in OAuth2 token lifecycle management.

## Quick start (Vue PoC)

**Prerequisites:** Docker, Node.js 20+, python3, curl

### 1. Keycloak + Mock API

```bash
# Start Keycloak (first run pulls image ~500MB)
cd poc/keycloak && docker compose up -d

# Wait for Keycloak & configure realm (takes ~30s on first run)
bash setup.sh

# Start mock API (separate terminal)
cd poc/mock-api && npm install && node server.js
```

If you see "Realm 'morph' not found", the Docker volume has stale data:

```bash
docker compose down -v && docker compose up -d && bash setup.sh
```

### 2. SDK + Vue app

```bash
# From repository root
cd core && npm install && npm run build
cd ../poc/ts-vue && npm install
cd ../..
npm run dev
```

Opens **http://127.0.0.1:5173/**. Rebuild the SDK after `core/` changes:

```bash
npm run build:core
```

### 3. Verify

```bash
cd poc/keycloak && bash test-flows.sh
```

All 5 tests should pass (device token, login, refresh rotation, token exchange, JWT decode).

### Optional: Google OAuth

See [docs/poc/google-setup.md](docs/poc/google-setup.md) for external IdP integration.

## Layout

| Path | Role |
|------|------|
| `core/` | `morph-api-client` TypeScript SDK package |
| `core/src/runtime.ts` | MorphRuntime — thin coordinator |
| `core/src/tokens/` | TokenLifecycle + TokenVault |
| `core/src/http/` | HostPipeline (host HTTP + 401 recovery) |
| `core/src/client/` | MorphClient, HostClient, AuthHandle facades |
| `poc/ts-vue/` | Vue 3 demo app |
| `poc/keycloak/` | Docker Keycloak realm + setup/test scripts |
| `poc/mock-api/` | Mock REST API (Express, validates JWT via Keycloak/Google) |
| `docs/` | Design & API docs |
