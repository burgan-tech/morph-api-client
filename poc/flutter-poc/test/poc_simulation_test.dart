import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:morph_flutter_poc/poc_simulation.dart';

void main() {
  group('PocSimStepResult.isError', () {
    test('int status >= 400 is error', () {
      expect(
        const PocSimStepResult(label: 'x', status: 200).isError,
        false,
      );
      expect(
        const PocSimStepResult(label: 'x', status: 399).isError,
        false,
      );
      expect(
        const PocSimStepResult(label: 'x', status: 400).isError,
        true,
      );
    });

    test('string sentinel statuses', () {
      expect(
        const PocSimStepResult(label: 'x', status: 'OK').isError,
        false,
      );
      expect(
        const PocSimStepResult(label: 'x', status: 'ERR').isError,
        true,
      );
      expect(
        const PocSimStepResult(label: 'x', status: 'NET').isError,
        true,
      );
      expect(
        const PocSimStepResult(label: 'x', status: 'AUTH').isError,
        true,
      );
    });
  });

  group('parsePocSimulationJson', () {
    test('fills mock URL from fallback when baseUrl omitted', () {
      final cfg = parsePocSimulationJson(
        jsonEncode({
          'steps': [
            {'type': 'fetch', 'label': 'ping', 'path': '/health'},
          ],
        }),
        'http://fallback/',
      );
      expect(cfg.mockApiBaseUrl, 'http://fallback/');
      expect(cfg.steps, hasLength(1));
      expect(cfg.steps.first, isA<PocSimFetchStep>());
      expect((cfg.steps.first as PocSimFetchStep).path, '/health');
    });

    test('uses mockApi.baseUrl when present', () {
      final cfg = parsePocSimulationJson(
        jsonEncode({
          'mockApi': {'baseUrl': 'http://mock/'},
          'steps': [],
        }),
        'http://ignored/',
      );
      expect(cfg.mockApiBaseUrl, 'http://mock/');
    });

    test('parses fetch, host, logout and skips unknown types', () {
      final cfg = parsePocSimulationJson(
        jsonEncode({
          'steps': [
            {'type': 'fetch', 'label': 'f', 'path': '/a', 'expectStatus': 201},
            {
              'type': 'host',
              'label': 'h',
              'hostKey': 'main-api',
              'method': 'post',
              'path': '/p',
              'auth': 'morph-auth/device',
              'headers': {'X': '1'},
              'skipInAutoSim': true,
            },
            {'type': 'logout_provider', 'label': 'l', 'providerKey': 'morph-auth'},
            {'type': 'unknown_future_type', 'label': 'skip'},
          ],
        }),
        'http://m/',
      );
      expect(cfg.steps, hasLength(3));

      final host = cfg.steps[1] as PocSimHostStep;
      expect(host.method, 'POST');
      expect(host.headers, {'X': '1'});
      expect(host.skipInAutoSim, true);
    });

    test('probe_404 conditional block merges steps', () {
      final cfg = parsePocSimulationJson(
        jsonEncode({
          'steps': [
            {'type': 'fetch', 'label': 'a', 'path': '/a'},
          ],
          'conditionalBlocks': [
            {
              'id': 'probe_404',
              'steps': [
                {'type': 'fetch', 'label': 'probe', 'path': '/missing'},
              ],
            },
          ],
        }),
        'http://m/',
      );
      expect(cfg.steps, hasLength(2));
      expect(cfg.steps.last.label, 'probe');
    });

    test('sessionDeadCheck defaults', () {
      final empty = parsePocSimulationJson('{}', 'http://m/');
      expect(empty.sessionDeadAuthIds, isEmpty);
      expect(empty.sessionDeadMessage, 'Session expired.');

      final full = parsePocSimulationJson(
        jsonEncode({
          'sessionDeadCheck': {
            'authIds': ['morph-auth/1fa'],
            'message': 'custom',
          },
        }),
        'http://m/',
      );
      expect(full.sessionDeadAuthIds, ['morph-auth/1fa']);
      expect(full.sessionDeadMessage, 'custom');
    });
  });

  group('isPocSessionDeadStop', () {
    late PocSimHostStep sessionStep;

    setUp(() {
      sessionStep = const PocSimHostStep(
        label: 'x',
        hostKey: 'main-api',
        method: 'GET',
        path: '/p',
        auth: 'morph-auth/2fa',
      );
    });

    test('requires AUTH status', () {
      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(label: 'x', status: 'ERR'),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/2fa'],
        ),
        false,
      );
    });

    test('requires auth context in sessionDeadAuthIds', () {
      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(
            label: 'x',
            status: 'AUTH',
            detail: 'invalid_grant foo',
          ),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/device'],
        ),
        false,
      );
    });

    test('requires invalid_grant OR Token is not active in detail', () {
      expect(
        isPocSessionDeadStop(
          result:
              const PocSimStepResult(label: 'x', status: 'AUTH', detail: 'other'),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/2fa'],
        ),
        false,
      );

      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(
            label: 'x',
            status: 'AUTH',
            detail: 'something invalid_grant',
          ),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/2fa'],
        ),
        true,
      );

      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(
            label: 'x',
            status: 'AUTH',
            detail: 'Token is not active (session)',
          ),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/2fa'],
        ),
        true,
      );
    });

    test('does not treat Token is not active as session-dead for non-listed auth '
        '(operator-precedence regression)', () {
      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(
            label: 'x',
            status: 'AUTH',
            detail: 'Token is not active',
          ),
          step: sessionStep,
          sessionDeadAuthIds: const ['morph-auth/1fa'], // 2fa step not listed
        ),
        false,
      );
    });

    test('logout step never matches session host auth', () {
      expect(
        isPocSessionDeadStop(
          result: const PocSimStepResult(
            label: 'x',
            status: 'AUTH',
            detail: 'invalid_grant',
          ),
          step: const PocSimLogoutStep(label: 'out', providerKey: 'morph-auth'),
          sessionDeadAuthIds: const ['morph-auth'],
        ),
        false,
      );
    });
  });

  group('fetch step (mocked HTTP)', () {
    test('parses JSON body on 200', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://m/ping');
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final step = const PocSimFetchStep(label: 'p', path: '/ping');
      final r =
          await runPocSimFetchForTesting(step, 'http://m', client);
      expect(r.status, 200);
      expect(r.isError, false);
      expect(r.body, {'ok': true});
      client.close();
    });

    test('unexpected explicit expectStatus sets detail', () async {
      final client = MockClient(
        (_) async => http.Response('{}', 500),
      );
      final step =
          const PocSimFetchStep(label: 'e', path: '/', expectStatus: 200);
      final r =
          await runPocSimFetchForTesting(step, 'http://m', client);
      expect(r.status, 500);
      expect(r.isError, true);
      expect(r.detail, contains('Unexpected status'));
      client.close();
    });
  });

  group('loadPocSimulation asset', () {
    test('parses committed poc-simulation.json', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cfg = await loadPocSimulation('http://should-not-use-if-json-has-base');
      expect(cfg.steps, isNotEmpty);
      expect(
        cfg.mockApiBaseUrl,
        startsWith('http://'),
      );
      expect(
        cfg.sessionDeadAuthIds,
        containsAll(['morph-auth/1fa', 'morph-auth/2fa']),
      );
    });
  });
}
