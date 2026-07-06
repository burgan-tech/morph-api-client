import 'package:morph_core/morph_core.dart';

/// In-memory [StorageProvider] for tests / VM-only apps.
final class MemoryStorageProvider implements StorageProvider {
  MemoryStorageProvider();

  final Map<String, String> _store = {};

  String _scopedKey(String key, StorageConfig cfg) => '${cfg.scope}:${cfg.type}:${cfg.protection}:${cfg.key}:$key';

  @override
  Future<void> delete(String key, StorageConfig storageConfig) async {
    _store.remove(_scopedKey(key, storageConfig));
  }

  @override
  Future<void> deleteByPrefix(String prefix, StorageConfig storageConfig) async {
    final p = _scopedKey(prefix, storageConfig);
    _store.removeWhere((k, _) => k.startsWith(p));
  }

  @override
  Future<String?> read(String key, StorageConfig storageConfig) async => _store[_scopedKey(key, storageConfig)];

  @override
  Future<void> write(String key, String value, StorageConfig storageConfig) async {
    _store[_scopedKey(key, storageConfig)] = value;
  }
}
