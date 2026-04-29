## Goal

Deliver a **Dart/Flutter Morph API Client** with **functional parity** to the existing TypeScript implementation (`packages/core`, `packages/oauth2`, `packages/browser-storage`, `packages/logger`): same **JSON configuration schema**, same **OAuth2 / multi-context token lifecycle**, **HTTP pipeline behavior** (auth resolution, retry, trace, 401 recovery), and **plugin composition** (`provides` / `requires`, `provideAuth` / `provideStorage`, logger chaining).

Foundation: Phase 1 scaffold in `packages/dart/morph_core` ([#1](https://github.com/burgan-tech/morph-api-client/issues/1), base branch **`f/plugin`**).

References:
- [docs/architecture.md](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/docs/architecture.md)
- [docs/api-reference.md](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/docs/api-reference.md)
- [docs/configuration.md](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/docs/configuration.md)
- [docs/platform-adapters.md](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/docs/platform-adapters.md)
- [docs/token-lifecycle.md](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/docs/token-lifecycle.md)

## Scope (parity targets)

| TS package | Dart target (name TBD in PRs; split like TS) | Feature parity checklist |
|------------|---------------------------------------------|---------------------------|
| `@morph/core` | `morph_core` (expand scaffold) | `MorphClient`, `MorphRuntime`-equivalent, `MorphConfig` validation/interpolation, `HostPipeline`, `HostClient`, `AuthHandle`, errors, HTTP trace events, plugin topo-sort + `MorphPluginContext` |
| `@morph/oauth2` | e.g. `morph_oauth2` | `AuthPlugin`, `TokenLifecycle`, `TokenVault`, OAuth helpers, refresh / exchange / 401 recovery behavior aligned with [token-lifecycle.md](docs/token-lifecycle.md) |
| `@morph/browser-storage` | e.g. `morph_secure_storage` or VM-first | `StorageProvider`; Flutter: secure storage / memory paths per [platform-adapters.md](docs/platform-adapters.md) |
| `@morph/logger` | packaged or nested | Optional logger plugin chaining `onLog` / `onHttpTrace` like TS |

**Non-functional:** idiomatic Dart (`snake_case` public APIs, `Future`/streams where async), deterministic tests mirroring TS test intent where configs align.

## Out of scope (unless explicitly expanded)

- Changing the **canonical JSON schema** consumed by TS (Dart must **validate** against the same semantics; schema evolution stays coordinated).
- UI samples (optional follow-up PoC); this issue tracks **SDK parity** first.

## Acceptance criteria

- [ ] **`dart analyze`** and **`dart test`** pass for every shipped Dart package in CI (extend [`.github/workflows/dart.yml`](.github/workflows/dart.yml) or split jobs per package).
- [ ] **`MorphClient.init`** with real config + `@morph/oauth2`-parity + storage plugin can obtain tokens and execute **authenticated host requests** (VM or Flutter test harness), behavior consistent with documented TS flows.
- [ ] **Docs:** [docs/dart-parity.md](docs/dart-parity.md) updated when parity milestones land; parity matrix references TS APIs.
- [ ] **Regression parity:** Critical paths covered by tests analogous to TS (fixture JSON configs where shared).

## Suggested sequencing (milestones inside this issue)

1. Typed **`MorphConfig` / `MorphOptions`** + validators + interpolate variables (Dart).
2. **Runtime + plugins** equivalent to TS `MorphRuntime`, `runtime.ts`.
3. **OAuth2 package** parity (`TokenLifecycle`, vault, OAuth URL/callback helpers).
4. **Storage** plugins (VM then Flutter secure storage adapters).
5. **Logger** plugin parity.
6. **Integration / gold tests** against same sample config files as TS (where practical).

---

**Blocked by / related:** [#1](https://github.com/burgan-tech/morph-api-client/issues/1) (scaffold + CI entry point).

**Branch policy:** Deliver against **`f/plugin`** unless release policy moves default branch.
