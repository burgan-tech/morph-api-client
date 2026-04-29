/// Strips common OAuth return query params without changing path/hash structure.
/// Browser `history` unchanged here (caller may use [Uri] + window).
String stripOAuthReturnSearchParams(String href) {
  final u = Uri.parse(href);
  const keys = [
    'code',
    'state',
    'session_state',
    'iss',
    'scope',
    'error',
    'error_description',
  ];
  final qp = Map<String, String>.from(u.queryParameters);
  for (final k in keys) {
    qp.remove(k);
  }
  final rebuilt = Uri(
    scheme: u.scheme,
    userInfo: u.userInfo,
    host: u.host,
    port: u.hasPort ? u.port : null,
    path: u.path,
    queryParameters: qp.isEmpty ? null : qp,
    fragment: u.fragment.isEmpty ? null : u.fragment,
  );
  return rebuilt.toString();
}
