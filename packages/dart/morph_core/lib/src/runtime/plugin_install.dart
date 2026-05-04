import '../config/resolved_morph_config.dart';
import '../types/morph_surface.dart';

/// Topological install order for plugins whose [MorphPlugin.requires] reference
/// [MorphPlugin.provides] from other plugins (parity `packages/core/src/runtime.ts`).
List<MorphPlugin> topoSortPlugins(List<MorphPlugin> plugins) {
  if (plugins.isEmpty) return [];

  final capToProvider = <String, MorphPlugin>{};
  for (final p in plugins) {
    for (final cap in p.provides ?? const <String>[]) {
      capToProvider[cap] = p;
    }
  }

  final adjOut = <MorphPlugin, Set<MorphPlugin>>{};
  final inDeg = <MorphPlugin, int>{};
  for (final p in plugins) {
    adjOut[p] = <MorphPlugin>{};
    inDeg[p] = 0;
  }

  for (final p in plugins) {
    for (final req in p.requires ?? const <String>[]) {
      final provider = capToProvider[req];
      if (provider == null) {
        throw StateError(
          "Plugin '${p.name}' requires '$req' but no plugin provides it. "
          "Add a plugin with provides: ['$req'] or pass the dependency via plugin options.",
        );
      }
      if (identical(provider, p)) continue;
      if (!adjOut[provider]!.contains(p)) {
        adjOut[provider]!.add(p);
        inDeg[p] = inDeg[p]! + 1;
      }
    }
  }

  final queue = <MorphPlugin>[];
  for (final p in plugins) {
    if (inDeg[p] == 0) queue.add(p);
  }

  final sorted = <MorphPlugin>[];
  while (queue.isNotEmpty) {
    final p = queue.removeAt(0);
    sorted.add(p);
    for (final dep in adjOut[p]!) {
      final d = inDeg[dep]! - 1;
      inDeg[dep] = d;
      if (d == 0) queue.add(dep);
    }
  }

  if (sorted.length != plugins.length) {
    final unsorted = plugins.where((p) => !sorted.contains(p)).map((p) => p.name).join(', ');
    throw StateError('Circular plugin dependency detected among: $unsorted');
  }

  return sorted;
}

/// Result of [installMorphPlugins] (parity `installPlugins`).
final class InstalledPlugins {
  InstalledPlugins({required this.auth, required this.storage});

  final AuthPlugin auth;
  final StorageProvider storage;
}

/// Runs [topoSortPlugins] then [MorphPlugin.install]; ensures exactly one auth + storage.
InstalledPlugins installMorphPlugins(
  List<MorphPlugin> plugins,
  ResolvedMorphConfig resolved,
  MorphOptions options,
  Map<String, String> variables,
) {
  final sorted = topoSortPlugins(plugins);

  AuthPlugin? auth;
  StorageProvider? storage;

  final ctx = MorphPluginContext(
    resolved: resolved,
    options: options,
    variables: variables,
    provideAuth: (AuthPlugin a) {
      if (auth != null) {
        throw StateError('Multiple plugins called provideAuth(). Only one auth plugin is allowed.');
      }
      auth = a;
      options.resolvedAuth = a;
    },
    provideStorage: (StorageProvider s) {
      if (storage != null) {
        throw StateError('Multiple plugins called provideStorage(). Only one storage plugin is allowed.');
      }
      storage = s;
      options.resolvedStorage = s;
    },
  );

  for (final plugin in sorted) {
    plugin.install(ctx);
  }

  if (auth == null) {
    throw StateError(
        'No plugin called provideAuth(). Add an auth plugin (e.g. oauth2Plugin()) to MorphOptions.plugins.');
  }
  if (storage == null) {
    throw StateError(
        'No plugin called provideStorage(). Add a storage plugin (e.g. browserStoragePlugin()) to MorphOptions.plugins.');
  }

  return InstalledPlugins(auth: auth!, storage: storage!);
}
