/// Redacts `Authorization`-style traces (parity TS [httpTrace.ts] helpers).
Map<String, String> redactedRequestHeadersMap(Map<String, String> hdr) {
  final o = <String, String>{};
  hdr.forEach((k, v) {
    if (k.toLowerCase() == 'authorization') {
      final parts = v.trim().split(RegExp(r'\s+'));
      o[k] = parts.length >= 2 ? '${parts[0]} <redacted>' : '<redacted>';
    } else {
      o[k] = v;
    }
  });
  return o;
}
