import 'package:morph_core/src/config/validate_config.dart';

/// Public facade mirroring the TypeScript `MorphClient` from `@morph/core`.
///
/// Planned: same JSON config model, OAuth2 token lifecycle, and HTTP pipeline as
/// described in repo `docs/architecture.md`.
///
/// **Config validation** (`validateAndIndexConfig`) is implemented for raw JSON maps.
/// OAuth, plugins, and HTTP calls remain unimplemented; see `docs/dart-parity.md`
/// and GitHub issues [#1](https://github.com/burgan-tech/morph-api-client/issues/1),
/// [#3](https://github.com/burgan-tech/morph-api-client/issues/3).
///
/// References:
/// * TypeScript [MorphClient source](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/client/MorphClient.ts).
class MorphClient {
  MorphClient._();

  /// Mirrors TypeScript `MorphClient.init(config, options)`.
  ///
  /// Validates [config] using the same rules as `@morph/core` /
  /// `validateAndIndexConfig`. Other subsystems remain unimplemented.
  static MorphClient init(Map<String, dynamic> config, MorphOptions options) {
    validateAndIndexConfig(Map<String, dynamic>.from(config));
    throw UnimplementedError(
      'Dart morph_core: runtime, OAuth, plugins, and HTTP pipeline are not '
      'implemented yet. See docs/dart-parity.md and issue #3.',
    );
  }

  /// Tears down resources (parity with TS `MorphClient.dispose()`).
  void dispose() {
    throw UnimplementedError(
      'Dart morph_core scaffold: MorphClient.dispose is not implemented yet.',
    );
  }
}

/// Stand-in for TypeScript `MorphOptions` (`plugins`, callbacks, `_resolvedAuth`, …).
///
/// Typed API will mirror [types.ts](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/types.ts).
typedef MorphOptions = Map<String, Object?>;
