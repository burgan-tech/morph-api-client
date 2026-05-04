import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

import 'morph_init.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final morph = await initMorph();

  // On web, handle OAuth callback BEFORE runApp so tokens are stored before
  // HomeScreen reads token status. The callback URL looks like:
  //   http://localhost:4200/?code=XXX&state=YYY
  String? oauthMessage;
  if (kIsWeb) {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code != null && state != null) {
      try {
        final result = await morph.completeOAuthCallback(code: code, state: state);
        oauthMessage =
            'OAuth complete: ${result.status}${result.message != null ? ' — ${result.message}' : ''}';
      } catch (e) {
        oauthMessage = 'OAuth callback error: $e';
      }
    }
  }

  runApp(MorphPocApp(morph: morph, initialMessage: oauthMessage));
}

class MorphPocApp extends StatefulWidget {
  const MorphPocApp({super.key, required this.morph, this.initialMessage});

  final MorphClient morph;
  final String? initialMessage;

  @override
  State<MorphPocApp> createState() => _MorphPocAppState();
}

class _MorphPocAppState extends State<MorphPocApp> {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingOAuthMessage;

  @override
  void initState() {
    super.initState();
    // Carry the OAuth result message from main() into the UI.
    _pendingOAuthMessage = widget.initialMessage;
    if (!kIsWeb) {
      _appLinks = AppLinks();
      _linkSubscription = _appLinks!.uriLinkStream.listen(_handleIncomingUri);
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
          return HomeScreen(morph: widget.morph);
        },
      ),
    );
  }
}
