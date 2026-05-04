import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:morph_core/morph_core.dart';

/// HTTP host pipeline parity with `packages/ts/core/src/http/hostPipeline.ts`.
final class HostPipeline {
  HostPipeline({
    required ResolvedMorphConfig resolved,
    required MorphOptions options,
    required Map<String, String> variables,
    required AuthPlugin tokens,
    http.Client? httpClient,
  })  : _resolved = resolved,
        _options = options,
        _variables = variables,
        _tokens = tokens,
        _client = httpClient ?? http.Client();

  final ResolvedMorphConfig _resolved;
  final MorphOptions _options;
  final Map<String, String> _variables;
  final AuthPlugin _tokens;
  final http.Client _client;

  Future<MorphResponse<T>> hostFetch<T>(
    HostConfig host,
    String path, {
    required String method,
    Object? body,
    Object? auth,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    String? timeout,
    bool sign = false,
    bool encrypted = false,
  }) async {
    final authIds = normalizeAuth(host, auth);
    Object? lastErr;
    for (final authId in authIds) {
      ensureAuthAllowed(host, authId);
      final ref = _resolved.contextByAuthId[authId];
      if (ref == null) throw UnknownContextError(authId);
      try {
        final token = await _tokens.resolveAccessToken(authId, ref, 'http');
        return await _performFetch<T>(
              host,
              path,
              method: method,
              body: body,
              headers: headers,
              queryParams: queryParams,
              timeout: timeout,
              sign: sign,
              encrypted: encrypted,
              token: token,
              authId: authId,
            );
      } catch (e) {
        lastErr = e;
      }
    }
    final errObj = lastErr;
    if (errObj != null) {
      throw errObj;
    }
    throw StateError('hostFetch failed');
  }

  List<String> normalizeAuth(HostConfig host, Object? auth) {
    if (auth == null) {
      final d = host.defaultAuth;
      if (d == null || d.isEmpty) {
        throw StateError('Host ${host.key} has no defaultAuth; pass auth in request options.');
      }
      return [d];
    }
    if (auth is String) return [auth];
    if (auth is Iterable) return auth.map((e) => e.toString()).toList();
    throw ArgumentError('auth');
  }

  void ensureAuthAllowed(HostConfig host, String authId) {
    if (!host.allowedAuth.contains(authId)) {
      throw InvalidAuthForHostError(host.key, authId, host.allowedAuth);
    }
  }

  Future<MorphResponse<T>> _performFetch<T>(
    HostConfig host,
    String path, {
    required String method,
    Object? body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    String? timeout,
    required bool sign,
    required bool encrypted,
    required String token,
    required String authId,
  }) async {
    final ref = _resolved.contextByAuthId[authId]!;
    final accessType = ref.context.tokenTypes['access'];
    final headerCfg = accessType?.header ?? const TokenHeaderConfig(name: 'Authorization', scheme: 'Bearer');

    var urlStr = resolveEndpoint(host.baseUrl, path.startsWith('/') ? path : '/$path');

    Uri uri = Uri.parse(urlStr);
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...queryParams});
    }

    final timeoutMs = parseDurationMs(timeout, 30000);

    String? serialized;
    if (body == null) {
      serialized = null;
    } else if (body is String || body is List<int>) {
      serialized = body.toString();
    } else {
      serialized = jsonEncode(body);
    }

    if (sign) {
      if (_options.onSignPayload == null || serialized == null || serialized.isEmpty) {
        throw StateError('sign: true requires a JSON body string and onSignPayload');
      }
      final sig = await _options.onSignPayload!(serialized, authId);
      headers = {...?headers, 'X-JWS-Signature': sig};
    }

    final mergedHost = interpolateRecord(host.headers, _variables);
    final headerMap = <String, String>{
      ...?mergedHost,
      ...?_interpolateHeaders(headers),
      headerCfg.name: '${headerCfg.scheme} $token',
    };

    Future<http.Response> once(Map<String, String> hdrs) async {
      final req = http.Request(method, uri);
      req.headers.addAll(hdrs);
      final b = serialized;
      req.bodyBytes = utf8.encode(b ?? '');
      if (serialized != null) {
        req.headers['content-type'] = req.headers['content-type'] ?? 'application/json;charset=utf-8';
      }
      return _client.send(req).timeout(Duration(milliseconds: timeoutMs)).then(http.Response.fromStream);
    }

    final sw = DateTime.now();
    var resp = await once(headerMap);

    if (resp.statusCode == 401 && ref.context.recoveryPolicy?.onUnauthorized == 'refresh') {
      await _tokens.handle401Recovery(authId, ref);
      final hdr2 = Map<String, String>.from(headerMap);
      final newTok = await _tokens.resolveAccessToken(authId, ref, 'http');
      hdr2[headerCfg.name] = '${headerCfg.scheme} $newTok';
      resp = await once(hdr2);
    }

    if (resp.statusCode == 401 && ref.context.recoveryPolicy?.onUnauthorized == 'delegate') {
      _tokens.fireAuthRequired(authId, ref.context);
      throw AuthError(authId, 'delegation_required');
    }

    var text = utf8.decode(resp.bodyBytes);

    if (encrypted) {
      if (_options.onDecryptResponse == null) {
        throw StateError('encrypted response requires onDecryptResponse');
      }
      text = await _options.onDecryptResponse!(text, authId);
    }

    Object? parsedBody = text.isEmpty ? null : text;

    final ct = resp.headers['content-type'] ?? '';
    if (parsedBody != null &&
        ct.contains('application/json') &&
        parsedBody is String &&
        parsedBody.isNotEmpty) {
      try {
        parsedBody = jsonDecode(parsedBody);
      } catch (_) {}
    }

    final headersOut = <String, String>{};
    resp.headers.forEach((k, v) {
      headersOut[k.toLowerCase()] = v;
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MorphHttpError(resp.statusCode, path, parsedBody, authId);
    }

    final durationMs = DateTime.now().difference(sw).inMilliseconds;
    _options.onHttpTrace?.call(MorphHttpTraceEvent(
          kind: 'host_http',
          hostKey: host.key,
          method: method,
          url: uri.toString(),
          path: path.startsWith('/') ? path : '/$path',
          authId: authId,
          requestHeaders: redactedRequestHeadersMap(headerMap),
          statusCode: resp.statusCode,
          responseHeaders: headersOut,
          responseBody: parsedBody,
          durationMs: durationMs,
        ));

    return MorphResponse<T>(
      statusCode: resp.statusCode,
      headers: headersOut,
      body: parsedBody as T,
      resolvedAuth: authId,
      raw: resp,
    );
  }

  Map<String, String>? _interpolateHeaders(Map<String, String>? h) =>
      interpolateRecord(h, _variables);
}
