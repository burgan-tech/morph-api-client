import 'package:morph_core/src/config/exchange_sources.dart';
import 'package:morph_core/src/config/resolved_morph_config.dart';
import 'package:morph_core/src/errors/morph_errors.dart';
import 'package:morph_core/src/types/morph_types.dart';

/// Validates and indexes Morph config (parity with TS [validateAndIndexConfig]).
///
/// Accepts a [MorphConfig] or a JSON [Map] (converted via [MorphConfig.fromJson]).
///
/// Throws [ConfigValidationError] when validation fails with the same error strings as
/// [@morph/core](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/ts/core/src/config/validate.ts).
ResolvedMorphConfig validateAndIndexConfig(dynamic raw) {
  final MorphConfig config;
  if (raw is MorphConfig) {
    config = raw;
  } else if (raw is Map<String, dynamic>) {
    config = MorphConfig.fromJson(Map<String, dynamic>.from(raw));
  } else if (raw is Map) {
    config = MorphConfig.fromJson(Map<String, dynamic>.from(raw));
  } else {
    throw ArgumentError('validateAndIndexConfig: expected MorphConfig or Map, got ${raw.runtimeType}');
  }

  final errors = <String>[];
  if (config.providers.isEmpty) errors.add('At least one provider is required');
  if (config.hosts.isEmpty) errors.add('At least one host is required');

  final contextByAuthId = <String, CtxRef>{};
  final contextsByProvider = <String, List<AuthContextConfig>>{};
  final providerKeys = <String>{};

  for (final p in config.providers) {
    if (p.key.isEmpty) errors.add('Provider missing key');
    if (providerKeys.contains(p.key)) errors.add('Duplicate provider key: ${p.key}');
    providerKeys.add(p.key);
    if (p.type != 'oauth2') errors.add('Provider ${p.key}: only oauth2 is supported');
    if (p.baseUrl.isEmpty) errors.add('Provider ${p.key}: baseUrl is required');
    final ctxKeys = <String>{};
    for (final c in p.contexts) {
      if (c.key.isEmpty) errors.add('Provider ${p.key}: context missing key');
      if (ctxKeys.contains(c.key)) {
        errors.add('Provider ${p.key}: duplicate context key ${c.key}');
      }
      ctxKeys.add(c.key);
      if (c.token.endpoint.isEmpty) {
        errors.add('Provider ${p.key}/${c.key}: token.endpoint is required');
      }
      if (!c.tokenTypes.containsKey('access')) {
        errors.add('Provider ${p.key}/${c.key}: tokenTypes.access is required');
      }
      final authId = '${p.key}/${c.key}';
      if (contextByAuthId.containsKey(authId)) {
        errors.add('Duplicate auth id $authId');
      } else {
        contextByAuthId[authId] = CtxRef(provider: p, context: c);
      }
    }
    contextsByProvider[p.key] = List<AuthContextConfig>.from(p.contexts);
  }

  final hostByKey = <String, HostConfig>{};
  final hostKeys = <String>{};

  for (final h in config.hosts) {
    if (h.key.isEmpty) errors.add('Host missing key');
    if (hostKeys.contains(h.key)) errors.add('Duplicate host key: ${h.key}');
    hostKeys.add(h.key);
    hostByKey[h.key] = h;
    if (h.baseUrl.isEmpty) errors.add('Host ${h.key}: baseUrl is required');
    if (h.allowedAuth.isEmpty) {
      errors.add('Host ${h.key}: allowedAuth must be a non-empty array');
    } else {
      for (final aid in h.allowedAuth) {
        if (!contextByAuthId.containsKey(aid)) {
          errors.add('Host ${h.key}: allowedAuth references unknown $aid');
        }
      }
    }
    final def = h.defaultAuth;
    if (def != null) {
      if (!contextByAuthId.containsKey(def)) {
        errors.add('Host ${h.key}: defaultAuth $def is unknown');
      }
      if (!h.allowedAuth.contains(def)) {
        errors.add('Host ${h.key}: defaultAuth must be listed in allowedAuth');
      }
    }
    // Optional host headers: typed as Map<String,String>; no further validation.
  }

  for (final entry in contextByAuthId.entries) {
    final authId = entry.key;
    final c = entry.value.context;
    for (final src in normalizeExchangeSourcesFromTokenBlock(c.token)) {
      if (!contextByAuthId.containsKey(src)) {
        errors.add('$authId: token.exchangeSource references unknown context $src');
      }
    }
  }

  // DFS cycle detection — circular exchangeSource chains (A→B→A) would deadlock
  // at runtime via nested _withLock calls in TokenLifecycle.resolveAccessToken.
  final _dfsSeen = <String>{};
  bool _hasCycle(String node, Set<String> inStack) {
    if (inStack.contains(node)) return true;
    if (_dfsSeen.contains(node)) return false;
    _dfsSeen.add(node);
    inStack.add(node);
    final ctx = contextByAuthId[node];
    if (ctx != null) {
      for (final src in normalizeExchangeSourcesFromTokenBlock(ctx.context.token)) {
        if (_hasCycle(src, {...inStack})) return true;
      }
    }
    return false;
  }
  for (final authId in contextByAuthId.keys) {
    if (_hasCycle(authId, {})) {
      errors.add('Circular token.exchangeSource dependency detected involving "$authId"');
      break;
    }
  }

  final rootCallback = config.rootCallbackAuthId?.trim();
  if (config.rootCallbackAuthId != null) {
    if (rootCallback == null || rootCallback.isEmpty) {
      errors.add('rootCallbackAuthId must be a non-empty string when set');
    } else if (!contextByAuthId.containsKey(rootCallback)) {
      errors.add('rootCallbackAuthId: unknown auth id $rootCallback');
    }
  }

  if (errors.isNotEmpty) throw ConfigValidationError(errors);

  return ResolvedMorphConfig(
    config: config,
    contextByAuthId: contextByAuthId,
    contextsByProvider: contextsByProvider,
    hostByKey: hostByKey,
  );
}

/// Same as [validateAndIndexConfig] but parses from JSON [raw].
ResolvedMorphConfig validateAndIndexConfigFromJson(Map<String, dynamic> raw) =>
    validateAndIndexConfig(MorphConfig.fromJson(Map<String, dynamic>.from(raw)));
