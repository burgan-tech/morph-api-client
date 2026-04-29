# morph_core (Dart)

Dart port of **`@morph/core`** (Morph API Client). See
[`docs/dart-parity.md`](../../../docs/dart-parity.md).

## Implemented (vs TypeScript)

- **`validateAndIndexConfig`** — same validation rules and indexes as
  `packages/core/src/config/validate.ts` (throws **`ConfigValidationError`** with
  aggregated messages).
- **`normalizeExchangeSources`**, **`listAuthIdsForProvider`** — parity with TS helpers.
- **`MorphClient.init`** — runs config validation, then throws **`UnimplementedError`**
  until runtime / OAuth / HTTP / plugins are ported ([#3](https://github.com/burgan-tech/morph-api-client/issues/3)).

Typed **`MorphConfig` / strong `MorphOptions`** DTOs (vs `Map<String,dynamic>`) are
planned; config is validated as decoded JSON maps for now.

```bash
dart pub get
dart analyze --fatal-infos
dart test
```
