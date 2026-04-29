import 'package:morph_core/morph_core.dart';

import 'oauth_callbacks.dart';
import 'token_http.dart' as th;
import 'token_vault.dart';

/// Parity: `OAuth2TokenOptions` (TS).
final class OAuth2TokenOptions {
  OAuth2TokenOptions({
    required this.callbacks,
    required this.variables,
    this.onTokenExchange,
    this.onClientJwtAssertion,
    this.autoAcquireNonInteractive,
    this.onLog,
  });

  final MorphOAuthCallbacks callbacks;
  final Map<String, String> variables;
  final Future<TokenSet?> Function(TokenExchangeGrant grant)? onTokenExchange;
  final Future<String?> Function(String authId)? onClientJwtAssertion;
  final bool? autoAcquireNonInteractive;
  final MorphLogFn? onLog;
}

const _grantTokenExchange =
    'urn:ietf:params:oauth:grant-type:token-exchange';
const _accessTokenSubjectType = 'urn:ietf:params:oauth:token-type:access_token';

/// Implements [`AuthPlugin`] — parity `packages/oauth2/src/tokens/tokenLifecycle.ts`.
final class TokenLifecycle implements AuthPlugin {
  TokenLifecycle(
    this.resolved,
    this.opts,
    Map<String, String> variablesIn,
    this.log,
    StorageProvider storage,
  ) : variables = {...variablesIn},
      vault = TokenVault(variablesIn, storage);

  final ResolvedMorphConfig resolved;
  final OAuth2TokenOptions opts;
  final Map<String, String> variables;
  final MorphLogFn? log;
  final TokenVault vault;

  final Map<String, Future<dynamic>> _locks = {};
  final Map<String, Future<void>> _inflightSubmit = {};

  @override
  void dispose() {
    _locks.clear();
    _inflightSubmit.clear();
  }

  void _doLog(String level, String msg, [Object? err, Map<String, Object?>? ctx]) {
    log?.call(level, msg, err, ctx);
  }

  Future<T> _withLock<T>(String authId, Future<T> Function() fn) {
    final prev = _locks[authId] ?? Future<void>.value();
    late final Future<T> next;
    next = prev.then((_) => fn());
    _locks[authId] = next.then<dynamic>((_) => Future<void>.value(), onError: (_) => Future<void>.value());
    return next;
  }

  NetworkPolicy? _policy(ProviderConfig p, AuthContextConfig ctx) =>
      ctx.networkPolicy ?? p.networkPolicy;

  String _tokenHttpBase(ProviderConfig p) {
    final raw = p.tokenHttpBaseUrl?.trim();
    if (raw != null && raw.isNotEmpty) {
      final r = interpolateString(raw, variables).trim();
      if (r.isNotEmpty) return r;
    }
    return interpolateString(p.baseUrl.trim(), variables);
  }

  TokenSet _oauthToSet(AuthContextConfig ctx, th.OAuthTokenResponse r,
      [String? preserveRefresh]) {
    final tt = ctx.tokenTypes['access']!;
    final exp = computeExpiresAt(r.accessToken, r.expiresIn, tt.maxTtl);
    return TokenSet(
      accessToken: r.accessToken,
      refreshToken: r.refreshToken ?? preserveRefresh,
      expiresAt: exp,
    );
  }

  Future<void> _persist(String authId, CtxRef ref, TokenSet? set) async {
    if (set != null) {
      await vault.save(authId, ref.provider, ref.context, set);
    } else {
      await vault.clear(authId, ref.provider, ref.context);
    }
    opts.callbacks.onTokenChange?.call(authId, set);
  }

  Future<TokenSet> _executeGrant(
    String authId,
    CtxRef ref,
    String grantType,
    Map<String, String> extras,
    TokenExchangeGrant info, [
    String? preserveRefresh,
  ]) async {
    final provider = ref.provider;
    final ctx = ref.context;
    final useExchange = grantType == _grantTokenExchange && ctx.token.exchangeEndpoint != null;
    final url = th.tokenEndpointUrl(_tokenHttpBase(provider), ctx, useExchange, variables);
    final clientFields = await th.buildClientAuthFields(
      authId: authId,
      ctx: ctx,
      variables: variables,
      onClientJwtAssertion: opts.onClientJwtAssertion,
    );
    final hdr = th.mergeTokenHeaders(provider, ctx, variables);
    final body = <String, String>{...clientFields, 'grant_type': grantType, ...extras};
    if (grantType != 'authorization_code' && ctx.audience != null) {
      body['audience'] = interpolateString(ctx.audience!, variables, {'key': ctx.key});
    }
    if (ctx.scopes != null && ctx.scopes!.isNotEmpty) {
      body['scope'] = ctx.scopes!.join(' ');
    }

    final custom = await opts.onTokenExchange?.call(info);
    if (custom != null) return custom;

    final r = await th.postTokenRequest(url, body, hdr, _policy(provider, ctx), opts.onLog ?? log);
    return _oauthToSet(ctx, r, preserveRefresh);
  }

