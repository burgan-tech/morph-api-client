import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:morph_core/morph_core.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

sealed class PocSimStep {
  const PocSimStep({required this.label});
  final String label;
}

final class PocSimFetchStep extends PocSimStep {
  const PocSimFetchStep({
    required super.label,
    required this.path,
    this.expectStatus,
    this.skipInAutoSim = false,
  });
  final String path;
  final int? expectStatus;
  final bool skipInAutoSim;
}

final class PocSimHostStep extends PocSimStep {
  const PocSimHostStep({
    required super.label,
    required this.hostKey,
    required this.method,
    required this.path,
    required this.auth,
    this.body,
    this.headers,
    this.skipInAutoSim = false,
  });
  final String hostKey;
  final String method;
  final String path;
  final String auth;
  final Object? body;
  final Map<String, String>? headers;
  final bool skipInAutoSim;
}

final class PocSimLogoutStep extends PocSimStep {
  const PocSimLogoutStep({
    required super.label,
    required this.providerKey,
  });
  final String providerKey;
}

final class PocSimStepResult {
  const PocSimStepResult({
    required this.label,
    required this.status,
    this.detail,
    this.body,
  });
  final String label;

  /// HTTP status code, or one of: 'OK', 'ERR', 'NET', 'AUTH'
  final Object status;
  final String? detail;
  final Object? body;

  bool get isError {
    if (status is int) return (status as int) >= 400;
    return status == 'ERR' || status == 'NET' || status == 'AUTH';
  }
}

/// When an auto-simulation step returns [PocSimStepResult.status] `AUTH`, decide
/// whether to stop the loop (stale Keycloak session). Kept pure for unit tests.
bool isPocSessionDeadStop({
  required PocSimStepResult result,
  required PocSimStep step,
  required List<String> sessionDeadAuthIds,
}) {
  if (result.status != 'AUTH') return false;
  final isSessionDead =
      step is PocSimHostStep && sessionDeadAuthIds.contains(step.auth);
  final detail = result.detail ?? '';
  return isSessionDead &&
      (detail.contains('invalid_grant') ||
          detail.contains('Token is not active'));
}

// ---------------------------------------------------------------------------
// Config loader
// ---------------------------------------------------------------------------

class PocSimulationConfig {
  PocSimulationConfig({
    required this.mockApiBaseUrl,
    required this.steps,
    required this.sessionDeadAuthIds,
    required this.sessionDeadMessage,
  });

  final String mockApiBaseUrl;
  final List<PocSimStep> steps;
  final List<String> sessionDeadAuthIds;
  final String sessionDeadMessage;
}

Future<PocSimulationConfig> loadPocSimulation(String mockApiBase) async {
  final raw = await rootBundle.loadString('assets/poc-simulation.json');
  return parsePocSimulationJson(raw, mockApiBase);
}

/// Parses the PoC simulation document (same shape as [assets/poc-simulation.json]).
/// [mockApiFallback] is used when the document omits `mockApi.baseUrl`.
PocSimulationConfig parsePocSimulationJson(String raw, String mockApiFallback) {
  final json = jsonDecode(raw) as Map<String, dynamic>;

  final mockApi = (json['mockApi'] as Map<String, dynamic>?) ?? {};
  final baseUrl = (mockApi['baseUrl'] as String?) ?? mockApiFallback;

  final sessionDeadCheck =
      (json['sessionDeadCheck'] as Map<String, dynamic>?) ?? {};
  final sessionDeadAuthIds = (sessionDeadCheck['authIds'] as List<dynamic>?)
          ?.cast<String>() ??
      const [];
  final sessionDeadMessage =
      (sessionDeadCheck['message'] as String?) ?? 'Session expired.';

  final steps = <PocSimStep>[];
  for (final raw in (json['steps'] as List<dynamic>? ?? [])) {
    final s = _parseStep(raw as Map<String, dynamic>);
    if (s != null) steps.add(s);
  }

  // Conditional blocks (skip Google, include 404 probe as optional)
  for (final block
      in (json['conditionalBlocks'] as List<dynamic>? ?? [])) {
    final b = block as Map<String, dynamic>;
    final id = b['id'] as String? ?? '';
    // 404 probe included without condition check — SimulationPanel handles enable/disable
    if (id == 'probe_404') {
      for (final raw in (b['steps'] as List<dynamic>? ?? [])) {
        final s = _parseStep(raw as Map<String, dynamic>);
        if (s != null) steps.add(s);
      }
    }
    // Google block: skip (not configured in the PoC env)
  }

  return PocSimulationConfig(
    mockApiBaseUrl: baseUrl,
    steps: steps,
    sessionDeadAuthIds: sessionDeadAuthIds,
    sessionDeadMessage: sessionDeadMessage,
  );
}

