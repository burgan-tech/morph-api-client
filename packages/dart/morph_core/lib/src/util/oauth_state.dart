import 'dart:convert';
import 'dart:math';

const _prefix = 'morph1.';

/// Encodes [authId] into OAuth state (URL-safe base64 payload).
/// Parity: [packages/ts/core/src/util/oauthState.ts](packages/ts/core/src/util/oauthState.ts).
String encodeOAuthState(String authId) {
  final n = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(4294967295)}';
  final payload = jsonEncode({'a': authId, 'n': n});
  var b64 = base64Encode(utf8.encode(payload));
  b64 = b64.replaceAll('+', '-').replaceAll('/', '_').replaceAll(RegExp(r'=+$'), '');
  return '$_prefix$b64';
}

/// Decodes [authId] from OAuth state, or returns null when format is unrecognized.
({String authId})? decodeOAuthState(String state) {
  if (!state.startsWith(_prefix)) return null;
  try {
    var b = state.substring(_prefix.length).replaceAll('-', '+').replaceAll('_', '/');
    while (b.length % 4 != 0) {
      b += '=';
    }
    final decoded = utf8.decode(base64Decode(b));
    final o = jsonDecode(decoded);
    if (o is Map && o['a'] is String) {
      final a = o['a'] as String;
      if (a.contains('/')) return (authId: a);
    }
  } catch (_) {
    /* ignore */
  }
  return null;
}
