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
| Persistent / browser storage | **Done:** `morph_core_storage` adapter in `morph-data-store` bridges `StorageProvider` → `IContextStore` (Keychain/KeyStore); `poc/flutter-poc` switched from in-memory to persistent storage. |
| Sample app | **Done:** `poc/flutter-poc` Flutter app — token status, OAuth login, mock-API call, HTTP trace log (closes #24). |

## CI

**.github/workflows/dart.yml** runs `dart analyze --fatal-infos` and `dart test` for `morph_core`, `morph_oauth2`, and `morph_logger`. **`morph_storage`** is intentionally omitted from the matrix while it stays test-only transitively; add when it has standalone coverage.

## Design intent (aligned with TS)

Per [architecture.md](architecture.md):

- Same **JSON config** shape and validation behavior.
- **Mirrored public API** with Dart idioms (`snake_case`, `Future` where async).
- **Platform adapters** for storage and HTTP: [platform-adapters.md](platform-adapters.md).

## Detailed backlog

Acceptance criteria and epic tracking: **[issue #3](https://github.com/burgan-tech/morph-api-client/issues/3)**.

When starting work on a backlog row (persistent / browser storage, typed `MorphConfig`, `poc/` sample, adding `morph_storage` to CI), open a **dedicated GitHub issue** and drive it with the [morph-api-client-issue-pr-merge](../.cursor/skills/morph-api-client-issue-pr-merge/SKILL.md) workflow so each slice stays reviewable.
