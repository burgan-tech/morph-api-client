import '../config/list_auth_ids.dart';
import '../runtime/morph_runtime.dart';
import '../types/morph_surface.dart';
import '../util/jwt_utils.dart';

/// Parity: [`AuthHandle`](packages/ts/core/src/client/AuthHandle.ts).
final class AuthHandle {
  AuthHandle(this._rt, this.authId);

  final MorphRuntime _rt;
  final String authId;

  Future<void> submitCode(String code, {String? codeVerifier, String? redirectUriOverride}) async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('submitCode requires a provider/context auth id');
    }
    _rt.assertAlive();
    await _rt.tokens.submitCode(r.authId, r.ref, code,
        codeVerifier: codeVerifier, redirectUriOverride: redirectUriOverride);
  }

  Future<void> acquireWithClientCredentials() async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('acquireWithClientCredentials requires a provider/context auth id');
    }
    _rt.assertAlive();
    await _rt.tokens.acquireWithClientCredentials(r.authId, r.ref);
  }

  Future<void> exchangeToken(String targetAuthId) async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('exchangeToken requires a provider/context auth id as the source');
    }
    _rt.assertAlive();
    await _rt.tokens.exchangeToken(r.authId, r.ref, targetAuthId);
  }

  Future<void> setTokens(TokenSet tokens) async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('setTokens requires a provider/context auth id');
    }
    _rt.assertAlive();
    await _rt.tokens.setTokens(r.authId, r.ref, tokens);
  }

  Future<void> clearTokens() async {
    final r = _rt.parseAuthRef(authId);
    _rt.assertAlive();
    if (r is ParsedAuthContext) {
      await _rt.tokens.clearTokens(r.authId, r.ref);
      return;
    }
    final pk = r is ParsedAuthProvider ? r.providerKey : '';
    for (final id in listAuthIdsForProvider(pk, _rt.resolved)) {
      final ref = _rt.resolved.contextByAuthId[id];
      if (ref != null) await _rt.tokens.clearTokens(id, ref);
    }
  }

  Future<void> logout([String reason = 'user_initiated']) async {
    final r = _rt.parseAuthRef(authId);
    _rt.assertAlive();
    if (r is ParsedAuthContext) {
      await _rt.tokens.logout(r.authId, r.ref, reason);
      return;
    }
    if (r is ParsedAuthProvider) {
      await _rt.tokens.logoutProvider(r.providerKey, reason);
    }
  }

  Future<bool> hasValidToken() async {
    final r = _rt.parseAuthRef(authId);
    _rt.assertAlive();
    if (r is ParsedAuthContext) {
      return _rt.tokens.hasValidTokenContext(r.authId, r.ref);
    }
    if (r is ParsedAuthProvider) {
      return _rt.tokens.hasValidTokenProvider(r.providerKey);
    }
    return false;
  }

  Future<void> refreshTokens() async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('refreshTokens requires a provider/context auth id');
    }
    _rt.assertAlive();
    await _rt.tokens.refreshTokensManual(r.authId, r.ref);
  }

  Future<TokenSet?> peekTokens() async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('peekTokens requires a provider/context auth id');
    }
    _rt.assertAlive();
    return _rt.tokens.loadTokens(r.authId, r.ref);
  }

  /// Decoded access token JWT claims, or null when no token / opaque token. No network, no refresh.
  Future<JwtPayload?> getClaims() async {
    final r = _rt.parseAuthRef(authId);
    if (r is! ParsedAuthContext) {
      throw StateError('getClaims requires a provider/context auth id');
    }
    _rt.assertAlive();
    if ((r.ref.context.tokenTypes['access']?.format ?? 'jwt') == 'opaque') {
      return null;
    }
    final set = await _rt.tokens.loadTokens(r.authId, r.ref);
    if (set?.accessToken == null || set!.accessToken.isEmpty) return null;
    try {
      return decodeJwtPayload(set.accessToken);
    } catch (_) {
      return null;
    }
  }
}
