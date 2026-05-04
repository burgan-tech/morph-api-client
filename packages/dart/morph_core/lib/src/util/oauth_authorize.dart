import 'package:morph_core/src/util/resolve_endpoint.dart';

/// Builds an OAuth 2.0 authorization redirect URL.
/// Parity: [packages/ts/core/src/util/oauthAuthorize.ts](packages/ts/core/src/util/oauthAuthorize.ts).
String buildOAuth2AuthorizationUrl({
  required String baseUrl,
  required String authorizationPath,
  required String clientId,
  required String redirectUri,
  List<String>? scopes,
  String? responseType,
  Map<String, String>? extraParams,
  required String state,
}) {
  final u = resolveEndpoint(baseUrl, authorizationPath);
  final q = <String, String>{
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': responseType ?? 'code',
    'state': state,
  };
  if (scopes != null && scopes.isNotEmpty) {
    q['scope'] = scopes.join(' ');
  }
  final buf = StringBuffer('$u?');
  var first = true;
  void add(String k, String v) {
    if (!first) buf.write('&');
    first = false;
    buf.write('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
  }

  q.forEach(add);
  if (extraParams != null) {
    for (final e in extraParams.entries) {
      if (e.value.isNotEmpty) add(e.key, e.value);
    }
  }
  return buf.toString();
}
