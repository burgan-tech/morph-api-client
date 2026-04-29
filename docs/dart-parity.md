# Dart / Flutter SDK parity

The TypeScript implementation is the reference today (`packages/core`, `packages/oauth2`,
`packages/browser-storage`, `packages/logger`). **Dart/Flutter parity** is tracked on
GitHub as [issue #1](https://github.com/burgan-tech/morph-api-client/issues/1); base
branch for work is **`f/plugin`**.

## Scaffold (Phase 1)

The package [`packages/dart/morph_core`](../packages/dart/morph_core) is the first
Dart package:

- **Public import:** `package:morph_core/morph_core.dart`
- **Status:** `MorphClient.init` throws `UnimplementedError` until runtime, HTTP
  pipeline, OAuth, and plugins are ported.
- **CI:** `.github/workflows/dart.yml` runs `dart analyze` and `dart test` for this
  package.

## Design intent (unchanged from TS)

Per [architecture.md](architecture.md):

- Same **JSON config** shape and validation behavior.
- **Mirrored public API** with Dart idioms (`snake_case`, `Future` where async).
- **Platform adapters** for storage and HTTP: see [platform-adapters.md](platform-adapters.md)
  (Flutter secure storage, `dart:io` `HttpClient`, certificate pinning, etc.).

## Next milestones (suggested)

| Milestone | Scope |
|-----------|--------|
| Config + types | Strongly typed `MorphConfig` / `MorphOptions` aligned with `packages/core/src/types.ts` |
| Runtime + plugins | Topological plugin install, `provideAuth` / `provideStorage` equivalents |
| OAuth2 + vault | Port `@morph/oauth2` token lifecycle (or new `packages/dart/morph_oauth2`) |
| Storage | Secure / in-memory adapters for Flutter and VM |
| Logger | Trace + `onLog` chaining like `@morph/logger` |
| Sample | Optional Flutter or Dart VM sample under `poc/` |
