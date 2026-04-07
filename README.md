# Morph API Client

Config-driven, multi-context HTTP client with built-in OAuth2 token lifecycle management.

## Quick start

**Prerequisites:** Docker, Node.js 20+, python3, curl

### First time setup

```bash
make install        # install all npm dependencies
make build          # build all SDK packages
cp poc/ts-vue/.env.example poc/ts-vue/.env   # create env with client secrets
make up             # start Keycloak + setup + mock API + Vue dev server
```

### Day-to-day

```bash
make up             # start full stack (Keycloak -> setup -> mock API -> Vue)
make down           # stop everything
```

Opens **http://127.0.0.1:5173/** (Vue PoC). Run `make help` to see all targets.

### Makefile targets

| Target | Description |
|--------|-------------|
| `make install` | Install npm deps for all packages, Vue PoC, and mock API |
| `make build` | Build all SDK packages (core -> oauth2 -> browser-storage) |
| `make up` | Start full stack: Keycloak -> setup -> mock API -> Vue |
| `make down` | Stop all services |
| `make dev` | Start Vue dev server only (http://127.0.0.1:5173) |
| `make mock-api` | Start mock API server only (http://localhost:3000) |
| `make keycloak-up` | Start Keycloak container (port 8080) |
| `make keycloak-down` | Stop Keycloak container |
| `make keycloak-setup` | Run realm setup (clients, redirects, lifetimes, tests) |
| `make keycloak-test` | Run OAuth2 flow smoke tests |
| `make keycloak-logs` | Tail Keycloak logs |
| `make keycloak-short-tokens` | Apply short token lifetimes (15s/30s/20s) |
| `make keycloak-restore-tokens` | Restore long-lived token lifetimes |
| `make clean` | Remove node_modules and dist |

### Services

| Service | URL |
|---------|-----|
| Vue PoC | http://127.0.0.1:5173 |
| Mock API | http://localhost:3000 |
| Keycloak Admin | http://localhost:8080/admin (admin/admin) |

## Documentation

See **[docs/README.md](docs/README.md)** for the full documentation index.

| Document | Description |
|----------|-------------|
| [Overview](docs/overview.md) | System architecture, auth flow diagrams, Keycloak client mapping |
| [PoC Guide](docs/poc-guide.md) | Step-by-step walkthrough of the Vue PoC app |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and fixes |
| [Getting Started](docs/getting-started.md) | SDK installation and basic usage |
| [Writing Plugins](docs/writing-plugins.md) | How to create custom plugins (auth, storage, or utility) |
| [Configuration](docs/configuration.md) | Full config field reference |
| [API Reference](docs/api-reference.md) | Complete public API |
| [Architecture](docs/architecture.md) | Internal design and module structure |

## Layout

| Path | Package | Role |
|------|---------|------|
| `packages/core/` | `@morph/core` | Types, config, HTTP pipeline, MorphClient, AuthHandle |
| `packages/oauth2/` | `@morph/oauth2` | TokenLifecycle, TokenVault, OAuth helpers |
| `packages/browser-storage/` | `@morph/browser-storage` | sessionStorage / localStorage adapters |
| `poc/ts-vue/` | | Vue 3 demo app |
| `poc/keycloak/` | | Docker Keycloak realm + setup/test scripts |
| `poc/mock-api/` | | Mock REST API (Express, validates JWT) |
| `docs/` | | Design & API docs |
