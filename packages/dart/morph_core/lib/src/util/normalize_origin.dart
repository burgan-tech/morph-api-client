/// Normalizes IPv6 loopback origins to localhost (parity TS [normalizeOrigin.ts]).
String normalizeLoopbackOrigin(String origin) {
  try {
    final u = Uri.parse(origin);
    final h = u.host.toLowerCase();
    final ipv6 =
        h == '::1' || h == '[::1]' || h == '[::ffff:127.0.0.1]' || h == '::ffff:127.0.0.1';
    if (ipv6) {
      final port = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
      return '${u.scheme}://localhost:$port';
    }
  } catch (_) {
    /* ignore */
  }
  return origin;
}
