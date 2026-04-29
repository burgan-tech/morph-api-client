import 'package:morph_core/morph_core.dart';

/// Public facade mirroring [`MorphClient`] from `@morph/core`.
class MorphClient {
  MorphClient._();

  static MorphClient init(dynamic config, MorphOptions options) {
    validateAndIndexConfig(config);
    throw UnimplementedError(
      'MorphClient runtime bootstrap is not wired yet. Use validateAndIndexConfig '
      '(typed [MorphConfig] + plugins) pending full integration.',
    );
  }

  void dispose() {}
}
