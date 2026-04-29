/// Parity with TS [normalizeExchangeSources](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/util/exchangeSources.ts).
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

bool hasExchangeSources(Map<String, dynamic> token) =>
    normalizeExchangeSources(token).isNotEmpty;
