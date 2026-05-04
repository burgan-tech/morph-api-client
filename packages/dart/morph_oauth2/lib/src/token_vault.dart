import 'dart:convert';

import 'package:morph_core/morph_core.dart';

/// Path manifest JSON stored beside token blobs (`packages/ts/oauth2/src/tokens/tokenVault.ts`).
final class PathManifest {
  PathManifest({required this.accessKey, this.refreshKey});
  factory PathManifest.fromJson(Map<String, dynamic> m) =>
      PathManifest(accessKey: m['accessKey'] as String, refreshKey: m['refreshKey'] as String?);

  final String accessKey;
  final String? refreshKey;

  Map<String, dynamic> toJson() => {
        'accessKey': accessKey,
        if (refreshKey != null) 'refreshKey': refreshKey,
      };
}

StorageConfig _manifestCfg(StorageConfig accessStorage, String authId) {
  return StorageConfig(
    scope: accessStorage.scope,
    type: accessStorage.type,
    protection: accessStorage.protection,
    key: 'morph:paths:${authId.replaceAll('/', '.')}',
  );
}

final class TokenVault {
  TokenVault(this._variables, StorageProvider transport) : _storage = transport;

  final Map<String, String> _variables;
  final StorageProvider _storage;

  StorageConfig _tokCfg(AuthContextConfig ctx, String kind) {
    final tt = ctx.tokenTypes[kind];
    if (tt == null) throw StateError('Missing tokenTypes.$kind for context ${ctx.key}');
    return tt.storage;
  }

  Future<PathManifest?> _readManifest(String authId, AuthContextConfig ctx) async {
    final acc = _tokCfg(ctx, 'access');
    final cfg = _manifestCfg(acc, authId);
    final raw = await _storage.read(cfg.key, cfg);
    if (raw == null) return null;
    try {
      return PathManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeManifest(String authId, AuthContextConfig ctx, PathManifest m) async {
    final acc = _tokCfg(ctx, 'access');
    final cfg = _manifestCfg(acc, authId);
    await _storage.write(cfg.key, jsonEncode(m.toJson()), cfg);
  }

  Future<void> _deleteManifest(String authId, AuthContextConfig ctx) async {
    final acc = _tokCfg(ctx, 'access');
    final cfg = _manifestCfg(acc, authId);
    await _storage.delete(cfg.key, cfg);
  }

  Map<String, String> _extrasForKeys(AuthContextConfig ctx, [String? accessToken]) {
    final subClaim = ctx.identity?.subject ?? 'sub';
    final actClaim = ctx.identity?.actor ?? 'act';
    final subject =
        accessToken != null ? (getJwtSubject(accessToken, subClaim) ?? 'unknown') : 'unknown';
    final actor =
        accessToken != null ? (getJwtSubject(accessToken, actClaim) ?? subject) : subject;
    return {'key': ctx.key, 'subject': subject, 'actor': actor};
  }

  Future<TokenSet?> load(
    String authId,
    ProviderConfig provider,
    AuthContextConfig ctx,
  ) async {
    final manifest = await _readManifest(authId, ctx);
    if (manifest == null) return null;
    final accCfg =
        StorageConfig(scope: _tokCfg(ctx, 'access').scope, type: _tokCfg(ctx, 'access').type, protection: _tokCfg(ctx, 'access').protection, key: manifest.accessKey);
    final rawAccess = await _storage.read(manifest.accessKey, accCfg);
    if (rawAccess == null) return null;
    String? refreshToken;
    if (manifest.refreshKey != null && ctx.tokenTypes.containsKey('refresh')) {
      final refCfg =
          StorageConfig(scope: _tokCfg(ctx, 'refresh').scope, type: _tokCfg(ctx, 'refresh').type, protection: _tokCfg(ctx, 'refresh').protection, key: manifest.refreshKey!);
      refreshToken = await _storage.read(manifest.refreshKey!, refCfg);
    }
    try {
      final map = jsonDecode(rawAccess);
      if (map is! Map) return null;
      final mj = Map<String, dynamic>.from(map.cast<dynamic, dynamic>());
      if (refreshToken != null) mj['refreshToken'] = refreshToken;
      return TokenSet.fromJson(mj);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String authId, ProviderConfig provider, AuthContextConfig ctx, TokenSet tokens) async {
    final extras = _extrasForKeys(ctx, tokens.accessToken);
    final accessTemplate = ctx.tokenTypes['access']!.storage.key;
    final accessKey = interpolateString(accessTemplate, _variables, extras);

    String? refreshKey;
    if (tokens.refreshToken != null && ctx.tokenTypes.containsKey('refresh')) {
      final rt = ctx.tokenTypes['refresh']!.storage.key;
      refreshKey = interpolateString(rt, _variables, extras);
    }

    final accessCfgFull = StorageConfig(
      scope: _tokCfg(ctx, 'access').scope,
      type: _tokCfg(ctx, 'access').type,
      protection: _tokCfg(ctx, 'access').protection,
      key: accessKey,
    );

    await _storage.write(
      accessKey,
      jsonEncode(
        TokenSet(
          accessToken: tokens.accessToken,
          expiresAt: tokens.expiresAt,
          metadata: tokens.metadata,
        ).toJson(),
      ),
      accessCfgFull,
    );

    if (refreshKey != null && tokens.refreshToken != null && ctx.tokenTypes.containsKey('refresh')) {
      final refCfg = StorageConfig(
        scope: _tokCfg(ctx, 'refresh').scope,
        type: _tokCfg(ctx, 'refresh').type,
        protection: _tokCfg(ctx, 'refresh').protection,
        key: refreshKey,
      );
      await _storage.write(refreshKey, tokens.refreshToken!, refCfg);
    }

    await _writeManifest(
      authId,
      ctx,
      PathManifest(accessKey: accessKey, refreshKey: refreshKey),
    );
  }

  Future<void> clear(String authId, ProviderConfig provider, AuthContextConfig ctx) async {
    final manifest = await _readManifest(authId, ctx);
    if (manifest != null) {
      final accDel = StorageConfig(
        scope: _tokCfg(ctx, 'access').scope,
        type: _tokCfg(ctx, 'access').type,
        protection: _tokCfg(ctx, 'access').protection,
        key: manifest.accessKey,
      );
      await _storage.delete(manifest.accessKey, accDel);
      if (manifest.refreshKey != null && ctx.tokenTypes.containsKey('refresh')) {
        final refDel = StorageConfig(
          scope: _tokCfg(ctx, 'refresh').scope,
          type: _tokCfg(ctx, 'refresh').type,
          protection: _tokCfg(ctx, 'refresh').protection,
          key: manifest.refreshKey!,
        );
        await _storage.delete(manifest.refreshKey!, refDel);
      }
    }
    await _deleteManifest(authId, ctx);
  }
}
