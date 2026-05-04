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

  runApp(MorphPocApp(morph: morph));
}

class MorphPocApp extends StatefulWidget {
  const MorphPocApp({super.key, required this.morph});

  final MorphClient morph;

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
    if (kIsWeb) {
      // On web, Keycloak redirects back to the app URL with code+state params.
      // Check Uri.base once on startup instead of using a custom scheme listener.
      _handleWebOAuthCallbackIfPresent();
    } else {
      _appLinks = AppLinks();
      _linkSubscription = _appLinks!.uriLinkStream.listen(_handleIncomingUri);
    }
  }

  /// Detects an OAuth callback redirect on web by inspecting [Uri.base].
  void _handleWebOAuthCallbackIfPresent() {
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('code') &&
        uri.queryParameters.containsKey('state')) {
      _handleIncomingUri(uri);
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final uriStr = uri.toString();
    final expectedPrefix = kIsWeb ? kWebOAuthCallbackUri : kOAuthCallbackUri;
    if (!uriStr.startsWith(expectedPrefix)) return;

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
