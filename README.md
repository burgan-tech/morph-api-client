# Morph API Client

Config-driven, multi-context HTTP client with built-in OAuth2 token lifecycle management.

## Quick start (Vue PoC)

From the **repository root** (no `cd` into `poc/ts-vue`):

```bash
cd core && npm install && npm run build
cd ../poc/ts-vue && npm install
cd ../..
npm run dev
```

After the first setup, from root:

```bash
npm run dev
```

Opens **http://127.0.0.1:5173/** (Vite + Keycloak proxy). Rebuild the SDK after `core/` changes:

```bash
npm run build:core
```

## Layout

| Path | Role |
|------|------|
| `core/` | `morph-api-client` TypeScript SDK package |
| `core/src/runtime.ts` | MorphRuntime — thin coordinator |
| `core/src/tokens/` | TokenLifecycle + TokenVault |
| `core/src/http/` | HostPipeline (host HTTP + 401 recovery) |
| `core/src/client/` | MorphClient, HostClient, AuthHandle facades |
| `poc/ts-vue/` | Vue 3 demo app |
| `poc/keycloak/` | Docker Keycloak realm |
| `poc/mock-api/` | Mock REST API |
| `docs/` | Design & API docs |
