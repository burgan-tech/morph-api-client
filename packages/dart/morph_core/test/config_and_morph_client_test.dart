import 'package:morph_core/morph_core.dart';
import 'package:test/test.dart';

/// Minimal Morph JSON passing [validateAndIndexConfig] (same rules as `@morph/core`).
Map<String, dynamic> minimalValidConfig() => {
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
  group('validateAndIndexConfig', () {
    test('accepts minimal valid Morph config', () {
      expect(() => validateAndIndexConfig(minimalValidConfig()), returnsNormally);
      final r = validateAndIndexConfig(minimalValidConfig());
      expect(r.contextByAuthId['p/c'], isNotNull);
      expect(r.hostByKey['api']?.baseUrl, 'https://api.example');
    });

    test('matches TS errors when providers missing', () {
      expect(
        () => validateAndIndexConfig(<String, dynamic>{
          'providers': <dynamic>[],
          'hosts': <dynamic>[],
        }),
        throwsA(
          predicate<ConfigValidationError>(
            (e) =>
                e.errors.contains('At least one provider is required') &&
                e.errors.contains('At least one host is required'),
          ),
        ),
      );
    });
  });

  group('MorphClient.init', () {
    test('runs validation then fails with UnimplementedError on valid config', () {
      expect(
        () => MorphClient.init(minimalValidConfig(), MorphOptions(plugins: const [])),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
