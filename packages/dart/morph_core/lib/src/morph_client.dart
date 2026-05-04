import 'config/validate_config.dart';
import 'client/auth_handle.dart';
import 'client/host_client.dart';
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

  HostClient host(String key) {
    runtime.assertAlive();
    return HostClient(runtime, runtime.getHost(key));
  }

  AuthHandle auth(String authId) {
    runtime.assertAlive();
    runtime.parseAuthRef(authId);
    return AuthHandle(runtime, authId);
  }

  Future<List<MorphTokenStatus>> getTokenStatus() {
    runtime.assertAlive();
    return runtime.getTokenStatus();
  }

  MorphProviderMeta getProviderMeta(String providerKey) {
    runtime.assertAlive();
    return runtime.getProviderMeta(providerKey);
  }

  List<String> getExchangeTargets(String sourceAuthId) {
    runtime.assertAlive();
    return runtime.getExchangeTargets(sourceAuthId);
  }

  List<String> getExchangeSources(String targetAuthId) {
    runtime.assertAlive();
    return runtime.getExchangeSources(targetAuthId);
  }

  bool isAuthContextReady(String authId) {
    runtime.assertAlive();
    return runtime.isAuthContextReady(authId);
  }

  bool isProviderEnvReady(String providerKey) {
    runtime.assertAlive();
    return runtime.isProviderEnvReady(providerKey);
  }

  String getAuthorizationUrl(String authId, {String? state}) {
    runtime.assertAlive();
    return runtime.getAuthorizationUrl(authId, state: state);
  }

  Future<OAuthReturnResult> completeOAuthCallback({
    String? code,
    String? state,
    String? error,
    String? errorDescription,
  }) {
    runtime.assertAlive();
    return runtime.completeOAuthCallback(
      code: code,
      state: state,
      error: error,
      errorDescription: errorDescription,
    );
  }

  Future<OAuthReturnResult> completeOAuthReturn({Uri? currentUri}) {
    runtime.assertAlive();
    return runtime.completeOAuthReturn(currentUri: currentUri);
  }

  Future<OAuthReturnResult> completeAuthorizationReturnFromUrl({Uri? currentUri}) {
    runtime.assertAlive();
    return runtime.completeAuthorizationReturnFromUrl(currentUri: currentUri);
  }

  void dispose() => runtime.dispose();
}
