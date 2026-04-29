import 'package:morph_core/src/config/resolved_morph_config.dart';

/// Parity with [listAuthIdsForProvider](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/config/validate.ts).
List<String> listAuthIdsForProvider(String providerKey, ResolvedMorphConfig resolved) {
  final ctxs = resolved.contextsByProvider[providerKey] ?? [];
  final p = _findProvider(resolved.config, providerKey);
  if (p == null) return [];
  final pk = p['key'] as String?;
  if (pk == null) return [];
  return ctxs.map((c) => '$pk/${c['key']}').toList();
}

Map<String, dynamic>? _findProvider(Map<String, dynamic> config, String key) {
  final raw = config['providers'];
  if (raw is! List<dynamic>) return null;
  for (final e in raw) {
    if (e is Map<String, dynamic> && e['key'] == key) return e;
  }
  return null;
}
