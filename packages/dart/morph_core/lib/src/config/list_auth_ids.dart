import 'package:morph_core/src/config/resolved_morph_config.dart';

/// Parity with TS [listAuthIdsForProvider](packages/ts/core/src/config/validate.ts).
List<String> listAuthIdsForProvider(String providerKey, ResolvedMorphConfig resolved) {
  final ctxs = resolved.contextsByProvider[providerKey] ?? [];
  final pIndex = resolved.config.providers.indexWhere((x) => x.key == providerKey);
  if (pIndex < 0) return [];
  final p = resolved.config.providers[pIndex];
  return ctxs.map((c) => '${p.key}/${c.key}').toList();
}