  Future<TokenSet> _executeRefresh(
      String aid, CtxRef ref, String rt) {
    final preserve =
        ref.context.refreshPolicy?.strategy == 'static' ? rt : null;
    return _executeGrant(aid, ref, 'refresh_token', {'refresh_token': rt},
        TokenExchangeGrant(type: 'refresh_token', authId: aid, refreshToken: rt),
        preserve);
  }

  Future<TokenSet> _fetchClientCred(String aid, CtxRef ref) =>
      _executeGrant(aid, ref, 'client_credentials', {},
          TokenExchangeGrant(type: 'client_credentials', authId: aid));

  Future<TokenSet> _runTokenExchange(String srcAid, String tgtAid,
      CtxRef targetRef, String subject) {
    return _executeGrant(tgtAid, targetRef, _grantTokenExchange, {
      'subject_token': subject,
      'subject_token_type': _accessTokenSubjectType,
    }, TokenExchangeGrant(
      type: 'token_exchange',
      authId: tgtAid,
      sourceAuthId: srcAid,
      sourceToken: subject,
    ));
  }

  @override
  Future<TokenSet?> loadTokens(String aid, CtxRef ref) =>
      vault.load(aid, ref.provider, ref.context);

  @override
  Future<void> submitCode(String aid, CtxRef ref, String code,
      {String? codeVerifier, String? redirectUriOverride}) async {
    final key = '$aid:$code';
    final existing = _inflightSubmit[key];
    if (existing != null) return existing;
    final done = () async {
      await _withLock(aid, () async {
        final ctx = ref.context;
        final red = ctx.authorization?.redirectUri;
        if (red == null || red.isEmpty) {
          throw StateError('authorization.redirectUri is required for submitCode');
        }
        final redirectUri = redirectUriOverride != null &&
                redirectUriOverride.trim().isNotEmpty
            ? redirectUriOverride.trim()
            : interpolateString(red, variables, {'key': ctx.key});
        final extras = <String, String>{
          'code': code,
          'redirect_uri': redirectUri,
        };
        if (codeVerifier != null) extras['code_verifier'] = codeVerifier;
        final set = await _executeGrant(aid, ref, 'authorization_code', extras, TokenExchangeGrant(
          type: 'authorization_code',
          authId: aid,
          code: code,
          codeVerifier: codeVerifier,
        ));
        await _persist(aid, ref, set);
        _doLog('info', 'Tokens stored (authorization_code)', null, {'authId': aid});
      });
    }().whenComplete(() => _inflightSubmit.remove(key));
    _inflightSubmit[key] = done;
    return done;
  }

  @override
  Future<void> acquireWithClientCredentials(String aid, CtxRef ref) =>
      _withLock(aid, () async {
        final set = await _fetchClientCred(aid, ref);
        await _persist(aid, ref, set);
        _doLog('info', 'Client credentials token stored', null, {'authId': aid});
      });

  @override
  Future<void> exchangeToken(String srcAid, CtxRef srcRef, String tgtAid) {
    final target = resolved.contextByAuthId[tgtAid];
    if (target == null) throw UnknownContextError(tgtAid);
    return _withLock(tgtAid, () async {
      final access = await resolveAccessToken(srcAid, srcRef, 'http');
      final nt = await _runTokenExchange(srcAid, tgtAid, target, access);
      await _persist(tgtAid, target, nt);
      _doLog(
          'info', 'Token exchange completed', null, {'sourceAuthId': srcAid, 'targetAuthId': tgtAid});
    });
  }

  @override
  Future<void> setTokens(String aid, CtxRef ref, TokenSet tokens) =>
      _withLock(aid, () async {
        var exp = tokens.expiresAt;
        exp ??=
            computeExpiresAt(tokens.accessToken, null, ref.context.tokenTypes['access']!.maxTtl);
        await _persist(aid, ref, TokenSet(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, expiresAt: exp, metadata: tokens.metadata));
      });

  @override
  Future<void> clearTokens(String aid, CtxRef ref) => _withLock(aid, () async {
        await vault.clear(aid, ref.provider, ref.context);
        opts.callbacks.onTokenChange?.call(aid, null);
      });

