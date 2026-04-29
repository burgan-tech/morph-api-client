import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:morph_core/morph_core.dart';

final class OAuthTokenResponse {
  OAuthTokenResponse({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.tokenType,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? tokenType;
}

OAuthTokenResponse oauthResponseFromJson(dynamic json) {
  if (json is! Map) throw FormatException('OAuth token JSON must be object');
  final m = Map<String, dynamic>.from(json.cast<dynamic, dynamic>());
  return OAuthTokenResponse(
    accessToken: m['access_token'] as String? ?? '',
    refreshToken: m['refresh_token'] as String?,
    expiresIn: (m['expires_in'] as num?)?.toInt(),
    tokenType: m['token_type'] as String?,
  );
}

Map<String, String> mergeTokenHeaders(
  ProviderConfig provider,
  AuthContextConfig ctx,
  Map<String, String> variables,
) {
  final base = interpolateRecord(provider.headers, variables) ?? {};
  final extra = interpolateRecord(ctx.headers, variables, {'key': ctx.key}) ?? {};
  return {...base, ...extra};
}

Future<OAuthTokenResponse> postTokenRequest(
  String url,
  Map<String, String> body,
  Map<String, String> headers,
  NetworkPolicy? policy,
  MorphLogFn? log,
) async {
  final timeoutMs = parseDurationMs(policy?.timeout, 30000);
  final retries = policy?.retry?.count ?? 0;
  final delayMs = parseDurationMs(policy?.retry?.delay, 200);

  Object? lastErr;
  for (var attempt = 0; attempt <= retries; attempt++) {
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              ...headers,
            },
            body: Uri(queryParameters: body).query,
            encoding: utf8,
          )
          .timeout(Duration(milliseconds: timeoutMs));

      final text = res.body;
      dynamic json;
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = {'raw': text};
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        log?.call('warn', 'Token endpoint HTTP ${res.statusCode}', null, {'url': url, 'json': json});
        throw TokenEndpointError(res.statusCode, text);
      }
      return oauthResponseFromJson(json);
    } catch (e) {
      if (e is TokenEndpointError) rethrow;
      lastErr = e;
      if (attempt < retries) await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
  throw lastErr ?? StateError('postTokenRequest exhausted retries');
}

String tokenEndpointUrl(
  String tokenHttpBase,
  AuthContextConfig ctx,
  bool useExchangeEndpoint,
  Map<String, String> variables,
) {
  final raw = useExchangeEndpoint && (ctx.token.exchangeEndpoint?.trim().isNotEmpty ?? false)
      ? ctx.token.exchangeEndpoint!.trim()
      : ctx.token.endpoint.trim();
  final ep = interpolateString(raw, variables, {'key': ctx.key});
  return resolveEndpoint(tokenHttpBase, ep);
}

Future<Map<String, String>> buildClientAuthFields({
  required String authId,
  required AuthContextConfig ctx,
  required Map<String, String> variables,
  Future<String?> Function(String authId)? onClientJwtAssertion,
}) async {
  final clientId =
      ctx.clientId != null ? interpolateString(ctx.clientId!, variables, {'key': ctx.key}) : '';
  final out = <String, String>{'client_id': clientId};
  final auth = ctx.clientAuth ?? 'client_secret_post';
  if (auth == 'private_key_jwt') {
    final assertion = await onClientJwtAssertion?.call(authId);
    if (assertion != null && assertion.isNotEmpty) {
      out['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';
      out['client_assertion'] = assertion;
      return out;
    }
  }
  if (ctx.clientSecret != null && ctx.clientSecret!.trim().isNotEmpty) {
    out['client_secret'] = interpolateString(ctx.clientSecret!, variables, {'key': ctx.key});
  }
  return out;
}
