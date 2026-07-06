import 'package:morph_core/morph_core.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/morph_storage.dart';
import 'package:test/test.dart';

import 'minimal_morph_config.dart';

/// Covers OAuth return / redirect parity on `MorphRuntime` (issue #13); façade tests live in morph_client_facade_test.dart (#14).
void main() {
  MorphClient client() => MorphClient.init(
        minimalValidConfig(),
        MorphOptions(
          plugins: [
            memoryStorageMorphPlugin(),
            oauth2Plugin(),
          ],
        ),
      );

  group('MorphRuntime OAuth return', () {
    test('completeOAuthReturn with non-root path returns none', () async {
      final c = client();
      final r = await c.runtime.completeOAuthReturn(
        currentUri: Uri.parse('https://app.example/callback?code=x'),
      );
      expect(r.status, 'none');
      c.dispose();
    });

    test('completeOAuthReturn forwards OAuth error query on root-ish path', () async {
      final c = client();
      final r = await c.runtime.completeOAuthReturn(
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
