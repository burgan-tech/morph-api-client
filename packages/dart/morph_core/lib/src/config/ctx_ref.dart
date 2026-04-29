/// Reference to a resolved provider + auth context (TS `CtxRef`).
///
/// Stores raw JSON maps until typed [MorphConfig] models exist.
final class CtxRef {
  const CtxRef({required this.provider, required this.context});

  final Map<String, dynamic> provider;
  final Map<String, dynamic> context;

  String get providerKey => provider['key']! as String;

  String get contextKey => context['key']! as String;

  String get authId => '$providerKey/$contextKey';
}
