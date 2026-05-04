import 'package:morph_core/morph_core.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/morph_storage.dart';
import 'package:test/test.dart';

import 'minimal_morph_config.dart';

void main() {
  MorphClient makeClient() => MorphClient.init(
        minimalValidConfig(),
        MorphOptions(
          plugins: [
            memoryStorageMorphPlugin(),
            oauth2Plugin(),
          ],
        ),
      );

  group('MorphClient facade', () {
    test('dispose then host throws StateError', () {
      final c = makeClient();
      c.dispose();
      expect(() => c.host('api'), throwsA(isA<StateError>()));
    });

    test('dispose then getTokenStatus throws StateError', () async {
      final c = makeClient();
      c.dispose();
      try {
        await c.getTokenStatus();
        fail('expected StateError');
      } catch (e) {
        expect(e, isA<StateError>());
      }
    });

    test('host exposes key and defaultAuth from config', () {
      final c = makeClient();
      final h = c.host('api');
      expect(h.key, 'api');
      expect(h.defaultAuth, isNull);
      c.dispose();
    });

    test('unknown host key throws UnknownHostError', () {
      final c = makeClient();
      expect(() => c.host('nope'), throwsA(isA<UnknownHostError>()));
      c.dispose();
    });

    test('invalid auth id throws UnknownContextError', () {
      final c = makeClient();
      expect(() => c.auth('nosuch'), throwsA(isA<UnknownContextError>()));
      c.dispose();
    });

    test('auth(peekTokens) returns null for fresh context', () async {
      final c = makeClient();
      final toks = await c.auth('p/c').peekTokens();
      expect(toks, isNull);
      c.dispose();
    });

    test('completeOAuthReturn with non-root path returns none without callback', () async {
      final c = makeClient();
      final r = await c.completeOAuthReturn(
        currentUri: Uri.parse('https://app.example/callback?code=x'),
      );
      expect(r.status, 'none');
      c.dispose();
    });

    test('completeOAuthReturn forwards OAuth error query', () async {
      final c = makeClient();
      final r = await c.completeOAuthReturn(
        currentUri: Uri.parse(
          'https://app.example/?error=access_denied&error_description=nope',
        ),
      );
      expect(r.status, 'oauth_error');
      expect(r.message, contains('access_denied'));
      c.dispose();
    });
  });
}
