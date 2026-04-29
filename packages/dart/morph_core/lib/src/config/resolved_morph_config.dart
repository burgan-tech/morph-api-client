import 'package:morph_core/src/types/morph_types.dart';

/// Result of validating and indexing Morph config (TS `ResolvedMorphConfig`).
final class ResolvedMorphConfig {
  const ResolvedMorphConfig({
    required this.config,
    required this.contextByAuthId,
    required this.contextsByProvider,
    required this.hostByKey,
  });

  final MorphConfig config;
  final Map<String, CtxRef> contextByAuthId;

  /// Contexts keyed by provider `key`.
  final Map<String, List<AuthContextConfig>> contextsByProvider;

  final Map<String, HostConfig> hostByKey;
}
