import '../config/exchange_sources.dart';
import '../config/interpolate_config.dart';
import '../config/resolved_morph_config.dart';
import '../errors/morph_errors.dart';
import '../http/host_pipeline.dart';
import '../types/morph_surface.dart';
import '../types/morph_types.dart';
import '../util/jwt_utils.dart';
import '../util/oauth_authorize.dart';
import '../util/oauth_state.dart';
import 'oauth_return_browser_stub.dart'
    if (dart.library.html) 'oauth_return_browser.dart';
import 'plugin_install.dart';

/// Result of [MorphRuntime.parseAuthRef] (parity TS union on `parseAuthRef`).
sealed class ParsedAuthRef {
  const ParsedAuthRef();
}

final class ParsedAuthContext extends ParsedAuthRef {
  ParsedAuthContext({required this.authId, required this.ref});

  final String authId;
  final CtxRef ref;
}

final class ParsedAuthProvider extends ParsedAuthRef {
  ParsedAuthProvider({required this.providerKey});

  final String providerKey;
}

/// Parity: [`MorphRuntime`](/packages/ts/core/src/runtime.ts).
final class MorphRuntime {
  MorphRuntime(
    this.resolved,
    this.options,
    Map<String, String> variables,
  ) : _variables = Map<String, String>.from(variables) {
    final installed = installMorphPlugins(
      options.plugins,
      resolved,
      options,
      _variables,
    );
    tokens = installed.auth;
    storage = installed.storage;
    options.resolvedAuth = tokens;
    options.resolvedStorage = storage;
    http = HostPipeline(
      resolved: resolved,
      options: options,
      variables: _variables,
      tokens: tokens,
    );
    _plugins = List<MorphPlugin>.from(options.plugins);
  }

  final ResolvedMorphConfig resolved;
  final MorphOptions options;
  final Map<String, String> _variables;

  late final AuthPlugin tokens;
  late final StorageProvider storage;
  late final HostPipeline http;

  late final List<MorphPlugin> _plugins;
  var _disposed = false;

  void log(String level, String message, [Object? err, Map<String, Object?>? ctx]) {
    options.onLog?.call(level, message, err, ctx);
  }

  void dispose() {
    _disposed = true;
    for (final plugin in _plugins) {
      plugin.dispose();
    }
    tokens.dispose();
  }

  void assertAlive() {
    if (_disposed) throw StateError('MorphClient has been disposed');
  }

  // ── Config queries ────────────────────────────────────────────────────────

  HostConfig getHost(String key) {
    final h = resolved.hostByKey[key];
    if (h == null) throw UnknownHostError(key);
    return h;
  }

