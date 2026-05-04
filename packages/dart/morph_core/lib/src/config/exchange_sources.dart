import 'package:morph_core/src/types/morph_types.dart';

/// Parity with TS [normalizeExchangeSources](packages/ts/core/src/util/exchangeSources.ts).
List<String> normalizeExchangeSourcesFromTokenBlock(TokenBlock token) {
  final ex = token.exchangeSource;
  if (ex == null) return [];
  if (ex is List) {
    return ex.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (ex is String) {
    final t = ex.trim();
    if (t.isNotEmpty) return [t];
  }
  return [];
}

bool hasExchangeSourcesFromTokenBlock(TokenBlock token) =>
    normalizeExchangeSourcesFromTokenBlock(token).isNotEmpty;

/// Legacy: token as JSON-like map `{ exchangeSource?: ... }`.
List<String> normalizeExchangeSources(Map<String, dynamic> token) {
  final ex = token['exchangeSource'];
  if (ex == null) return [];
  if (ex is List<dynamic>) {
    return ex.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (ex is String) {
    final t = ex.trim();
    if (t.isNotEmpty) return [t];
  }
  return [];
}

bool hasExchangeSources(Map<String, dynamic> token) => normalizeExchangeSources(token).isNotEmpty;