  @override
  Future<void> logout(String aid, CtxRef ref, String reason) async {
    final set = await loadTokens(aid, ref);
    final p = ref.provider;
    final ctx = ref.context;
    final ep = ctx.logout?.endpoint;
    if (ep != null && ep.isNotEmpty) {
      try {
        final url = resolveEndpoint(_tokenHttpBase(p), ep);
        final clientFields = await th.buildClientAuthFields(
          authId: aid,
          ctx: ctx,
          variables: variables,
          onClientJwtAssertion: opts.onClientJwtAssertion,
        );
        final hdr = th.mergeTokenHeaders(p, ctx, variables);
        final body = <String, String>{...clientFields};
        if (set?.refreshToken != null) body['refresh_token'] = set!.refreshToken!;
        await th.postTokenRequest(url, body, hdr, _policy(p, ctx), opts.onLog ?? log);
      } catch (e) {
        _doLog('warn', 'Logout endpoint failed', e, {'authId': aid});
      }
    }
    await clearTokens(aid, ref);
    opts.callbacks.onLogout?.call(aid, reason);
  }

  @override
  Future<void> logoutProvider(String providerKey, String reason) async {
    final ids = listAuthIdsForProvider(providerKey, resolved);
    for (final id in ids) {
      final r = resolved.contextByAuthId[id]!;
      await logout(id, r, reason);
    }
  }

