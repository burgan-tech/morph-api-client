import 'package:morph_core/src/config/resolved_morph_config.dart';
import 'package:morph_core/src/types/morph_types.dart';

typedef OAuthReturnStatus = String;

final class OAuthReturnResult {
  const OAuthReturnResult({required this.status, this.message});

  final OAuthReturnStatus status;
  final String? message;

  Map<String, dynamic> toJson() => {
        'status': status,
        if (message != null) 'message': message,
      };
}

final class MorphContextMeta {
  const MorphContextMeta({
    required this.key,
    required this.authId,
    this.clientId,
    this.clientAuth,
    this.audience,
    this.identity,
    this.authorization,
    required this.token,
    this.logout,
    this.scopes,
    this.pkce,
    this.refreshPolicy,
    this.recoveryPolicy,
    this.delegateMetadata,
    this.sessionPolicy,
    this.networkPolicy,
    this.headers,
    required this.tokenTypes,
  });

  final String key;
  final String authId;
  final String? clientId;
  final String? clientAuth;
  final String? audience;
  final IdentityBlock? identity;
  final AuthorizationBlock? authorization;
  final TokenBlock token;
  final LogoutBlock? logout;
  final List<String>? scopes;
  final PkceBlock? pkce;
  final RefreshPolicyBlock? refreshPolicy;
  final RecoveryPolicy? recoveryPolicy;
  final DelegateMetadata? delegateMetadata;
  final Map<String, String>? sessionPolicy;
  final NetworkPolicy? networkPolicy;
  final Map<String, String>? headers;
  final Map<String, TokenTypeConfig> tokenTypes;
}

final class MorphProviderMeta {
  const MorphProviderMeta({
    required this.key,
    required this.type,
    required this.baseUrl,
    this.authorizationBrowserBaseUrl,
    this.tokenHttpBaseUrl,
    this.networkPolicy,
    this.headers,
    required this.contexts,
  });

  final String key;
  final String type;
  final String baseUrl;
  final String? authorizationBrowserBaseUrl;
  final String? tokenHttpBaseUrl;
  final NetworkPolicy? networkPolicy;
  final Map<String, String>? headers;
  final List<MorphContextMeta> contexts;
}

final class TokenSet {
  const TokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.metadata,
  });

  factory TokenSet.fromJson(Map<String, dynamic> m) => TokenSet(
        accessToken: m['accessToken'] as String? ?? '',
        refreshToken: m['refreshToken'] as String?,
        expiresAt: (m['expiresAt'] as num?)?.toInt(),
        metadata: m['metadata'] is Map ? Map<String, Object?>.from(m['metadata'] as Map) : null,
      );

  final String accessToken;
  final String? refreshToken;
  final int? expiresAt;
  final Map<String, Object?>? metadata;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (metadata != null) 'metadata': metadata,
      };
}

final class MorphTokenStatus {
  const MorphTokenStatus({
    required this.authId,
    required this.providerKey,
    required this.contextKey,
    this.grantHint,
    required this.hasAccessToken,
    required this.hasRefreshToken,
    required this.accessLikelyValid,
    this.expiresAt,
    this.jwtExp,
    this.claims,
    this.decodeError,
    this.refreshClaims,
    this.refreshJwtExp,
    this.refreshDecodeError,
  });

  final String authId;
  final String providerKey;
  final String contextKey;
  final String? grantHint;
  final bool hasAccessToken;
  final bool hasRefreshToken;
  final bool accessLikelyValid;
  final int? expiresAt;
  final int? jwtExp;
  final Map<String, Object?>? claims;
  final String? decodeError;
  final Map<String, Object?>? refreshClaims;
  final int? refreshJwtExp;
  final String? refreshDecodeError;
}

typedef MorphLogFn = void Function(
  String level,
  String message, [
  Object? error,
  Map<String, Object?>? context,
]);

final class ProxyConfig {
  const ProxyConfig({required this.url});
  final String url;
}

final class ClientCertificate {
  const ClientCertificate({
    required this.cert,
    required this.key,
    this.passphrase,
  });
  final String cert;
  final String key;
  final String? passphrase;
}

final class NetworkConfig {
  const NetworkConfig({this.certificatePins, this.proxy, this.clientCertificate});
  final List<String>? certificatePins;
  final ProxyConfig? proxy;
  final ClientCertificate? clientCertificate;
}

final class TokenExchangeGrant {
  const TokenExchangeGrant({
    required this.type,
    required this.authId,
    this.code,
    this.codeVerifier,
    this.sourceAuthId,
    this.sourceToken,
    this.refreshToken,
  });

  final String type;
  final String authId;
  final String? code;
  final String? codeVerifier;
  final String? sourceAuthId;
  final String? sourceToken;
  final String? refreshToken;
}

