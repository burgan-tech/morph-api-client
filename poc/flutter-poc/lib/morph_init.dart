import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:morph_core/morph_core.dart';
import 'package:morph_logger/create_logger.dart';
import 'package:morph_logger/logger_plugin.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/memory_storage_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deep-link URI scheme used by the Flutter PoC.
const String kOAuthCallbackUri = 'morphpoc://oauth/callback';

/// Prefix for SharedPreferences keys.
const String _kPrefsPrefix = 'morph-poc:';

/// Log events collected from [MorphOptions.onLog]; consumed by the UI.
final List<String> morphLogLines = [];

/// HTTP trace events collected from [MorphOptions.onHttpTrace]; consumed by the UI.
final List<MorphHttpTraceEvent> morphHttpTraces = [];

/// Initializes and returns the [MorphClient] singleton.
///
/// Call once from [main] after [WidgetsFlutterBinding.ensureInitialized].
Future<MorphClient> initMorph() async {
  final config = await _loadConfig();
  final variables = await _buildVariables();

  final logger = loggerPlugin(const LoggerPluginOptions(level: 'debug'));

  final storage = memoryStorageMorphPlugin();

  final options = MorphOptions(
    plugins: [
      logger,
      oauth2Plugin(
        OAuth2PluginOptions(
          logger: logger,
          storage: storage,
          variables: variables,
          autoAcquireNonInteractive: true,
        ),
      ),
    ],
    variables: variables,
    onLog: (level, message, [error, context]) {
      final entry = '[$level] $message${error != null ? ' — $error' : ''}';
      morphLogLines.add(entry);
      if (morphLogLines.length > 300) morphLogLines.removeAt(0);
    },
    onHttpTrace: (event) {
      morphHttpTraces.insert(0, event);
      if (morphHttpTraces.length > 100) morphHttpTraces.removeLast();
    },
  );

  return MorphClient.init(config, options);
}

Future<dynamic> _loadConfig() async {
  final raw = await rootBundle.loadString('assets/poc-config.json');
  return jsonDecode(raw);
}

Future<Map<String, String>> _buildVariables() async {
  final prefs = await SharedPreferences.getInstance();

  final deviceId = _readOrCreate(prefs, '${_kPrefsPrefix}device-id');
  final installationId = _readOrCreate(prefs, '${_kPrefsPrefix}install-id');

  const keycloakBase =
      'http://localhost:8080/realms/morph/protocol/openid-connect';

  return {
    'deviceId': deviceId,
    'installationId': installationId,
    // Client secrets — override via --dart-define at build/run time.
    'deviceClientSecret': const String.fromEnvironment(
      'DEVICE_CLIENT_SECRET',
      defaultValue: 'morph-device-secret',
    ),
    'loginClientSecret': const String.fromEnvironment(
      'LOGIN_CLIENT_SECRET',
      defaultValue: 'morph-login-secret',
    ),
    'sessionClientSecret': const String.fromEnvironment(
      'SESSION_CLIENT_SECRET',
      defaultValue: 'morph-session-secret',
    ),
    // Keycloak — direct HTTP (no CORS proxy needed on mobile/desktop).
    'keycloakOidcBase': keycloakBase,
    'keycloakBrowserBaseUrl': keycloakBase,
    'pocKeycloakTokenHttpBase': '',
    // Google (disabled by default in the PoC).
    'pocGoogleTokenHttpBase': '',
    'pocGoogleTokenEndpoint': 'https://oauth2.googleapis.com/token',
    'googleClientId': const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    'googleClientSecret': const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
    // OAuth redirect — custom scheme handled by app_links.
    'oauthCallbackUri': kOAuthCallbackUri,
  };
}

String _readOrCreate(SharedPreferences prefs, String key) {
  var value = prefs.getString(key);
  if (value == null || value.isEmpty) {
    // Pseudo-UUID using DateTime + hashCode — sufficient for a PoC.
    value =
        '${DateTime.now().millisecondsSinceEpoch}-${key.hashCode.abs()}';
    prefs.setString(key, value);
  }
  return value;
}
