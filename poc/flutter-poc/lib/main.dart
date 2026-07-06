import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

import 'morph_init.dart';
import 'screens/home_screen.dart';

/// Captures the OAuth params from the URL **synchronously** before runApp,
/// so we can clear them from `Uri.base` and process them after the UI mounts.
({String? code, String? state})? _captureWebOAuthParams() {
  if (!kIsWeb) return null;
  final uri = Uri.base;
  final code = uri.queryParameters['code'];
  final state = uri.queryParameters['state'];
  if (code == null || state == null) return null;
  return (code: code, state: state);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ignore: avoid_print
  print('[morph-poc] main() start — ${Uri.base}');

  final pendingOAuth = _captureWebOAuthParams();
  // ignore: avoid_print
  print('[morph-poc] OAuth params present? ${pendingOAuth != null}');

  final morph = await initMorph();
  // ignore: avoid_print
  print('[morph-poc] initMorph() done — runApp now');

  // Render UI immediately; HomeScreen will process the OAuth callback in initState.
  runApp(MorphPocApp(morph: morph, pendingOAuth: pendingOAuth));
  // ignore: avoid_print
  print('[morph-poc] runApp returned');
}

class MorphPocApp extends StatefulWidget {
  const MorphPocApp({super.key, required this.morph, this.pendingOAuth});

  final MorphClient morph;
  final ({String? code, String? state})? pendingOAuth;

  @override
  State<MorphPocApp> createState() => _MorphPocAppState();
}

class _MorphPocAppState extends State<MorphPocApp> {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingOAuthMessage;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('[morph-poc] _MorphPocAppState.initState');
    if (!kIsWeb) {
      _appLinks = AppLinks();
      _linkSubscription = _appLinks!.uriLinkStream.listen(_handleIncomingUri);
    } else if (widget.pendingOAuth != null) {
      // Process web OAuth callback AFTER the UI mounted, so a hang/error
      // here does not prevent runApp from rendering.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processPendingWebOAuth();
      });
    }
  }

  Future<void> _processPendingWebOAuth() async {
    final p = widget.pendingOAuth!;
    // ignore: avoid_print
    print('[morph-poc] _processPendingWebOAuth: calling completeOAuthCallback…');
    try {
      final result = await widget.morph.completeOAuthCallback(
        code: p.code,
        state: p.state,
      );
      // ignore: avoid_print
      print('[morph-poc] completeOAuthCallback DONE: ${result.status} / ${result.message}');
      if (mounted) {
        setState(() => _pendingOAuthMessage =
            'OAuth complete: ${result.status}${result.message != null ? ' — ${result.message}' : ''}');
        // Trigger HomeScreen to re-read token status after OAuth completes.
        await _homeKey.currentState?.refreshStatus();
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[morph-poc] completeOAuthCallback THREW: $e\n$st');
      if (mounted) {
        setState(() => _pendingOAuthMessage = 'OAuth callback error: $e');
      }
    }
  }

  /// Mobile/desktop: handles deep-link OAuth callbacks via app_links.
  Future<void> _handleIncomingUri(Uri uri) async {
    if (!uri.toString().startsWith(kOAuthCallbackUri)) return;

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];

    if (code == null || state == null) {
      setState(() => _pendingOAuthMessage = 'OAuth callback missing code/state');
      return;
    }

    try {
      final result = await widget.morph.runtime.completeOAuthCallback(
        code: code,
        state: state,
      );
      setState(() => _pendingOAuthMessage =
          'OAuth complete: ${result.status}${result.message != null ? ' — ${result.message}' : ''}');
    } catch (e) {
      setState(() => _pendingOAuthMessage = 'OAuth callback error: $e');
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    widget.morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morph Flutter PoC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          if (_pendingOAuthMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_pendingOAuthMessage!),
                  duration: const Duration(seconds: 4),
                ),
              );
              setState(() => _pendingOAuthMessage = null);
            });
          }
          return HomeScreen(key: _homeKey, morph: widget.morph);
        },
      ),
    );
  }
}
