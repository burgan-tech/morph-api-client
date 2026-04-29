import 'package:morph_core/src/util/duration_ms.dart';
import 'package:morph_core/src/util/jwt_utils.dart';

/// Parity [packages/oauth2/src/util/expiry.ts].
int? computeExpiresAt(String accessToken, int? expiresIn, String? maxTtl) {
  final fromJwt = getJwtExpirySeconds(accessToken);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  var exp = fromJwt;
  if (exp == null && expiresIn != null) {
    exp = now + expiresIn;
  }
  if (exp == null) return null;
  if (maxTtl != null && maxTtl.isNotEmpty) {
    int? iat;
    try {
      final payload = decodeJwtPayload(accessToken)['iat'];
      if (payload is num) iat = payload.round();
    } catch (_) {
      iat = null;
    }
    final issued = iat ?? now;
    final cap = issued + (parseDurationMs(maxTtl) ~/ 1000);
    exp = exp < cap ? exp : cap;
  }
  return exp;
}

bool isExpired(int? expiresAt, int skewSeconds) {
  if (expiresAt == null) return false;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return now >= expiresAt - skewSeconds;
}
