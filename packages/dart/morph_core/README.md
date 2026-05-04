# morph_core (Dart)

Dart port of **`@morph/core`** (Morph API Client). See
[`docs/dart-parity.md`](../../../docs/dart-parity.md).

## Implemented (vs TypeScript)

- **`validateAndIndexConfig`** — same validation rules and indexes as
  `packages/ts/core/src/config/validate.ts` (throws **`ConfigValidationError`** with
  aggregated messages).
- **`normalizeExchangeSources`**, **`listAuthIdsForProvider`** — parity with TS helpers.
- **`MorphClient`**, **`MorphRuntime`**, plugin install (**`provides` / `requires`**),
  **`HostPipeline.hostFetch`**, and **`MorphPlugin`** surface — shipped; mirrors TS
  client/runtime/pipeline behavior per **`docs/dart-parity.md`**.
- Public OAuth helpers (authorize URL, OAuth state/return utilities), JWT helpers,
  and types aligned with **`packages/ts/core`** exports where applicable.

Typed **`MorphConfig` / strong `MorphOptions`** DTOs (vs `Map<String,dynamic>`) remain
**backlog**; config is validated as decoded JSON maps for now ([#3](https://github.com/burgan-tech/morph-api-client/issues/3)).

```bash
dart pub get
dart analyze --fatal-infos
dart test
```