PocSimStep? _parseStep(Map<String, dynamic> m) {
  final type = m['type'] as String?;
  final label = m['label'] as String? ?? '';
  switch (type) {
    case 'fetch':
      return PocSimFetchStep(
        label: label,
        path: m['path'] as String? ?? '',
        expectStatus: m['expectStatus'] as int?,
        skipInAutoSim: m['skipInAutoSim'] as bool? ?? false,
      );
    case 'host':
      final rawHeaders = m['headers'] as Map<String, dynamic>?;
      return PocSimHostStep(
        label: label,
        hostKey: m['hostKey'] as String? ?? 'main-api',
        method: (m['method'] as String? ?? 'GET').toUpperCase(),
        path: m['path'] as String? ?? '',
        auth: m['auth'] as String? ?? '',
        body: m['body'],
        headers: rawHeaders?.cast<String, String>(),
        skipInAutoSim: m['skipInAutoSim'] as bool? ?? false,
      );
    case 'logout_provider':
      return PocSimLogoutStep(
        label: label,
        providerKey: m['providerKey'] as String? ?? '',
      );
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Step executor
// ---------------------------------------------------------------------------

Future<PocSimStepResult> runPocSimStep(
  MorphClient morph,
  PocSimulationConfig cfg,
  PocSimStep step, [
  http.Client? httpClient,
]) async {
  return switch (step) {
    PocSimFetchStep s => _runFetch(s, cfg.mockApiBaseUrl, httpClient),
    PocSimHostStep s => _runHost(morph, s),
    PocSimLogoutStep s => _runLogout(morph, s),
  };
}

Future<PocSimStepResult> _runFetch(
  PocSimFetchStep step,
  String mockApiBase, [
  http.Client? clientOverride,
]) async {
  final url = '$mockApiBase${step.path}';
  final client = clientOverride ?? http.Client();
  final ownsClient = clientOverride == null;
  try {
    final res = await client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    final expectedStatus = step.expectStatus;
    final ok = expectedStatus == null
        ? res.statusCode < 400
        : res.statusCode == expectedStatus;
    Object? body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = res.body;
    }
    return PocSimStepResult(
      label: step.label,
      status: res.statusCode,
      detail: ok ? null : 'Unexpected status ${res.statusCode}',
      body: body,
    );
  } catch (e) {
    return PocSimStepResult(
        label: step.label, status: 'NET', detail: e.toString());
  } finally {
    if (ownsClient) client.close();
  }
}

/// Calls [_runFetch] with an injected HTTP client for unit tests.
@visibleForTesting
Future<PocSimStepResult> runPocSimFetchForTesting(
  PocSimFetchStep step,
  String mockApiBase,
  http.Client httpClient,
) =>
    _runFetch(step, mockApiBase, httpClient);

Future<PocSimStepResult> _runHost(
    MorphClient morph, PocSimHostStep step) async {
  try {
    final host = morph.runtime.getHost(step.hostKey);
    final res = await morph.runtime.http.hostFetch<dynamic>(
      host,
      step.path,
      method: step.method,
      body: step.body != null ? jsonEncode(step.body) : null,
      auth: step.auth,
      headers: step.headers,
    );
    return PocSimStepResult(
      label: step.label,
      status: res.statusCode,
      body: res.body,
    );
  } catch (e) {
    // PoC: morph_core/hostFetch errors are surfaced as opaque strings until
    // typed error parity exists; keep heuristic aligned with Gemini review (#28).
    final msg = e.toString();
    final isAuth = msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('Unauthorized') ||
        msg.contains('invalid_grant');
    return PocSimStepResult(
      label: step.label,
      status: isAuth ? 'AUTH' : 'ERR',
      detail: msg,
    );
  }
}

Future<PocSimStepResult> _runLogout(
    MorphClient morph, PocSimLogoutStep step) async {
  try {
    await morph.auth(step.providerKey).logout();
    return PocSimStepResult(
      label: step.label,
      status: 'OK',
      detail: 'Logged out ${step.providerKey}',
    );
  } catch (e) {
    return PocSimStepResult(
        label: step.label, status: 'ERR', detail: e.toString());
  }
}