abstract class StorageProvider {
  Future<String?> read(String key, StorageConfig storageConfig);
  Future<void> write(String key, String value, StorageConfig storageConfig);
  Future<void> delete(String key, StorageConfig storageConfig);
  Future<void> deleteByPrefix(String prefix, StorageConfig storageConfig);
}

abstract class AuthPlugin {
  Future<String> resolveAccessToken(String authId, CtxRef ref, String mode);
  Future<void> handle401Recovery(String authId, CtxRef ref);
  void fireAuthRequired(String authId, AuthContextConfig ctx);
  Future<void> submitCode(String authId, CtxRef ref, String code,
      {String? codeVerifier, String? redirectUriOverride});
  Future<void> acquireWithClientCredentials(String authId, CtxRef ref);
  Future<void> exchangeToken(String sourceAuthId, CtxRef sourceRef, String targetAuthId);
  Future<void> setTokens(String authId, CtxRef ref, TokenSet tokens);
  Future<void> clearTokens(String authId, CtxRef ref);
  Future<TokenSet?> loadTokens(String authId, CtxRef ref);
  Future<void> logout(String authId, CtxRef ref, String reason);
  Future<void> logoutProvider(String providerKey, String reason);
  Future<bool> hasValidTokenContext(String authId, CtxRef ref);
  Future<bool> hasValidTokenProvider(String providerKey);
  Future<void> refreshTokensManual(String authId, CtxRef ref);
  void dispose();
}

typedef MorphSignPayloadFn = Future<String> Function(String payload, String authId);
typedef MorphDecryptFn = Future<String> Function(String encryptedBody, String authId);

abstract class MorphPlugin {
  String get name;
  List<String>? get provides => null;
  List<String>? get requires => null;

  void install(MorphPluginContext ctx);
  void dispose() {}
}

final class MorphOptions {
  MorphOptions({
    required this.plugins,
    this.variables,
    this.oauthRedirectBase,
    this.networkDelegate,
    this.onSignPayload,
    this.onDecryptResponse,
    this.onLog,
    this.onHttpTrace,
  });

  final List<MorphPlugin> plugins;
  final Map<String, String>? variables;

  /// When set (e.g. full `https://` callback origin), overrides [Uri.base] for root
  /// OAuth code exchange redirect URI. Prefer on Flutter VM/desktop/native where
  /// `Uri.base` is not the web app origin.
  final String? oauthRedirectBase;

  final Future<NetworkConfig?> Function(String hostname)? networkDelegate;
  final MorphSignPayloadFn? onSignPayload;
  final MorphDecryptFn? onDecryptResponse;
  MorphLogFn? onLog;
  void Function(MorphHttpTraceEvent event)? onHttpTrace;

  AuthPlugin? resolvedAuth;
  StorageProvider? resolvedStorage;
}

final class MorphPluginContext {
  MorphPluginContext({
    required this.resolved,
    required this.options,
    required this.variables,
    required this.provideAuth,
    required this.provideStorage,
  });

  final ResolvedMorphConfig resolved;
  final MorphOptions options;
  final Map<String, String> variables;

  final void Function(AuthPlugin auth) provideAuth;
  final void Function(StorageProvider storage) provideStorage;
}

final class MorphHttpTraceEvent {
  const MorphHttpTraceEvent({
    required this.kind,
    required this.hostKey,
    required this.method,
    required this.url,
    required this.path,
    required this.authId,
    required this.requestHeaders,
    required this.statusCode,
    required this.responseHeaders,
    required this.responseBody,
    required this.durationMs,
    this.networkError,
  });

  final String kind;
  final String hostKey;
  final String method;
  final String url;
  final String path;
  final String authId;
  final Map<String, String> requestHeaders;
  final int statusCode;
  final Map<String, String> responseHeaders;
  final Object? responseBody;
  final int durationMs;
  final String? networkError;
}

final class HostRequestOptions {
  const HostRequestOptions({
    this.auth,
    this.headers,
    this.queryParams,
    this.timeout,
    this.sign,
    this.encrypted,
  });

  final Object? auth;
  final Map<String, String>? headers;
  final Map<String, String>? queryParams;
  final String? timeout;
  final bool? sign;
  final bool? encrypted;
}

final class HostFullRequestOptions extends HostRequestOptions {
  const HostFullRequestOptions({
    required this.method,
    required this.path,
    this.body,
    super.auth,
    super.headers,
    super.queryParams,
    super.timeout,
    super.sign,
    super.encrypted,
  });

  final String method;
  final String path;
  final Object? body;
}

final class MorphResponse<T> {
  const MorphResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.resolvedAuth,
    this.raw,
  });

  final int statusCode;
  final Map<String, String> headers;
  final T body;
  final String resolvedAuth;
  final Object? raw;
}
