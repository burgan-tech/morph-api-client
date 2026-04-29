# Dart / Flutter SDK parity

The TypeScript implementation is the reference today (`packages/core`, `packages/oauth2`,
`packages/browser-storage`, `packages/logger`). **Dart/Flutter parity** is tracked on
GitHub:
- **[issue #1](https://github.com/burgan-tech/morph-api-client/issues/1)** — scaffold (`morph_core` stub, CI entry).
- **[issue #3](https://github.com/burgan-tech/morph-api-client/issues/3)** — **full Dart/TS feature parity** (runtime, OAuth, storage, logger, pipelines).

Base branch for work is **`f/plugin`** unless release policy changes.

## Scaffold + config validation

The package [`packages/dart/morph_core`](../packages/dart/morph_core) is the first Dart package:

- **Public import:** `package:morph_core/morph_core.dart`
- **Done:** **`validateAndIndexConfig`** parity with **`validate.ts`**; **`MorphClient.init`** validates config then **`UnimplementedError`** until runtime/oauth/http ([#3](https://github.com/burgan-tech/morph-api-client/issues/3)).
- **Still TODO:** Typed `MorphConfig` / `MorphOptions` models (vs raw maps), Morph runtime / plugins.

## CI

**.github/workflows/dart.yml** runs `dart analyze --fatal-infos` and `dart test` for this package.

## Design intent (unchanged from TS)

Per [architecture.md](architecture.md):


- Same **JSON config** shape and validation behavior.
- **Mirrored public API** with Dart idioms (`snake_case`, `Future` where async).
- **Platform adapters** for storage and HTTP: see [platform-adapters.md](platform-adapters.md)
  (Flutter secure storage, `dart:io` `HttpClient`, certificate pinning, etc.).

## Next milestones

Detailed backlog and acceptance criteria: **[issue #3 — full Dart/TS parity](https://github.com/burgan-tech/morph-api-client/issues/3)**.

| Milestone | Scope |
|-----------|--------|
| Config validation | **Shipped:** `validateAndIndexConfig` + helpers (parity with `validate.ts`). **Next:** codegen or hand-written `MorphConfig` DTOs + `json` encoding |
| Runtime + plugins | Topological plugin install, `provideAuth` / `provideStorage` equivalents |
| OAuth2 + vault | Port `@morph/oauth2` token lifecycle (or new `packages/dart/morph_oauth2`) |
| Storage | Secure / in-memory adapters for Flutter and VM |
| Logger | Trace + `onLog` chaining like `@morph/logger` |
| Sample | Optional Flutter or Dart VM sample under `poc/` |
