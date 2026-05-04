import 'package:morph_core/morph_core.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/morph_storage.dart';
import 'package:test/test.dart';

import 'minimal_morph_config.dart';

void main() {
  group('MorphClient.init', () {
    test('bootstrap succeeds with memory storage + oauth2 plugins', () {
      final client = MorphClient.init(
        minimalValidConfig(),
        MorphOptions(
          plugins: [
            memoryStorageMorphPlugin(),
            oauth2Plugin(),
          ],
        ),
      );
      expect(client.runtime.tokens, isA<TokenLifecycle>());
      expect(client.runtime.storage, isA<MemoryStorageProvider>());
      client.dispose();
    });
  });
}