  @override
  Future<bool> hasValidTokenContext(String aid, CtxRef ref) async {
    try {
      await resolveAccessToken(aid, ref, 'probe');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasValidTokenProvider(String pk) async {
    final ids = listAuthIdsForProvider(pk, resolved);
    for (final id in ids) {
      final r = resolved.contextByAuthId[id];
      if (r != null && await hasValidTokenContext(id, r)) return true;
    }
    return false;
  }

  @override
  void fireAuthRequired(String aid, AuthContextConfig ctx) {
    DelegateMetadata md;
    if (ctx.delegateMetadata != null) {
      md = ctx.delegateMetadata!;
    } else {
      md = DelegateMetadata(workflow: 'unknown', grantHint: 'unknown', interaction: 'interactive');
    }
    opts.callbacks.onAuthRequired(aid, md);
    if (opts.autoAcquireNonInteractive == true && md.interaction == 'non-interactive') {
      final ref = resolved.contextByAuthId[aid];
      if (ref != null) {
        acquireWithClientCredentials(aid, ref).catchError((Object e, StackTrace _) {
          _doLog('warn', 'autoAcquireNonInteractive failed', e, {'authId': aid});
        });
      }
    }
  }

  void _emitRefreshFailCallbacks(CtxRef ref, String aid, String mode) {
    if (mode != 'http') return;
    if (ref.context.recoveryPolicy?.onRefreshFail == 'delegate') {
      fireAuthRequired(aid, ref.context);
    }
    opts.callbacks.onLogout?.call(aid, 'refresh_failed');
  }

  @override
  Future<void> handle401Recovery(String aid, CtxRef ref) =>
      _withLock(aid, () async {
        final set = await loadTokens(aid, ref);
        if (set?.refreshToken != null && set!.refreshToken!.isNotEmpty) {
          try {
            final nw = await _executeRefresh(aid, ref, set.refreshToken!);
            await _persist(aid, ref, nw);
            _doLog('info', 'Access token refreshed after 401', null, {'authId': aid});
          } catch (_) {
            await vault.clear(aid, ref.provider, ref.context);
            opts.callbacks.onTokenChange?.call(aid, null);
            _emitRefreshFailCallbacks(ref, aid, 'http');
          }
        } else {
          fireAuthRequired(aid, ref.context);
        }
      });

  @override
  Future<String> resolveAccessToken(String aid, CtxRef ref, String mode) =>
      _withLock<String>(aid, () => _resolveAccessInner(aid, ref, mode));

  Future<String> _resolveAccessInner(String aid, CtxRef ref, String mode) async {
    var set = await loadTokens(aid, ref);
    const skew = 30;
    var refreshBefore = skew;
    final rbp = ref.context.refreshPolicy?.refreshBeforeExpiry;
    if (rbp != null) {
      refreshBefore = (parseDurationMs(rbp) / 1000).ceil().clamp(1, 86400);
    }
    if (rbp == null && set?.expiresAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final ttlSec = set!.expiresAt! - now;
      if (ttlSec > 0 && ttlSec < refreshBefore) {
        refreshBefore = (ttlSec - 5).clamp(1, refreshBefore);
      }
    }

    if (set != null && !isExpired(set.expiresAt, refreshBefore)) {
      return set.accessToken;
    }

    var recoveryEmitted = false;
    var deferredRefreshFail = false;

    if (set?.refreshToken != null && set!.refreshToken!.isNotEmpty) {
      try {
        final newSet = await _executeRefresh(aid, ref, set.refreshToken!);
        await _persist(aid, ref, newSet);
        _doLog('info', 'Access token refreshed', null, {'authId': aid});
        return newSet.accessToken;
      } catch (e) {
        _doLog('warn', 'Refresh failed', e, {'authId': aid});
        await vault.clear(aid, ref.provider, ref.context);
        opts.callbacks.onTokenChange?.call(aid, null);
        set = null;
        deferredRefreshFail = hasExchangeSourcesFromTokenBlock(ref.context.token);
        if (!deferredRefreshFail) {
          _emitRefreshFailCallbacks(ref, aid, mode);
          recoveryEmitted = true;
        }
      }
    }

    if (set != null &&
        isExpired(set.expiresAt, refreshBefore) &&
        (set.refreshToken == null || set.refreshToken!.isEmpty) &&
        ref.context.delegateMetadata?.grantHint == 'client_credentials') {
      try {
        final newSet = await _fetchClientCred(aid, ref);
        await _persist(aid, ref, newSet);
        _doLog('info', 'Access token renewed (client_credentials)', null, {'authId': aid});
        return newSet.accessToken;
      } catch (e) {
        _doLog('warn', 'Client credentials re-acquire failed', e, {'authId': aid});
      }
    }

    final exSrcs = normalizeExchangeSourcesFromTokenBlock(ref.context.token);
    if (exSrcs.isNotEmpty) {
      var exchanged = false;
      for (final exSrc in exSrcs) {
        try {
          final srcRef = resolved.contextByAuthId[exSrc];
          if (srcRef == null) throw StateError('Invalid exchangeSource $exSrc');
          final srcToken = await resolveAccessToken(exSrc, srcRef, mode);
          final newSet = await _runTokenExchange(exSrc, aid, ref, srcToken);
          await _persist(aid, ref, newSet);
          _doLog('info', 'Access token issued (token_exchange)', null, {'authId': aid, 'exchangeSource': exSrc});
          deferredRefreshFail = false;
          exchanged = true;
          return newSet.accessToken;
        } catch (e) {
          _doLog('warn', 'Auto token exchange failed', e, {'authId': aid, 'exSrc': exSrc});
        }
      }
      if (!exchanged && deferredRefreshFail) {
        _emitRefreshFailCallbacks(ref, aid, mode);
        recoveryEmitted = true;
      }
    }

    if (mode == 'http' && ref.context.recoveryPolicy?.onRefreshFail == 'delegate') {
      if (!recoveryEmitted) fireAuthRequired(aid, ref.context);
      throw AuthError(aid, 'delegation_required');
    }

    throw AuthError(aid, set != null ? 'refresh_failed' : 'no_token');
  }

  @override
  Future<void> refreshTokensManual(String aid, CtxRef ref) => _withLock(aid, () async {
        final set = await loadTokens(aid, ref);
        if (set?.refreshToken != null && set!.refreshToken!.isNotEmpty) {
          try {
            final newSet = await _executeRefresh(aid, ref, set.refreshToken!);
            await _persist(aid, ref, newSet);
            _doLog('info', 'Access token refreshed (manual)', null, {'authId': aid});
            return;
          } catch (e) {
            final exSrcs = normalizeExchangeSourcesFromTokenBlock(ref.context.token);
            for (final exSrc in exSrcs) {
              try {
                final srcRef = resolved.contextByAuthId[exSrc];
                if (srcRef == null) throw StateError('Invalid exchangeSource $exSrc');
                final srcToken = await resolveAccessToken(exSrc, srcRef, 'http');
                final newSet = await _runTokenExchange(exSrc, aid, ref, srcToken);
                await _persist(aid, ref, newSet);
                _doLog(
                    'info', 'Access token issued (manual: exchange after refresh fail)', null, {'authId': aid});
                return;
              } catch (_) {}
            }
            await vault.clear(aid, ref.provider, ref.context);
            opts.callbacks.onTokenChange?.call(aid, null);
            _emitRefreshFailCallbacks(ref, aid, 'http');
            rethrow;
          }
        }
        if (ref.context.delegateMetadata?.grantHint == 'client_credentials') {
          final newSet = await _fetchClientCred(aid, ref);
          await _persist(aid, ref, newSet);
          _doLog('info', 'Access token renewed (client_credentials, manual)', null, {'authId': aid});
          return;
        }
        throw StateError('$aid: no refresh token; use login or token exchange');
      });
}

