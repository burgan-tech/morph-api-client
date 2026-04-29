/// Thrown when Morph JSON config fails validation (parity with TS
/// `ConfigValidationError` in `packages/core/src/errors.ts`).
final class ConfigValidationError implements Exception {
  ConfigValidationError(this.errors) : assert(errors.isNotEmpty);

  final List<String> errors;

  @override
  String toString() => errors.join('; ');
}
