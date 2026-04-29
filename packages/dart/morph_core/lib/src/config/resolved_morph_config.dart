import 'package:morph_core/src/config/ctx_ref.dart';

/// Result of validating and indexing Morph config (TS `ResolvedMorphConfig`).
///
/// Strongly typed [MorphConfig] DTOs are planned; `config` remains the raw JSON map.
final class ResolvedMorphConfig {
  const ResolvedMorphConfig({
    required this.config,
    required this.contextByAuthId,
    required this.contextsByProvider,
    required this.hostByKey,
  });

  final Map<String, dynamic> config;
  final Map<String, CtxRef> contextByAuthId;

  /// Context JSON objects keyed by provider `key`.
  final Map<String, List<Map<String, dynamic>>> contextsByProvider;

  /// Host JSON objects keyed by host `key`.
  final Map<String, Map<String, dynamic>> hostByKey;
}
