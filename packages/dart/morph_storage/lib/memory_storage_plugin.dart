import 'package:morph_core/morph_core.dart';

import 'memory_storage_provider.dart';

/// [`MorphPlugin`] that [`provideStorage`] with an in-memory store (parity idea: inline storage plugin).
MorphPlugin memoryStorageMorphPlugin() => _MemoryStoragePluginMorph();

final class _MemoryStoragePluginMorph implements MorphPlugin {
  final MemoryStorageProvider _storage = MemoryStorageProvider();

  @override
  String get name => '@morph/dart-memory-storage';

  @override
  List<String>? get requires => null;

  @override
  List<String>? get provides => const ['storage'];

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {
    ctx.provideStorage(_storage);
    ctx.options.onLog?.call('debug',
        'Storage initialized (memory, plugin: $name)', null, {'plugin': name});
  }
}
