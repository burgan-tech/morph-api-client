/// Combines base URL and path/absolute URL (parity: [packages/ts/core/src/util/url.ts]).
String resolveEndpoint(String baseUrl, String endpoint) {
  if (RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(endpoint)) {
    return endpoint;
  }
  final b = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final e = endpoint.startsWith('/') ? endpoint : '/$endpoint';
  return '$b$e';
}
