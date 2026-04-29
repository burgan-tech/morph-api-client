// TypeScript `types.ts` parity — data classes and callback typedefs for Morph API Client.

import 'package:morph_core/src/types/json_helpers.dart';

// --- Enums / literals ---

typedef LogoutReason = String; // 'user_initiated' | 'unauthorized' | ...

typedef InteractionMode = String; // 'interactive' | 'non-interactive' | 'redirect'

final class DelegateMetadata {
  const DelegateMetadata({
    required this.workflow,
    required this.grantHint,
    required this.interaction,
  });

  factory DelegateMetadata.fromJson(Map<String, dynamic> m) => DelegateMetadata(
        workflow: asString(m['workflow']) ?? '',
        grantHint: asString(m['grantHint']) ?? '',
        interaction: asString(m['interaction']) ?? 'interactive',
      );

  final String workflow;
  final String grantHint;
  final String interaction;

  Map<String, dynamic> toJson() => {
        'workflow': workflow,
        'grantHint': grantHint,
        'interaction': interaction,
      };
}

final class NetworkRetry {
  const NetworkRetry({this.count, this.delay});

  factory NetworkRetry.fromJson(Map<String, dynamic> m) =>
      NetworkRetry(count: asInt(m['count']), delay: asString(m['delay']));

  final int? count;
  final String? delay;

  Map<String, dynamic> toJson() => {
        if (count != null) 'count': count,
        if (delay != null) 'delay': delay,
      };
}

final class NetworkPolicy {
  const NetworkPolicy({this.timeout, this.retry});

  factory NetworkPolicy.fromJson(Map<String, dynamic> m) => NetworkPolicy(
        timeout: asString(m['timeout']),
        retry: m['retry'] is Map ? NetworkRetry.fromJson(asJsonMap(m['retry'])!) : null,
      );

  final String? timeout;
  final NetworkRetry? retry;

  Map<String, dynamic> toJson() => {
        if (timeout != null) 'timeout': timeout,
        if (retry != null) 'retry': retry!.toJson(),
      };
}

final class TokenHeaderConfig {
  const TokenHeaderConfig({required this.name, required this.scheme});

  factory TokenHeaderConfig.fromJson(Map<String, dynamic> m) => TokenHeaderConfig(
        name: asString(m['name']) ?? '',
        scheme: asString(m['scheme']) ?? '',
      );

  final String name;
  final String scheme;

  Map<String, dynamic> toJson() => {'name': name, 'scheme': scheme};
}

final class StorageConfig {
  const StorageConfig({
    required this.scope,
    required this.type,
    required this.protection,
    required this.key,
  });

  factory StorageConfig.fromJson(Map<String, dynamic> m) => StorageConfig(
        scope: asString(m['scope']) ?? '',
        type: asString(m['type']) ?? '',
        protection: asString(m['protection']) ?? '',
        key: asString(m['key']) ?? '',
      );

  final String scope;
  final String type;
  final String protection;
  final String key;

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'type': type,
        'protection': protection,
        'key': key,
      };
}

final class TokenTypeConfig {
  const TokenTypeConfig({
    this.format,
    this.header,
    required this.expiryPolicy,
    this.maxTtl,
    required this.storage,
  });

  factory TokenTypeConfig.fromJson(Map<String, dynamic> m) {
    final stor = asJsonMap(m['storage']);
    return TokenTypeConfig(
      format: asString(m['format']),
      header: m['header'] is Map ? TokenHeaderConfig.fromJson(asJsonMap(m['header'])!) : null,
      expiryPolicy: asString(m['expiryPolicy']) ?? '',
      maxTtl: asString(m['maxTtl']),
      storage: stor != null ? StorageConfig.fromJson(stor) : StorageConfig(scope: '', type: '', protection: '', key: ''),
    );
  }

  final String? format;
  final TokenHeaderConfig? header;
  final String expiryPolicy;
  final String? maxTtl;
  final StorageConfig storage;

  Map<String, dynamic> toJson() => {
        if (format != null) 'format': format,
        if (header != null) 'header': header!.toJson(),
        'expiryPolicy': expiryPolicy,
        if (maxTtl != null) 'maxTtl': maxTtl,
        'storage': storage.toJson(),
      };
}

final class RecoveryPolicy {
  const RecoveryPolicy({this.onUnauthorized, this.onRefreshFail});

