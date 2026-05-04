final _varPattern = RegExp(r'\$([a-zA-Z_][a-zA-Z0-9_]*)');

/// Replaces `$variable` tokens (parity: [packages/ts/core/src/config/interpolate.ts]).
String interpolateString(
  String template,
  Map<String, String> variables, [
  Map<String, String>? extras,
]) {
  final map = {...variables, ...?extras};
  return template.replaceAllMapped(_varPattern, (m) {
    final name = m.group(1)!;
    if (!map.containsKey(name)) {
      throw StateError('Missing variable: \$$name in "$template"');
    }
    return map[name]!;
  });
}

Map<String, String>? interpolateRecord(
  Map<String, String>? record,
  Map<String, String> variables, [
  Map<String, String>? extras,
]) {
  if (record == null) return null;
  final out = <String, String>{};
  record.forEach((k, v) {
    out[k] = interpolateString(v, variables, extras);
  });
  return out;
}
