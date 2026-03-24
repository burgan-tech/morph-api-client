# Morph TypeScript SDK — Vue PoC

Demonstrates `morph-api-client` from [`../../core`](../../core) against the local Keycloak realm and mock API.

## Prereqs

1. Keycloak: `cd ../keycloak && docker compose up -d` then `./setup.sh` if needed.
2. Mock API: `cd ../mock-api && npm install && npm start`
3. Copy `.env.example` to `.env` and adjust secrets (defaults match the imported realm).

## Run

```bash
npm install
npm run dev
```

Open http://localhost:5173 — acquire device token, log in via Keycloak, then use the home page for token status, mock API calls, and token exchange.

### Routes

| Route | Purpose |
|-------|---------|
| `/` | Home — token status, login, mock API, simulation |
| `/oauth/callback` | Generic OAuth callback (all providers) |

### Simulation

Periodic mock API calls with latency + status table, verbose SDK console logs. Short Keycloak token lifetimes: `poc/keycloak/set-simulation-lifetimes.sh`. See [Simulation guide](../../docs/poc/simulation.md).

### Device token identity (web vs mobile)

| Concept | Mobile | Web PoC |
|---------|--------|---------|
| Device id | Physical device / app instance | `localStorage` UUID (`morph-poc:device-id`) |
| Installation id | First-install GUID | `sessionStorage` UUID (`morph-poc:installation-id`); new tab = new id |

Pin with `VITE_DEVICE_ID` / `VITE_INSTALLATION_ID` in `.env` for demos or CI.

### Token storage

Tokens are stored in `sessionStorage` (prefixed `morph-poc:tk:`) via the SDK's `createBrowserSessionStorage` factory — tokens survive SPA reloads but not new tabs.

### CORS proxies (dev only)

The SDK exchanges authorization codes at the provider's token URL from the browser. Keycloak and Google block this cross-origin.

`vite.config.ts` proxies:
- `/__keycloak/...` → `localhost:8080`
- `/__google-oauth/...` → `https://oauth2.googleapis.com`

The Keycloak login page opens at port 8080; Google consent at `accounts.google.com`. Only token POSTs go through the dev server.

## Google (optional)

Set `VITE_GOOGLE_CLIENT_ID` / `VITE_GOOGLE_CLIENT_SECRET` in `.env`. See [Google setup guide](../../docs/poc/google-setup.md).