  factory RecoveryPolicy.fromJson(Map<String, dynamic> m) => RecoveryPolicy(
        onUnauthorized: asString(m['onUnauthorized']),
        onRefreshFail: asString(m['onRefreshFail']),
      );

  final String? onUnauthorized;
  final String? onRefreshFail;

  Map<String, dynamic> toJson() => {
        if (onUnauthorized != null) 'onUnauthorized': onUnauthorized,
        if (onRefreshFail != null) 'onRefreshFail': onRefreshFail,
      };
}

final class AuthorizationBlock {
  const AuthorizationBlock({
    required this.endpoint,
    this.redirectUri,
    this.responseType,
    this.extraParams,
  });

  factory AuthorizationBlock.fromJson(Map<String, dynamic> m) => AuthorizationBlock(
        endpoint: asString(m['endpoint']) ?? '',
        redirectUri: asString(m['redirectUri']),
        responseType: asString(m['responseType']),
        extraParams: stringMapFromJson(m['extraParams']),
      );

  final String endpoint;
  final String? redirectUri;
  final String? responseType;
  final Map<String, String>? extraParams;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        if (redirectUri != null) 'redirectUri': redirectUri,
        if (responseType != null) 'responseType': responseType,
        if (extraParams != null) 'extraParams': extraParams,
      };
}

final class IdentityBlock {
  const IdentityBlock({this.subject, this.actor});

  factory IdentityBlock.fromJson(Map<String, dynamic> m) =>
      IdentityBlock(subject: asString(m['subject']), actor: asString(m['actor']));

  final String? subject;
  final String? actor;

  Map<String, dynamic> toJson() => {
        if (subject != null) 'subject': subject,
        if (actor != null) 'actor': actor,
      };
}

final class TokenBlock {
  const TokenBlock({
    required this.endpoint,
    this.exchangeEndpoint,
    this.exchangeSource,
  });

  factory TokenBlock.fromJson(Map<String, dynamic> m) => TokenBlock(
        endpoint: asString(m['endpoint']) ?? '',
        exchangeEndpoint: asString(m['exchangeEndpoint']),
        exchangeSource: m['exchangeSource'],
      );

  /// `exchangeSource` stays dynamic: `String` or `List<String>` in TS.
  final String endpoint;
  final String? exchangeEndpoint;
  final Object? exchangeSource;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        if (exchangeEndpoint != null) 'exchangeEndpoint': exchangeEndpoint,
        if (exchangeSource != null) 'exchangeSource': exchangeSource,
      };
}

final class LogoutBlock {
  const LogoutBlock({required this.endpoint});

  factory LogoutBlock.fromJson(Map<String, dynamic> m) =>
      LogoutBlock(endpoint: asString(m['endpoint']) ?? '');

  final String endpoint;

  Map<String, dynamic> toJson() => {'endpoint': endpoint};
}

final class PkceBlock {
  const PkceBlock({this.codeChallengeMethod});

  factory PkceBlock.fromJson(Map<String, dynamic> m) =>
      PkceBlock(codeChallengeMethod: asString(m['codeChallengeMethod']));

  final String? codeChallengeMethod;

  Map<String, dynamic> toJson() => {
        if (codeChallengeMethod != null) 'codeChallengeMethod': codeChallengeMethod,
      };
}

final class RefreshPolicyBlock {
  const RefreshPolicyBlock({this.strategy, this.refreshBeforeExpiry});

  factory RefreshPolicyBlock.fromJson(Map<String, dynamic> m) => RefreshPolicyBlock(
        strategy: asString(m['strategy']),
        refreshBeforeExpiry: asString(m['refreshBeforeExpiry']),
      );

  final String? strategy;
  final String? refreshBeforeExpiry;

  Map<String, dynamic> toJson() => {
        if (strategy != null) 'strategy': strategy,
        if (refreshBeforeExpiry != null) 'refreshBeforeExpiry': refreshBeforeExpiry,
      };
}

final class AuthContextConfig {
  const AuthContextConfig({
    required this.key,
    this.clientId,
    this.clientSecret,
    this.clientAuth,
    this.audience,
    this.identity,
    this.authorization,
    required this.token,
    this.logout,
    this.scopes,
    this.pkce,
    this.refreshPolicy,
    this.recoveryPolicy,
    this.delegateMetadata,
    this.sessionPolicy,
    this.networkPolicy,
    this.headers,
    required this.tokenTypes,
  });

