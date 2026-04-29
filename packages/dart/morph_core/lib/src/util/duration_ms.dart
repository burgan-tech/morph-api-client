const Map<String, double> _unitMs = {
  'ms': 1,
  's': 1000,
  'm': 60000,
  'h': 3600000,
  'd': 86400000,
};

/// Parses strings like `"200ms"`, `"10s"`, `"30d"` into milliseconds.
/// Parity: [packages/core/src/util/duration.ts](packages/core/src/util/duration.ts).
int parseDurationMs(String? input, [int? fallbackMs]) {
  if (input == null || input.trim().isEmpty) {
    if (fallbackMs != null) return fallbackMs;
    throw ArgumentError('Missing duration');
  }
  final re = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h|d)$', caseSensitive: false);
  final m = re.firstMatch(input.trim());
  if (m == null) throw ArgumentError('Invalid duration: $input');
  final n = double.parse(m.group(1)!);
  final u = m.group(2)!.toLowerCase();
  final mult = _unitMs[u];
  if (mult == null) throw ArgumentError('Invalid duration unit: $input');
  return (n * mult).round();
}
