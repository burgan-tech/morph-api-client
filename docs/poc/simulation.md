# PoC — Simulation screen

The PoC Vue app imports a single file: **`docs/poc/poc-simulation.json`**. It drives the **Simulation** loop (default **every 5 seconds**), the **Mock API** modal buttons (same root `steps` plus each conditional block’s `steps`, with `when` checked on click), and shared step execution. Step kinds: **`fetch`**, **`host`** (`method`, `path`, `auth`, optional `body` / `headers` / `tickHeaderName`), **`logout_provider`** (`providerKey` — never run on auto ticks). Optional **`skipInAutoSim`** on `fetch`/`host` skips a step in the loop but keeps it in the modal. **Conditional** blocks (e.g. Google verify, 404 probe) and **`sessionDeadCheck`** behave as before.

## What it does

The JSON **`mockApi`** block defines the **mock HTTP base** for `fetch` steps: **`baseUrl`** (required for clarity; no trailing slash) is the canonical default. Optional **`envOverride`** (e.g. `VITE_MOCK_API_BASE`) — when that env var is set at build time, it overrides `baseUrl` so you can point at another mock host without editing JSON. **`host`** steps ignore `mockApi`; they use the **`main-api`** (or other) `baseUrl` from **`morph-config.json`**.

The **`steps`** array runs in order each tick. **`conditionalBlocks`** add steps when their `when` condition holds; optional **`skipRow`** records a single **SKIP** row when the condition is false (e.g. Google not logged in). See the file for the default scenario (public `fetch`, 1fa/2fa/device host calls, optional Google + 404 probe).

**Google**: same semantics as before — block uses stored Google token when configured.

**404 probe**: gated by the **Include 404 probe** checkbox; JSON uses `{ "type": "ui_flag_probe_404" }` on the block’s `when`.

**Ignore `when` (full conditional run)**: optional checkbox — when on, every `conditionalBlocks` step list runs each tick even if `when` would be false (no SKIP row for that block). Use this to see AUTH/noise for optional paths (e.g. Google) instead of silent skips.

The table shows **status**, **total ms**, and a short **detail** line. **Verbose console** mirrors each step as `[sim]` and, when enabled, bumps Morph SDK logs (including `debug`) so refresh/token-endpoint activity is visible.

### Session dead (`sessionDeadCheck`)

If **one tick** yields **AUTH** for **every** auth id listed in **`sessionDeadCheck.authIds`** in `docs/poc/poc-simulation.json` (default: **1fa** and **2fa**), the loop **stops** and the banner shows **`sessionDeadCheck.message`**. Adjust the list or message in JSON if your scenario differs.

## Flutter PoC executor

The Flutter app at **`poc/flutter-poc`** includes a copy of this document’s JSON as **`assets/poc-simulation.json`**. Execution is implemented in **`lib/poc_simulation.dart`**:

- **`fetch`** — `GET` via `package:http` to `mockApi.baseUrl` (with timeout); same step shape as Vue.
- **`host`** — `MorphRuntime.http.hostFetch` with `method`, `path`, `auth`, optional `body` / `headers`.
- **`logout_provider`** — `MorphClient.auth(providerKey).logout()`.

Parsing is synchronous via **`parsePocSimulationJson`** (tests) and **`loadPocSimulation`** (loads the asset). The **Simulation** panel runs steps **when the user taps Run** (not on a fixed interval like the Vue dev server’s default tick). **Session dead:** after an **AUTH** result, **`isPocSessionDeadStop`** requires the step’s host **`auth`** to be listed in **`sessionDeadCheck.authIds`** *and* `invalid_grant` or `Token is not active` in the error detail (parentheses matter — see unit tests). **Unit tests:** `poc/flutter-poc/test/poc_simulation_test.dart`.

## Short token lifetimes (Keycloak)

**Fresh** imports use the short defaults below (`morph-realm.json`). If Keycloak was created from an older export or you ran **`restore-simulation-lifetimes.sh`** (long-lived PoC), re-apply the short profile (Keycloak must be up):

```bash
cd poc/keycloak
chmod +x set-simulation-lifetimes.sh restore-simulation-lifetimes.sh
./set-simulation-lifetimes.sh
```

Realm import (`morph-realm.json`) and this script align on:

- **`morph-login` (2fa):** access **30s**, **client session idle 60s** (controls how long refresh stays valid without activity; rotating refresh extends the session)
- **`morph-session` (1fa):** access **20s**, **client session idle 60s**
- **`morph-device`:** access **15s** (`client_credentials`, re-acquired when expired)

Revert:

```bash
./restore-simulation-lifetimes.sh
```

After changing lifetimes, **sign in again** in the browser so new grants pick up the new settings.

## Optional: SDK refresh lead time

In `poc/.env` or `poc/ts-vue/.env`:

```bash
VITE_SIMULATION_MODE=true
```

Restart `npm run dev`. The SDK config then uses **`refreshBeforeExpiry: 5s`** on **2fa** and **1fa** so proactive refresh runs closer to expiry (works together with short JWT lifetimes from Keycloak).

## Optional: mock API base URL

If the mock API is not on `http://localhost:3000`:

```bash
VITE_MOCK_API_BASE=http://127.0.0.1:3000
```

The simulation `fetch` steps use this; `morph` still uses `morph-config.json` host `main-api` — change that too if the host differs.

## Requirements

- Mock API running (`poc/mock-api`)
- Keycloak + realm for Morph-authenticated steps
- For meaningful **1fa/2fa** rows, complete login and **2fa → 1fa** exchange as in the main PoC flow first
