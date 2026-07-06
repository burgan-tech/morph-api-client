/// Low-level coercion helpers for JSON maps (camelCase keys, TS-aligned).
Map<String, dynamic>? asJsonMap(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

List<dynamic>? asJsonList(dynamic v) {
  if (v is List<dynamic>) return v;
  if (v is List) return List<dynamic>.from(v);
  return null;
}

String? asString(dynamic v) => v is String ? v : null;

bool asBool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  return fallback;
}

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return null;
}

double? asDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return null;
}

Map<String, String>? stringMapFromJson(dynamic v) {
  final m = asJsonMap(v);
  if (m == null) return null;
  final out = <String, String>{};
  for (final e in m.entries) {
    if (e.value is String) out[e.key] = e.value as String;
  }
  return out;
}