  factory AuthContextConfig.fromJson(Map<String, dynamic> m) {
    final tt = asJsonMap(m['tokenTypes']) ?? {};
    final types = <String, TokenTypeConfig>{};
    for (final e in tt.entries) {
      final sub = asJsonMap(e.value);
      if (sub != null) types[e.key] = TokenTypeConfig.fromJson(sub);
    }
    return AuthContextConfig(
      key: asString(m['key']) ?? '',
      clientId: asString(m['clientId']),
      clientSecret: asString(m['clientSecret']),
      clientAuth: asString(m['clientAuth']),
      audience: asString(m['audience']),
      identity: m['identity'] is Map ? IdentityBlock.fromJson(asJsonMap(m['identity'])!) : null,
      authorization: m['authorization'] is Map ? AuthorizationBlock.fromJson(asJsonMap(m['authorization'])!) : null,
      token: TokenBlock.fromJson(asJsonMap(m['token']) ?? {}),
      logout: m['logout'] is Map ? LogoutBlock.fromJson(asJsonMap(m['logout'])!) : null,
      scopes: asJsonList(m['scopes'])?.map((e) => e.toString()).toList(),
      pkce: m['pkce'] is Map ? PkceBlock.fromJson(asJsonMap(m['pkce'])!) : null,
      refreshPolicy: m['refreshPolicy'] is Map ? RefreshPolicyBlock.fromJson(asJsonMap(m['refreshPolicy'])!) : null,
      recoveryPolicy: m['recoveryPolicy'] is Map ? RecoveryPolicy.fromJson(asJsonMap(m['recoveryPolicy'])!) : null,
      delegateMetadata:
          m['delegateMetadata'] is Map ? DelegateMetadata.fromJson(asJsonMap(m['delegateMetadata'])!) : null,
      sessionPolicy: stringMapFromJson(m['sessionPolicy']),
      networkPolicy: m['networkPolicy'] is Map ? NetworkPolicy.fromJson(asJsonMap(m['networkPolicy'])!) : null,
      headers: stringMapFromJson(m['headers']),
      tokenTypes: types,
    );
  }

  final String key;
  final String? clientId;
  final String? clientSecret;
  final String? clientAuth;
  final String? audience;
  final IdentityBlock? identity;
  final AuthorizationBlock? authorization;
  final TokenBlock token;
  final LogoutBlock? logout;
  final List<String>? scopes;
  final PkceBlock? pkce;
  final RefreshPolicyBlock? refreshPolicy;
  final RecoveryPolicy? recoveryPolicy;
  final DelegateMetadata? delegateMetadata;
  final Map<String, String>? sessionPolicy;
  final NetworkPolicy? networkPolicy;
  final Map<String, String>? headers;
  final Map<String, TokenTypeConfig> tokenTypes;

  Map<String, dynamic> toJson() => {
        'key': key,
        if (clientId != null) 'clientId': clientId,
        if (clientSecret != null) 'clientSecret': clientSecret,
        if (clientAuth != null) 'clientAuth': clientAuth,
        if (audience != null) 'audience': audience,
        if (identity != null) 'identity': identity!.toJson(),
        if (authorization != null) 'authorization': authorization!.toJson(),
        'token': token.toJson(),
        if (logout != null) 'logout': logout!.toJson(),
        if (scopes != null) 'scopes': scopes,
        if (pkce != null) 'pkce': pkce!.toJson(),
        if (refreshPolicy != null) 'refreshPolicy': refreshPolicy!.toJson(),
        if (recoveryPolicy != null) 'recoveryPolicy': recoveryPolicy!.toJson(),
        if (delegateMetadata != null) 'delegateMetadata': delegateMetadata!.toJson(),
        if (sessionPolicy != null) 'sessionPolicy': sessionPolicy,
        if (networkPolicy != null) 'networkPolicy': networkPolicy!.toJson(),
        if (headers != null) 'headers': headers,
        'tokenTypes': tokenTypes.map((k, v) => MapEntry(k, v.toJson())),
      };
}

