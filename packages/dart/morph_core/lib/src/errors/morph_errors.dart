// Core errors mirroring `@morph/core` packages/core/src/errors.ts.

final class ConfigValidationError implements Exception {
  ConfigValidationError(this.errors) : assert(errors.isNotEmpty);

  final List<String> errors;

  static const String errorName = 'ConfigValidationError';

  @override
  String toString() => errors.join('; ');
}

final class UnknownHostError implements Exception {
  UnknownHostError(this.key);

  final String key;

  static const String errorName = 'UnknownHostError';

  @override
  String toString() => 'Unknown host: $key';
}

final class UnknownProviderError implements Exception {
  UnknownProviderError(this.key);

  final String key;

  static const String errorName = 'UnknownProviderError';

  @override
  String toString() => 'Unknown provider: $key';
}

final class UnknownContextError implements Exception {
  UnknownContextError(this.authId);

  final String authId;

  static const String errorName = 'UnknownContextError';

  @override
  String toString() => 'Unknown auth: $authId';
}

final class InvalidAuthForHostError implements Exception {
  InvalidAuthForHostError(this.hostKey, this.authId, this.allowedAuth);

  final String hostKey;
  final String authId;
  final List<String> allowedAuth;

  static const String errorName = 'InvalidAuthForHostError';

  @override
  String toString() => 'Auth $authId is not allowed for host $hostKey';
}

final class AuthError implements Exception {
  AuthError(this.authId, this.reason, [this.message]);

  final String authId;

  /// `no_token` | `refresh_failed` | `delegation_required` | `exchange_failed`
  final String reason;
  final String? message;

  static const String errorName = 'AuthError';

  @override
  String toString() => message ?? reason;
}

final class TokenEndpointError implements Exception {
  TokenEndpointError(this.statusCode, this.responseText);

  final int statusCode;
  final String responseText;

  static const String errorName = 'TokenEndpointError';

  @override
  String toString() => 'Token endpoint failed: $statusCode $responseText';
}

final class MorphHttpError implements Exception {
  MorphHttpError(this.statusCode, this.path, this.body, [this.resolvedAuth]);

  final int statusCode;
  final String path;
  final Object? body;
  final String? resolvedAuth;

  static const String errorName = 'MorphHttpError';

  @override
  String toString() => 'HTTP $statusCode for $path';
}
