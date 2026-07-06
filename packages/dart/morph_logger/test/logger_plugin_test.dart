import 'package:morph_core/morph_core.dart';
import 'package:morph_logger/morph_logger.dart';
import 'package:test/test.dart';

ResolvedMorphConfig minimalResolved() {
  final raw = <String, dynamic>{
    'providers': [
      {
        'key': 'p',
        'type': 'oauth2',
        'baseUrl': 'https://issuer.example',
        'contexts': [
          {
            'key': 'c',
            'token': {'endpoint': '/token'},
            'tokenTypes': {
              'access': {
                'expiryPolicy': 'token',
                'storage': {
                  'scope': 's',
                  'type': 'memory',
                  'protection': 'secure',
                  'key': 'access-key',
                },
              },
            },
          },
        ],
      },
    ],
    'hosts': [
      {
        'key': 'api',
        'baseUrl': 'https://api.example',
        'allowedAuth': ['p/c'],
      },
    ],
  };
  return validateAndIndexConfig(raw);
}

void main() {
  group('createLogger', () {
    test('uses onLog when provided', () {
      final captured = <String>[];
      createLogger(
        LoggerPluginOptions(
          onLog:
              (String level, String msg, [Object? err, Map<String, Object?>? c]) =>
                  captured.add('$level:$msg'),
        ),
      )('info', 'hello', null, null);
      expect(captured, ['info:hello']);
    });

    test('when custom onLog is supplied, level option is delegated to caller', () {
      final lines = <String>[];
      final fn = createLogger(
        LoggerPluginOptions(
          level: 'warn',
          prefix: '[t] ',
          onLog: (String lvl, String msg, [Object? err, Map<String, Object?>? ctx]) =>
              lines.add(msg),
        ),
      );
      fn('debug', 'a', null, null);
      fn('warn', 'b', null, null);
      expect(lines, ['a', 'b']);
    });

    test('default MorphLogFn ignores unknown level labels but still runs', () {
      final fn = createLogger(const LoggerPluginOptions(level: 'warn'));
      expect(fn, isA<MorphLogFn>());
      expect(() => fn('warn', 'w', null, null), returnsNormally);
    });
  });

  group('morphHttpTraceMessage', () {
    test('formats status vs network error', () {
      final ok = MorphHttpTraceEvent(
        kind: 'request',
        hostKey: 'h',
        method: 'GET',
        url: 'https://x',
        path: '/a',
        authId: 'a',
        requestHeaders: {},
        statusCode: 200,
        responseHeaders: {},
        responseBody: null,
        durationMs: 12,
      );
      expect(
        morphHttpTraceMessage('[p] ', ok),
        '[p] GET /a → 200 (12ms)',
      );

      final err = MorphHttpTraceEvent(
        kind: 'request',
        hostKey: 'h',
        method: 'POST',
        url: 'https://x',
        path: '/b',
        authId: 'a',
        requestHeaders: {},
        statusCode: 0,
        responseHeaders: {},
        responseBody: null,
        durationMs: 5,
        networkError: 'timeout',
      );
      expect(
        morphHttpTraceMessage('[p] ', err),
        '[p] POST /b → ERR timeout (5ms)',
      );
    });
  });

  group('loggerPlugin', () {
    MorphPluginContext ctx(MorphOptions o) => MorphPluginContext(
          resolved: minimalResolved(),
          options: o,
          variables: {},
          provideAuth: (_) {},
          provideStorage: (_) {},
        );

    test('chains plugin onLog before existing MorphOptions.onLog', () {
      final seq = <String>[];
      final o = MorphOptions(plugins: const []);
      o.onLog = (String lvl, String msg, [Object? err, Map<String, Object?>? context]) =>
          seq.add('prev:$msg');

      loggerPlugin(
        LoggerPluginOptions(
          onLog: (String _, String msg, [Object? err, Map<String, Object?>? ctx]) =>
              seq.add('new:$msg'),
        ),
      ).install(ctx(o));

      o.onLog?.call('info', 'x', null, null);

      expect(seq, ['new:x', 'prev:x']);
    });

    test('chains plugin onHttpTrace before existing handler', () {
      final seq = <String>[];
      final o = MorphOptions(plugins: const []);
      o.onHttpTrace = (e) => seq.add('prev:${e.path}');

      loggerPlugin(LoggerPluginOptions(
        prefix: '[l] ',
        onHttpTrace: (e) => seq.add('new:${e.path}'),
      )).install(ctx(o));

      o.onHttpTrace?.call(
        MorphHttpTraceEvent(
          kind: 'k',
          hostKey: 'h',
          method: 'GET',
          url: 'u',
          path: '/p',
          authId: 'a',
          requestHeaders: {},
          statusCode: 201,
          responseHeaders: {},
          responseBody: null,
          durationMs: 3,
        ),
      );

      expect(seq, ['new:/p', 'prev:/p']);
    });

    test('does not wrap onHttpTrace when httpTrace is false', () {
      var hits = 0;
      final o = MorphOptions(plugins: const []);
      o.onHttpTrace = (_) => hits++;

      loggerPlugin(const LoggerPluginOptions(httpTrace: false)).install(ctx(o));

      o.onHttpTrace?.call(
        MorphHttpTraceEvent(
          kind: 'k',
          hostKey: 'h',
          method: 'GET',
          url: 'u',
          path: '/p',
          authId: 'a',
          requestHeaders: {},
          statusCode: 200,
          responseHeaders: {},
          responseBody: null,
          durationMs: 1,
        ),
      );

      expect(hits, 1);
    });
  });
}
