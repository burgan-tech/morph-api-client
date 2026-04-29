import 'package:morph_core/morph_core.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/morph_storage.dart';
import 'package:test/test.dart';

Map<String, dynamic> minimalValidMorphConfig() => {
      'providers': [
        {
          'key': 'p',
          'type': 'oauth2',
          'baseUrl': 'https://issuer.example',
          'contexts': [
            {
              'key': 'c',
              'token': {'endpoint': '/token'},
              'tokenTypes': {
                'access': {
                  'expiryPolicy': 'token',
                  'storage': {
                    'scope': 's',
                    'type': 'memory',
                    'protection': 'secure',
                    'key': 'access-key',
                  },
                },
              },
            },
          ],
        },
      ],
      'hosts': [
        {
          'key': 'api',
          'baseUrl': 'https://api.example',
          'allowedAuth': ['p/c'],
        },
      ],
    };

void main() {
  group('oauth2Plugin', () {
    late ResolvedMorphConfig resolved;

    setUp(() {
      resolved = validateAndIndexConfig(minimalValidMorphConfig());
    });

    test('provideAuth installs TokenLifecycle with direct MemoryStorageProvider', () {
      final options = MorphOptions(plugins: const []);
      AuthPlugin? captured;
      oauth2Plugin(OAuth2PluginOptions(storage: MemoryStorageProvider()))
          .install(MorphPluginContext(
        resolved: resolved,
        options: options,
        variables: {},
        provideAuth: (a) => captured = a,
        provideStorage: (_) {},
      ));
      expect(captured, isA<TokenLifecycle>());
    });

    test('uses MorphOptions.resolvedStorage when storage option is omitted', () {
      final options = MorphOptions(plugins: const []);
      options.resolvedStorage = MemoryStorageProvider();
      AuthPlugin? captured;
      oauth2Plugin().install(MorphPluginContext(
        resolved: resolved,
        options: options,
        variables: {},
        provideAuth: (a) => captured = a,
        provideStorage: (_) {},
      ));
      expect(captured, isA<TokenLifecycle>());
    });

    test('inline storage MorphPlugin provides storage before oauth2 auth', () {
      final options = MorphOptions(plugins: const []);
      oauth2Plugin(OAuth2PluginOptions(storage: memoryStorageMorphPlugin()))
          .install(MorphPluginContext(
        resolved: resolved,
        options: options,
        variables: {},
        provideAuth: (_) {},
        provideStorage: (s) => options.resolvedStorage = s,
      ));

      AuthPlugin? captured;
      oauth2Plugin().install(MorphPluginContext(
        resolved: resolved,
        options: options,
        variables: {},
        provideAuth: (a) => captured = a,
        provideStorage: (_) {},
      ));
      expect(captured, isA<TokenLifecycle>());
    });

    test('throws StateError without any storage source', () {
      final options = MorphOptions(plugins: const []);
      expect(
        () => oauth2Plugin().install(MorphPluginContext(
              resolved: resolved,
              options: options,
              variables: {},
              provideAuth: (_) {},
              provideStorage: (_) {},
            )),
        throwsStateError,
      );
    });
  });
}