final class ProviderConfig {
  const ProviderConfig({
    required this.key,
    required this.type,
    required this.baseUrl,
    this.authorizationBrowserBaseUrl,
    this.tokenHttpBaseUrl,
    this.networkPolicy,
    this.headers,
    required this.contexts,
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> m) {
    final ctxs = <AuthContextConfig>[];
    final raw = asJsonList(m['contexts']);
    if (raw != null) {
      for (final c in raw) {
        final cm = asJsonMap(c);
        if (cm != null) ctxs.add(AuthContextConfig.fromJson(cm));
      }
    }
    return ProviderConfig(
      key: asString(m['key']) ?? '',
      type: asString(m['type']) ?? 'oauth2',
      baseUrl: asString(m['baseUrl']) ?? '',
      authorizationBrowserBaseUrl: asString(m['authorizationBrowserBaseUrl']),
      tokenHttpBaseUrl: asString(m['tokenHttpBaseUrl']),
      networkPolicy: m['networkPolicy'] is Map ? NetworkPolicy.fromJson(asJsonMap(m['networkPolicy'])!) : null,
      headers: stringMapFromJson(m['headers']),
      contexts: ctxs,
    );
  }

  final String key;
  /// Always `oauth2` in current SDK.
  final String type;
  final String baseUrl;
  final String? authorizationBrowserBaseUrl;
  final String? tokenHttpBaseUrl;
  final NetworkPolicy? networkPolicy;
  final Map<String, String>? headers;
  final List<AuthContextConfig> contexts;

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'baseUrl': baseUrl,
        if (authorizationBrowserBaseUrl != null) 'authorizationBrowserBaseUrl': authorizationBrowserBaseUrl,
        if (tokenHttpBaseUrl != null) 'tokenHttpBaseUrl': tokenHttpBaseUrl,
        if (networkPolicy != null) 'networkPolicy': networkPolicy!.toJson(),
        if (headers != null) 'headers': headers,
        'contexts': contexts.map((c) => c.toJson()).toList(),
      };
}

final class HostConfig {
  const HostConfig({
    required this.key,
    required this.baseUrl,
    required this.allowedAuth,
    this.defaultAuth,
    this.headers,
  });

  factory HostConfig.fromJson(Map<String, dynamic> m) {
    final aa = <String>[];
    final raw = asJsonList(m['allowedAuth']);
    if (raw != null) {
      for (final a in raw) {
        if (a is String) aa.add(a);
      }
    }
    return HostConfig(
      key: asString(m['key']) ?? '',
      baseUrl: asString(m['baseUrl']) ?? '',
      allowedAuth: aa,
      defaultAuth: asString(m['defaultAuth']),
      headers: stringMapFromJson(m['headers']),
    );
  }

  final String key;
  final String baseUrl;
  final List<String> allowedAuth;
  final String? defaultAuth;
  final Map<String, String>? headers;

  Map<String, dynamic> toJson() => {
        'key': key,
        'baseUrl': baseUrl,
        'allowedAuth': allowedAuth,
        if (defaultAuth != null) 'defaultAuth': defaultAuth,
        if (headers != null) 'headers': headers,
      };
}

final class MorphConfig {
  const MorphConfig({
    required this.providers,
    required this.hosts,
    this.rootCallbackAuthId,
  });

  factory MorphConfig.fromJson(Map<String, dynamic> m) {
    final prov = <ProviderConfig>[];
    for (final p in asJsonList(m['providers']) ?? const []) {
      final pm = asJsonMap(p);
      if (pm != null) prov.add(ProviderConfig.fromJson(pm));
    }
    final hs = <HostConfig>[];
    for (final h in asJsonList(m['hosts']) ?? const []) {
      final hm = asJsonMap(h);
      if (hm != null) hs.add(HostConfig.fromJson(hm));
    }
    return MorphConfig(
      providers: prov,
      hosts: hs,
      rootCallbackAuthId: asString(m['rootCallbackAuthId']),
    );
  }

  final List<ProviderConfig> providers;
  final List<HostConfig> hosts;
  final String? rootCallbackAuthId;

  Map<String, dynamic> toJson() => {
        'providers': providers.map((p) => p.toJson()).toList(),
        'hosts': hosts.map((h) => h.toJson()).toList(),
        if (rootCallbackAuthId != null) 'rootCallbackAuthId': rootCallbackAuthId,
      };
}

/// Reference to a resolved provider + auth context (TS `CtxRef`).
final class CtxRef {
  const CtxRef({required this.provider, required this.context});

  final ProviderConfig provider;
  final AuthContextConfig context;

  String get providerKey => provider.key;

  String get contextKey => context.key;

  String get authId => '${provider.key}/${context.key}';
}
