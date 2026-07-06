import 'package:morph_core/morph_core.dart';

/// Partial callbacks (`Partial<MorphCallbacks>` parity) for assembling [MorphOAuthCallbacks].
final class MorphOAuthCallbacksPartial {
  const MorphOAuthCallbacksPartial({
    this.onAuthRequired,
    this.onLogout,
    this.onTokenChange,
  });

  final void Function(String authId, DelegateMetadata meta)? onAuthRequired;
  final void Function(String authId, LogoutReason reason)? onLogout;
  final void Function(String authId, TokenSet? tokens)? onTokenChange;
}

/// Callbacks matching TS [`MorphCallbacks`](/packages/ts/core/src/types.ts).
final class MorphOAuthCallbacks {
  MorphOAuthCallbacks({
    required this.onAuthRequired,
    this.onLogout,
    this.onTokenChange,
  });

  final void Function(String authId, DelegateMetadata meta) onAuthRequired;

  /// Same semantics as TS `MorphCallbacks.onLogout` (often optional).
  final void Function(String authId, String reason)? onLogout;

  final void Function(String authId, TokenSet? tokens)? onTokenChange;
}
