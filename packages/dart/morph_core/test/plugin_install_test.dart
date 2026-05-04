import 'package:morph_core/morph_core.dart';
import 'package:test/test.dart';

import 'minimal_morph_config.dart';

final class _MemStorage implements StorageProvider {
  final Map<String, String> _m = {};
  String _k(String key, StorageConfig c) => '${c.scope}:${c.type}:${c.protection}:${c.key}:$key';

  @override
  Future<void> delete(String key, StorageConfig storageConfig) async => _m.remove(_k(key, storageConfig));

  @override
  Future<void> deleteByPrefix(String prefix, StorageConfig storageConfig) async {
    final p = _k(prefix, storageConfig);
    _m.removeWhere((k, _) => k.startsWith(p));
  }

  @override
  Future<String?> read(String key, StorageConfig storageConfig) async => _m[_k(key, storageConfig)];

  @override
  Future<void> write(String key, String value, StorageConfig storageConfig) async {
    _m[_k(key, storageConfig)] = value;
  }
}

final class _StubAuth implements AuthPlugin {
  @override
  void dispose() {}

  @override
  Future<void> acquireWithClientCredentials(String authId, CtxRef ref) async {}

  @override
  Future<void> clearTokens(String authId, CtxRef ref) async {}

  @override
  Future<void> exchangeToken(String sourceAuthId, CtxRef sourceRef, String targetAuthId) async {}

  @override
  void fireAuthRequired(String authId, AuthContextConfig ctx) {}

  @override
  Future<bool> hasValidTokenContext(String authId, CtxRef ref) async => false;

  @override
  Future<bool> hasValidTokenProvider(String providerKey) async => false;

  @override
  Future<void> handle401Recovery(String authId, CtxRef ref) async {}

  @override
  Future<TokenSet?> loadTokens(String authId, CtxRef ref) async => null;

  @override
  Future<void> logout(String authId, CtxRef ref, String reason) async {}

  @override
  Future<void> logoutProvider(String providerKey, String reason) async {}

  @override
  Future<void> refreshTokensManual(String authId, CtxRef ref) async {}

  @override
  Future<String> resolveAccessToken(String authId, CtxRef ref, String mode) async => '';

  @override
  Future<void> setTokens(String authId, CtxRef ref, TokenSet tokens) async {}

  @override
  Future<void> submitCode(String authId, CtxRef ref, String code,
          {String? codeVerifier, String? redirectUriOverride}) async {}
}

final class _StoragePlugin implements MorphPlugin {
  @override
  String get name => 'test-storage';

  @override
  List<String>? get provides => const ['storage'];

  @override
  List<String>? get requires => null;

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {
    ctx.provideStorage(_MemStorage());
  }
}

final class _AuthPlugin implements MorphPlugin {
  @override
  String get name => 'test-auth';

  @override
  List<String>? get provides => const ['auth'];

  @override
  List<String>? get requires => const ['storage'];

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {
    ctx.provideAuth(_StubAuth());
  }
}

void main() {
  group('topoSortPlugins', () {
    test('orders dependency before dependent', () {
      final storage = _StoragePlugin();
      final auth = _AuthPlugin();
      final sorted = topoSortPlugins([auth, storage]);
      expect(sorted.first.name, 'test-storage');
      expect(sorted[1].name, 'test-auth');
    });

    test('throws on circular requires', () {
      final a = _CycleA();
      final b = _CycleB();
      expect(
        () => topoSortPlugins([a, b]),
        throwsA(predicate<StateError>((e) => e.message.contains('Circular'))),
      );
    });

    test('throws when requirement has no provider', () {
      final orphan = _AuthPlugin();
      expect(
        () => topoSortPlugins([orphan]),
        throwsA(predicate<StateError>((e) => e.message.contains('no plugin provides'))),
      );
    });
  });

  group('installMorphPlugins', () {
    test('resolves auth and storage', () {
      final resolved = validateAndIndexConfig(minimalValidConfig());
      final options = MorphOptions(
        plugins: [_StoragePlugin(), _AuthPlugin()],
      );
      final r = installMorphPlugins(
        options.plugins,
        resolved,
        options,
        {},
      );
      expect(r.auth, isA<_StubAuth>());
      expect(r.storage, isA<_MemStorage>());
    });
  });
}

final class _CycleA implements MorphPlugin {
  @override
  String get name => 'a';

  @override
  List<String>? get provides => const ['cap-a'];

  @override
  List<String>? get requires => const ['cap-b'];

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {}
}

final class _CycleB implements MorphPlugin {
  @override
  String get name => 'b';

  @override
  List<String>? get provides => const ['cap-b'];

  @override
  List<String>? get requires => const ['cap-a'];

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {}
}
