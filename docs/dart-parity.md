# Dart / Flutter SDK parity

The TypeScript implementation is the reference (`packages/core`, `packages/oauth2`,
`packages/browser-storage`, `packages/logger`). **Dart/Flutter parity** is tracked on
GitHub:
- **[issue #1](https://github.com/burgan-tech/morph-api-client/issues/1)** — scaffold (`morph_core`, CI entry).
- **[issue #3](https://github.com/burgan-tech/morph-api-client/issues/3)** — **full Dart/TS feature parity** (remaining gaps).

Base branch for work is **`f/plugin`** unless release policy changes.

**Execution discipline:** milestones are shipped via the repo skill [morph-api-client-issue-pr-merge](../.cursor/skills/morph-api-client-issue-pr-merge/SKILL.md) (issue → PR with `Closes #n` → merge → update docs).

## Current packages

| Dart package | Role | Status |
|-------------|------|--------|
| [`packages/dart/morph_core`](../packages/dart/morph_core) | Config validation, `MorphClient`, `MorphRuntime`, `HostPipeline`, types | **Shipped** (facade parity with TS `MorphClient` / `HostClient` / `AuthHandle` tracked in codebase) |
| [`packages/dart/morph_oauth2`](../packages/dart/morph_oauth2) | Token lifecycle, vault, `oauth2Plugin` | **Shipped** |
| [`packages/dart/morph_storage`](../packages/dart/morph_storage) | In-memory storage plugin | **VM / tests** (`@morph/browser-storage` analogue for apps not yet ported) |
| [`packages/dart/morph_logger`](../packages/dart/morph_logger) | Logger plugin + traces | **Shipped** |

**Public import (core):** `package:morph_core/morph_core.dart`

## Done vs next (milestone summary)

| Milestone | Dart status |
|-----------|--------------|
| Config validation | **Done:** `validateAndIndexConfig` parity with `validate.ts`. |
| `MorphClient.init` → runtime | **Done:** Builds `MorphRuntime` (plugins, HTTP pipeline), not a stub. |
| Runtime + plugins | **Done:** topological install, auth/storage providers wired. |
| HTTP host pipeline | **Done:** `HostPipeline.hostFetch`; `MorphClient.host()` exposes `HostClient`. |
| Public client API | **Done:** TS-style `MorphClient` methods + `AuthHandle` for token helpers. |
| OAuth2 plugin | **Done:** `@morph/oauth2` analogue in `morph_oauth2`. |
| Logger | **Done:** `@morph/logger` analogue in `morph_logger`. |
| Memory storage | **Done:** `morph_storage` module + plugin for tests/tools. |
| OAuth return / redirect | **Done:** `oauthRedirectBase` on `MorphOptions`; `completeOAuthReturn` with conditional `dart:html` + optional `Uri? currentUri`. |
| Typed `MorphConfig` DTOs | **Backlog:** hand-written or codegen from JSON boundary. |
| Persistent storage (adapter) | **Done:** `morph_core_storage` in **morph-data-store** bridges `morph_core.StorageProvider` → `IContextStore` (Device / platform secure storage). Suitable for **mobile/desktop** PoC and production apps that set **ContextStore identity** before user-scoped writes. |
| Flutter PoC (`poc/flutter-poc`) | **Done:** Feature parity with **`poc/ts-vue`** (closes [#27](https://github.com/burgan-tech/morph-api-client/issues/27), PR [#28](https://github.com/burgan-tech/morph-api-client/pull/28)): provider-grouped status, dynamic actions, mock-API sheet + HTTP trace, provider config sheet, JSON-driven simulation (`assets/poc-simulation.json` copy of `docs/poc/poc-simulation.json`). **Web:** uses **in-memory** `StorageProvider` — full-page OAuth reload cannot satisfy ContextStore **user** boundary before the first token write; **non-web** uses **ContextStore** when init succeeds. **`run_web.sh`** defaults to **`--profile`** (fast single bundle; debug reload is slow and can race Keycloak code expiry). Keycloak **`webOrigins`** must include `http://localhost:4200` for **morph-device** and **morph-session** as well as morph-login (browser `POST /token`). **Unit tests:** `poc/flutter-poc/test/poc_simulation_test.dart` (+ `flutter test`); `parsePocSimulationJson`, `isPocSessionDeadStop`, mocked fetch steps. |
| Sample app (minimal) | **Done (earlier milestone):** baseline Flutter app — token status, OAuth, mock call, trace log ([#24](https://github.com/burgan-tech/morph-api-client/issues/24)). |

## CI

**.github/workflows/dart.yml** runs `dart analyze --fatal-infos` and `dart test` for **`morph_core`**, **`morph_oauth2`**, and **`morph_logger`**.

- **`morph_storage`** is intentionally omitted from the matrix while it stays test-only transitively; tracked in backlog [#21](https://github.com/burgan-tech/morph-api-client/issues/21).
- **`poc/flutter-poc`** is **not** in CI yet: `pubspec` uses **`path:`** dependencies on **morph-data-store** checked out beside this repo locally. Adding CI would require a second checkout or publishing those packages.

## Design intent (aligned with TS)

Per [architecture.md](architecture.md):

- Same **JSON config** shape and validation behavior.
- **Mirrored public API** with Dart idioms (`snake_case`, `Future` where async).
- **Platform adapters** for storage and HTTP: [platform-adapters.md](platform-adapters.md).

## Detailed backlog

Acceptance criteria and epic tracking: **[issue #3](https://github.com/burgan-tech/morph-api-client/issues/3)**.

When starting work on a backlog row (typed `MorphConfig`, **`morph_storage` in CI**, façade polish, OAuth hardening, `package:web` migration), use the open issues **[#18](https://github.com/burgan-tech/morph-api-client/issues/18)**–**[#22](https://github.com/burgan-tech/morph-api-client/issues/22)** and epic **[issue #3](https://github.com/burgan-tech/morph-api-client/issues/3)**. Drive each slice with the [morph-api-client-issue-pr-merge](../.cursor/skills/morph-api-client-issue-pr-merge/SKILL.md) workflow so it stays reviewable.
