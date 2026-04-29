/// Public facade mirroring the TypeScript `MorphClient` from `@morph/core`.
///
/// Planned: same JSON config model, OAuth2 token lifecycle, and HTTP pipeline as
/// described in repo `docs/architecture.md`.
///
/// **Scaffold:** [MorphClient.init] throws [UnimplementedError] until parity work
/// lands; see repo `docs/dart-parity.md` and GitHub issue #1.
///
/// References:
/// * TypeScript [MorphClient source](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/client/MorphClient.ts).
class MorphClient {
  MorphClient._();

  /// Mirrors TypeScript `MorphClient.init(config, options)`.
  ///
  /// When implemented: validates config, topologically installs plugins,
  /// exposes host/auth/OAuth helpers equivalent to `@morph/core`.
  static MorphClient init(Map<String, dynamic> config, MorphOptions options) {
    throw UnimplementedError(
      'Dart morph_core scaffold: MorphClient.init is not implemented yet. '
      'See docs/dart-parity.md and issue #1 (morph-api-client).',
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
