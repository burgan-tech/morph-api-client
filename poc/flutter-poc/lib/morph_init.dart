import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:morph_core/morph_core.dart';
import 'package:morph_core_storage/morph_core_storage.dart';
import 'package:morph_data_store/morph_data_store.dart';
import 'package:morph_logger/create_logger.dart';
import 'package:morph_logger/logger_plugin.dart';
import 'package:morph_oauth2/morph_oauth2.dart';
import 'package:morph_storage/memory_storage_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deep-link URI scheme used by the Flutter PoC on mobile/desktop.
const String kOAuthCallbackUri = 'morphpoc://oauth/callback';

/// Returns the mock API base URL for the current platform.
/// Android emulators use 10.0.2.2 to reach the host machine's localhost.
String getMockApiBase() {
  final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? '10.0.2.2'
      : 'localhost';
  return 'http://$host:3000';
}

/// Redirect URI used when running as a Flutter web app on Chrome.
/// Must be registered in Keycloak's morph-login client redirectUris.
const String kWebOAuthCallbackUri = 'http://localhost:4200/';

/// Prefix for SharedPreferences keys.
const String _kPrefsPrefix = 'morph-poc:';

/// Log events collected from SDK; consumed by the UI.
final List<String> morphLogLines = [];

/// HTTP trace events collected via [MorphOptions.onHttpTrace]; consumed by the UI.
final List<MorphHttpTraceEvent> morphHttpTraces = [];

/// Shared log appender — writes to browser console AND keeps the in-memory
/// ring buffer (consumed by UI widgets).
// ignore: avoid_print
void _appendLog(String level, String message, [Object? error]) {
  final entry = '[morph][$level] $message${error != null ? ' — $error' : ''}';
  // ignore: avoid_print
  print(entry);
  morphLogLines.add(entry);
  if (morphLogLines.length > 300) morphLogLines.removeAt(0);
}

/// Initializes and returns the [MorphClient] singleton.
///
/// Call once from [main] after [WidgetsFlutterBinding.ensureInitialized].
Future<MorphClient> initMorph() async {
  final config = await _loadConfig();
  final variables = await _buildVariables();

  final logger = loggerPlugin(const LoggerPluginOptions(level: 'debug'));

  // Storage strategy:
  // • Web: in-memory only.  ContextStore requires an active user identity
  //   (Boundary.user) to build storage keys, but on web the OAuth redirect
  //   reloads the page — so the identity is never set before the token write.
  //   In-memory storage is correct here: completeOAuthCallback() runs in main()
  //   before runApp(), so the token lives in the same JS heap the app reads from.
  // • Native: ContextStore (persistent, boundary-scoped).  Deep-link callbacks
  //   do NOT reload the process, so identity can be set before token storage.
  MorphPlugin storagePlugin;
  if (kIsWeb) {
    storagePlugin = memoryStorageMorphPlugin();
    _appendLog('info', 'Storage: in-memory (web — ContextStore requires user identity)');
  } else {
    try {
      final contextStore = await ContextStore.create(ContextStoreOptions(
        onRequestServerTime: (_, __) async => null,
        timeServerUrls: [],
        onLog: (level, message, [err, ctx]) =>
            _appendLog(level.name, message, err),
      ));
      storagePlugin = contextStoreStoragePlugin(contextStore);
      _appendLog('info', 'Storage: ContextStore (persistent)');
    } catch (e) {
      storagePlugin = memoryStorageMorphPlugin();
      _appendLog('warn', 'Storage: fallback to in-memory — ContextStore init failed', e);
    }
  }

  final options = MorphOptions(
    plugins: [
      logger,
      storagePlugin,
      oauth2Plugin(
        OAuth2PluginOptions(
          logger: logger,
          variables: variables,
          autoAcquireNonInteractive: true,
        ),
      ),
    ],
    variables: variables,
    onLog: (level, message, [error, context]) =>
        _appendLog(level, message, error),
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

  // On Android emulators, localhost refers to the emulator's own loopback.
  // Use 10.0.2.2 to reach the host machine's localhost instead.
  // On web (Chrome), localhost is always correct since the browser runs on the host.
  final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? '10.0.2.2'
      : 'localhost';
  final keycloakBase =
      'http://$host:8080/realms/morph/protocol/openid-connect';
  final mockApiBase = 'http://$host:3000';

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
    'mockApiBase': mockApiBase,
    // Google (disabled by default in the PoC).
    'pocGoogleTokenHttpBase': '',
    'pocGoogleTokenEndpoint': 'https://oauth2.googleapis.com/token',
    'googleClientId': const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    'googleClientSecret': const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
    // OAuth redirect — HTTP redirect on web, custom scheme on mobile/desktop.
    'oauthCallbackUri': kIsWeb ? kWebOAuthCallbackUri : kOAuthCallbackUri,
  };
}

String _readOrCreate(SharedPreferences prefs, String key) {
  var value = prefs.getString(key);
  if (value == null || value.isEmpty) {
    value =
        '${DateTime.now().millisecondsSinceEpoch}-${key.hashCode.abs()}';
    prefs.setString(key, value);
  }
  return value;
}
