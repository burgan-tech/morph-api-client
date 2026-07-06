import 'package:morph_core/morph_core.dart';
import 'package:test/test.dart';

import 'minimal_morph_config.dart';

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
    test('throws when plugins list is empty (no auth/storage)', () {
      expect(
        () => MorphClient.init(minimalValidConfig(), MorphOptions(plugins: const [])),
        throwsA(isA<StateError>().having((e) => e.toString(), 'txt', contains('provideAuth'))),
      );
    });
  });
}
