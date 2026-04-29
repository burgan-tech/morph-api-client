import 'dart:convert';

typedef JwtPayload = Map<String, Object?>;

String _base64UrlDecode(String s) {
  var b64 = s.replaceAll('-', '+').replaceAll('_', '/');
  final pad = (4 - (b64.length % 4)) % 4;
  b64 += '=' * pad;
  return utf8.decode(base64Decode(b64));
}

/// Parity: [packages/core/src/util/jwt.ts](packages/core/src/util/jwt.ts).
JwtPayload decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length < 2) throw FormatException('Invalid JWT format');
  final jsonStr = _base64UrlDecode(parts[1]);
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map) throw const FormatException('JWT payload must be JSON object');
  return Map<String, Object?>.from(decoded.cast<dynamic, dynamic>());
}

int? getJwtExpirySeconds(String token) {
  try {
    final exp = decodeJwtPayload(token)['exp'];
    if (exp is int) return exp;
    if (exp is num) return exp.round();
    return null;
  } catch (_) {
    return null;
  }
}

String? getJwtSubject(String token, String? claim) {
  if (claim == null || claim.isEmpty) return null;
  try {
    final p = decodeJwtPayload(token)[claim];
    return p is String ? p : null;
  } catch (_) {
    return null;
  }
}
