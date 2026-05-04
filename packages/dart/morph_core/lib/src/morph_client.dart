import 'config/validate_config.dart';
import 'runtime/morph_runtime.dart';
import 'types/morph_surface.dart';

/// Public facade mirroring [`MorphClient`] from `@morph/core`.
final class MorphClient {
  MorphClient._(this.runtime);

  /// Resolved config + plugins + HTTP pipeline (parity [`MorphRuntime`]).
  final MorphRuntime runtime;

  static MorphClient init(dynamic config, MorphOptions options) {
    final resolved = validateAndIndexConfig(config);
    final vars = Map<String, String>.from(options.variables ?? const {});
    return MorphClient._(MorphRuntime(resolved, options, vars));
  }

  void dispose() => runtime.dispose();
}
