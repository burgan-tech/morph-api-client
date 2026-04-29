## Goal

Add a **Dart/Flutter** SDK that mirrors the TypeScript Morph API client: same JSON config and public API shape (`docs/architecture.md`, `docs/api-reference.md`).

Base branch for all Dart work: **`f/plugin`**.

---

## Phase 1 (scaffold) — landed via PR `feat/dart-sdk-scaffold` → `f/plugin`

Use **`Refs #1`** in that PR description to keep this issue as the tracking epic, or **`Closes #1`** if you only wanted the scaffold.

- [x] `packages/dart/morph_core` with `pubspec`, analysis, stub `MorphClient.init` (throws `UnimplementedError`)
- [x] GitHub Actions: `dart analyze` + `dart test` (`.github/workflows/dart.yml`)
- [x] `docs/dart-parity.md` + index in `docs/README.md`

Local run: `make dart-all` or `cd packages/dart/morph_core && dart pub get && dart analyze && dart test`.

---

## Later phases (sub-issues or checklist)

- [ ] Strongly typed `MorphConfig` / `MorphOptions` aligned with `packages/core/src/types.ts`
- [ ] Runtime + topological plugin install (parity with `packages/core/src/runtime.ts`)
- [ ] Port `@morph/oauth2` (new package e.g. `packages/dart/morph_oauth2` or `lib/src/oauth2/`)
- [ ] Storage adapters (Flutter / VM) per `docs/platform-adapters.md`
- [ ] Logger / HTTP trace hooks
- [ ] Optional Dart/Flutter sample under `poc/`