  ParsedAuthRef parseAuthRef(String authId) {
    final parts = authId.split('/');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      final ref = resolved.contextByAuthId[authId];
      if (ref == null) throw UnknownContextError(authId);
      return ParsedAuthContext(authId: authId, ref: ref);
    }
    if (parts.length == 1 && parts[0].isNotEmpty) {
      final pk = parts[0];
      if (!resolved.contextsByProvider.containsKey(pk)) throw UnknownContextError(authId);
      return ParsedAuthProvider(providerKey: pk);
    }
    throw UnknownContextError(authId);
  }

  bool isAuthContextReady(String authId) {
    try {
      final r = parseAuthRef(authId);
      if (r is! ParsedAuthContext) return false;
      final c = r.ref.context;
      if (c.delegateMetadata?.grantHint != 'authorization_code') return false;
      if (c.clientId == null || c.clientId!.trim().isEmpty) return false;
      if (c.clientSecret == null || c.clientSecret!.trim().isEmpty) return false;
      try {
        if (interpolateString(c.clientId!.trim(), _variables).trim().isEmpty) return false;
        if (interpolateString(c.clientSecret!.trim(), _variables).trim().isEmpty) return false;
      } catch (_) {
        return false;
      }
      final authz = c.authorization;
      if (authz == null ||
          authz.endpoint.trim().isEmpty ||
          authz.redirectUri == null ||
          authz.redirectUri!.trim().isEmpty) {
        return false;
      }
      try {
        interpolateString(authz.redirectUri!.trim(), _variables);
      } catch (_) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isProviderEnvReady(String providerKey) {
    try {
      final ctxs = resolved.contextsByProvider[providerKey] ?? const [];
      for (final c in ctxs) {
        if (c.delegateMetadata?.grantHint == 'authorization_code') {
          if (!isAuthContextReady('$providerKey/${c.key}')) return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<MorphTokenStatus>> getTokenStatus() async {
    assertAlive();
    final ids = resolved.contextByAuthId.keys.toList()..sort();
    final out = <MorphTokenStatus>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final authId in ids) {
      final ref = resolved.contextByAuthId[authId]!;
      final set = await tokens.loadTokens(authId, ref);
      final hasAccessToken = set?.accessToken.isNotEmpty ?? false;
      final exp = set?.expiresAt;
      int? jwtExp;
      Map<String, Object?>? claims;
      String? decodeError;
      int? refreshJwtExp;
      Map<String, Object?>? refreshClaims;
      String? refreshDecodeError;

      final accessFormat = ref.context.tokenTypes['access']?.format ?? 'jwt';
      final refreshFormat = ref.context.tokenTypes['refresh']?.format ?? 'jwt';

      if (set != null && set.accessToken.isNotEmpty && accessFormat == 'jwt') {
        try {
          final payload = decodeJwtPayload(set.accessToken);
          final expVal = payload['exp'];
          jwtExp = expVal is int
              ? expVal
              : expVal is num
                  ? expVal.toInt()
                  : null;
          claims = Map<String, Object?>.from(payload);
        } catch (e) {
          decodeError = e is Exception ? e.toString() : '$e';
        }
      }
      final refreshTok = set?.refreshToken;
      if (refreshTok != null &&
          refreshTok.isNotEmpty &&
          refreshFormat == 'jwt') {
        try {
          final rp = decodeJwtPayload(refreshTok);
          final rj = rp['exp'];
          refreshJwtExp = rj is int
              ? rj
              : rj is num
                  ? rj.toInt()
                  : null;
          refreshClaims = Map<String, Object?>.from(rp);
        } catch (e) {
          refreshDecodeError = e is Exception ? e.toString() : '$e';
        }
      }

      out.add(
        MorphTokenStatus(
          authId: authId,
          providerKey: ref.provider.key,
          contextKey: ref.context.key,
          grantHint: ref.context.delegateMetadata?.grantHint,
          hasAccessToken: hasAccessToken,
          hasRefreshToken: set?.refreshToken?.isNotEmpty ?? false,
          accessLikelyValid: hasAccessToken && (exp == null || exp > now),
          expiresAt: exp,
          jwtExp: jwtExp,
          claims: claims,
          decodeError: decodeError,
          refreshClaims: refreshClaims,
          refreshJwtExp: refreshJwtExp,
          refreshDecodeError: refreshDecodeError,
        ),
      );
    }
    return out;
  }

  MorphProviderMeta getProviderMeta(String providerKey) {
    assertAlive();
    ProviderConfig? p;
    for (final x in resolved.config.providers) {
      if (x.key == providerKey) {
        p = x;
        break;
      }
    }
    if (p == null) throw UnknownProviderError(providerKey);
    final contexts = <MorphContextMeta>[];
    for (final c in p.contexts) {
      contexts.add(MorphContextMeta(
        key: c.key,
        authId: '${p.key}/${c.key}',
        clientId: c.clientId,
        clientAuth: c.clientAuth,
        audience: c.audience,
        identity: c.identity,
        authorization: c.authorization,
        token: c.token,
        logout: c.logout,
        scopes: c.scopes,
        pkce: c.pkce,
        refreshPolicy: c.refreshPolicy,
        recoveryPolicy: c.recoveryPolicy,
        delegateMetadata: c.delegateMetadata,
        sessionPolicy: c.sessionPolicy,
        networkPolicy: c.networkPolicy,
        headers: c.headers,
        tokenTypes: c.tokenTypes,
      ));
    }
    return MorphProviderMeta(
      key: p.key,
      type: p.type,
      baseUrl: p.baseUrl,
      authorizationBrowserBaseUrl: p.authorizationBrowserBaseUrl,
      tokenHttpBaseUrl: p.tokenHttpBaseUrl,
      networkPolicy: p.networkPolicy,
      headers: p.headers,
      contexts: contexts,
    );
  }

  List<String> getExchangeTargets(String sourceAuthId) {
    assertAlive();
    final parsed = parseAuthRef(sourceAuthId);
    if (parsed is! ParsedAuthContext) {
      throw StateError('getExchangeTargets($sourceAuthId): expected provider/context');
    }
    final targets = <String>[];
    for (final e in resolved.contextByAuthId.entries) {
      final ctx = e.value.context;
      if (normalizeExchangeSourcesFromTokenBlock(ctx.token).contains(sourceAuthId)) {
        targets.add(e.key);
      }
    }
    targets.sort();
    return targets;
  }

  List<String> getExchangeSources(String targetAuthId) {
    assertAlive();
    final parsed = parseAuthRef(targetAuthId);
    if (parsed is! ParsedAuthContext) {
      throw StateError('getExchangeSources($targetAuthId): expected provider/context');
    }
    return normalizeExchangeSourcesFromTokenBlock(parsed.ref.context.token);
  }

  String getAuthorizationUrl(String authId, {String? state}) {
    assertAlive();
    if (!isAuthContextReady(authId)) {
      throw StateError('$authId: not ready for authorize');
    }
    final r = parseAuthRef(authId);
    if (r is! ParsedAuthContext) throw UnknownContextError(authId);
    final p = r.ref.provider;
    final c = r.ref.context;
    final authz = c.authorization!;
    final redirectUri = interpolateString(authz.redirectUri!.trim(), _variables);
    final clientId = interpolateString(c.clientId!.trim(), _variables);
    final st = state ?? encodeOAuthState(authId);
    final browserBaseRaw = p.authorizationBrowserBaseUrl?.trim();
    final authorizeBase = browserBaseRaw != null && browserBaseRaw.isNotEmpty
        ? interpolateString(browserBaseRaw, _variables)
        : interpolateString(p.baseUrl.trim(), _variables);
    return buildOAuth2AuthorizationUrl(
      baseUrl: authorizeBase,
      authorizationPath: interpolateString(authz.endpoint.trim(), _variables),
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: c.scopes,
      responseType: authz.responseType,
      extraParams: authz.extraParams,
      state: st,
    );
  }

  Future<OAuthReturnResult> completeOAuthCallback({
    String? code,
    String? state,
    String? error,
    String? errorDescription,
  }) async {
    assertAlive();
    if (error != null) {
      final msg = errorDescription != null ? ' — $errorDescription' : '';
      return OAuthReturnResult(status: 'oauth_error', message: 'OAuth error: $error$msg');
    }
    if (code == null || code.isEmpty) {
      return const OAuthReturnResult(status: 'none');
    }

    final decoded = state != null ? decodeOAuthState(state) : null;
    if (decoded != null) {
      final ref = resolved.contextByAuthId[decoded.authId];
      if (ref == null) {
        return OAuthReturnResult(
          status: 'error',
          message: 'Unknown auth id from state: ${decoded.authId}',
        );
      }
      try {
        await tokens.submitCode(decoded.authId, ref, code);
        return OAuthReturnResult(status: 'success', message: 'Signed in (${decoded.authId}).');
      } catch (e) {
        return OAuthReturnResult(status: 'error', message: e is Exception ? e.toString() : '$e');
      }
    }

    final rootId = resolved.config.rootCallbackAuthId?.trim();
    if (rootId == null || rootId.isEmpty) {
      return const OAuthReturnResult(
        status: 'error',
        message: 'Missing or invalid OAuth state and no rootCallbackAuthId configured.',
      );
    }
    final ref = resolved.contextByAuthId[rootId];
    if (ref == null) {
      return OAuthReturnResult(status: 'error', message: 'Unknown rootCallbackAuthId: $rootId');
    }
    final redirectOverride = _resolvedRootOAuthRedirectUriOverride();
    try {
      await tokens.submitCode(
        rootId,
        ref,
        code,
        redirectUriOverride: redirectOverride,
      );
      return const OAuthReturnResult(
        status: 'success',
        message: 'Authorization code exchanged.',
      );
    } catch (e) {
      return OAuthReturnResult(status: 'error', message: e is Exception ? e.toString() : '$e');
    }
  }

  String _resolvedRootOAuthRedirectUriOverride() {
    final raw = options.oauthRedirectBase?.trim();
    if (raw != null && raw.isNotEmpty) {
      final withScheme = raw.contains('://') ? raw : 'https://$raw';
      final u = Uri.tryParse(withScheme);
      if (u != null && (u.scheme == 'http' || u.scheme == 'https')) {
        return '${u.origin}/';
      }
    }
    return '${Uri.base.origin}/';
  }

  /// Browser-oriented when compiled with dart:html, or pass [currentUri] on any platform.
  /// If the URI path is non-root (`/` or empty), returns `{ status: none }`.
  Future<OAuthReturnResult> completeOAuthReturn({Uri? currentUri}) async {
    assertAlive();
    final loc = currentUri ?? oauthReturnReadLocationUri();
    if (loc == null) return const OAuthReturnResult(status: 'none');
    final path = loc.path;
    if (path.isNotEmpty && path != '/') return const OAuthReturnResult(status: 'none');
    final qp = loc.queryParameters;
    final result = await completeOAuthCallback(
      code: qp['code'],
      state: qp['state'],
      error: qp['error'],
      errorDescription: qp['error_description'],
    );
    if (result.status != 'none') oauthReturnReplaceLocationHref(loc.toString());
    return result;
  }

  Future<OAuthReturnResult> completeAuthorizationReturnFromUrl({Uri? currentUri}) =>
      completeOAuthReturn(currentUri: currentUri);
}

MorphRuntime createMorphRuntime(
  ResolvedMorphConfig resolved,
  MorphOptions options, [
  Map<String, String>? variables,
]) =>
    MorphRuntime(
      resolved,
      options,
      variables ?? options.variables ?? const {},
    );
