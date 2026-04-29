import 'package:morph_core/src/config/ctx_ref.dart';
import 'package:morph_core/src/config/exchange_sources.dart';
import 'package:morph_core/src/config/resolved_morph_config.dart';
import 'package:morph_core/src/errors/morph_errors.dart';

/// Validates and indexes Morph JSON config (parity with TS [validateAndIndexConfig]).
///
/// Throws [ConfigValidationError] when validation fails with the same error strings as
/// [@morph/core](https://github.com/burgan-tech/morph-api-client/blob/f/plugin/packages/core/src/config/validate.ts).
ResolvedMorphConfig validateAndIndexConfig(Map<String, dynamic> raw) {
  final errors = <String>[];
  final rawProviders = raw['providers'];
  final rawHosts = raw['hosts'];
  if (rawProviders is! List<dynamic> || rawProviders.isEmpty) {
    errors.add('At least one provider is required');
  }
  if (rawHosts is! List<dynamic> || rawHosts.isEmpty) {
    errors.add('At least one host is required');
  }

  final contextByAuthId = <String, CtxRef>{};
  final contextsByProvider = <String, List<Map<String, dynamic>>>{};
  final providerKeys = <String>{};

  if (rawProviders is List<dynamic>) {
    for (final pe in rawProviders) {
      if (pe is! Map<String, dynamic>) {
        errors.add('Provider entries must be objects');
        continue;
      }
      final p = pe;
      final pk = p['key'];
      if (pk is! String || pk.isEmpty) errors.add('Provider missing key');
      if (pk is String) {
        if (providerKeys.contains(pk)) errors.add('Duplicate provider key: $pk');
        providerKeys.add(pk);
        if (p['type'] != 'oauth2') errors.add('Provider $pk: only oauth2 is supported');
        if (p['baseUrl'] is! String || (p['baseUrl'] as String).isEmpty) {
          errors.add('Provider $pk: baseUrl is required');
        }
        final authBrowser = p['authorizationBrowserBaseUrl'];
        if (authBrowser != null && authBrowser is! String) {
          errors.add('Provider $pk: authorizationBrowserBaseUrl must be a string');
        }
        final tokenHttp = p['tokenHttpBaseUrl'];
        if (tokenHttp != null && tokenHttp is! String) {
          errors.add('Provider $pk: tokenHttpBaseUrl must be a string');
        }
        final ctxKeys = <String>{};
        final rawContexts = p['contexts'];
        if (rawContexts is! List<dynamic>) {
          errors.add('Provider $pk: contexts must be an array');
        } else {
          for (final ce in rawContexts) {
            if (ce is! Map<String, dynamic>) {
              errors.add('Provider $pk: context entries must be objects');
              continue;
            }
            final c = ce;
            final ck = c['key'];
            if (ck is! String || ck.isEmpty) {
              errors.add('Provider $pk: context missing key');
            } else {
              if (ctxKeys.contains(ck)) {
                errors.add('Provider $pk: duplicate context key $ck');
              }
              ctxKeys.add(ck);
            }
            final label = ck is String ? ck : '?';
            final token = c['token'];
            if (token is! Map<String, dynamic>) {
              errors.add('Provider $pk/$label: token must be an object');
            } else {
              final ep = token['endpoint'];
              if (ep is! String || ep.isEmpty) {
                errors.add('Provider $pk/$label: token.endpoint is required');
              }
            }
            final ttRaw = c['tokenTypes'];
            if (ttRaw is! Map<String, dynamic> || ttRaw['access'] == null) {
              errors.add('Provider $pk/$label: tokenTypes.access is required');
            }
            if (ck is String) {
              final authId = '$pk/$ck';
              if (contextByAuthId.containsKey(authId)) {
                errors.add('Duplicate auth id $authId');
              } else {
                contextByAuthId[authId] = CtxRef(provider: p, context: c);
              }
            }
          }
          contextsByProvider[pk] = rawContexts.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
  }

  final hostByKey = <String, Map<String, dynamic>>{};
  final hostKeys = <String>{};

  if (rawHosts is List<dynamic>) {
    for (final he in rawHosts) {
      if (he is! Map<String, dynamic>) {
        errors.add('Host entries must be objects');
        continue;
      }
      final h = he;
      final hk = h['key'];
      if (hk is! String || hk.isEmpty) errors.add('Host missing key');
      if (hk is String) {
        if (hostKeys.contains(hk)) errors.add('Duplicate host key: $hk');
        hostKeys.add(hk);
        hostByKey[hk] = h;
        if (h['baseUrl'] is! String || (h['baseUrl'] as String).isEmpty) {
          errors.add('Host $hk: baseUrl is required');
        }
        final allowed = h['allowedAuth'];
        if (allowed is! List<dynamic> || allowed.isEmpty) {
          errors.add('Host $hk: allowedAuth must be a non-empty array');
        } else {
          for (final aid in allowed) {
            if (aid is! String) {
              errors.add('Host $hk: allowedAuth entries must be strings');
              continue;
            }
            if (!contextByAuthId.containsKey(aid)) {
              errors.add('Host $hk: allowedAuth references unknown $aid');
            }
          }
        }
        final def = h['defaultAuth'];
        if (def != null) {
          if (def is! String) {
            errors.add('Host $hk: defaultAuth must be a string');
          } else {
            if (!contextByAuthId.containsKey(def)) {
              errors.add('Host $hk: defaultAuth $def is unknown');
            }
            final al =
                allowed is List<dynamic> ? allowed.whereType<String>().toList(growable: false) : <String>[];
            if (!al.contains(def)) {
              errors.add('Host $hk: defaultAuth must be listed in allowedAuth');
            }
          }
        }
        final headers = h['headers'];
        if (headers != null) {
          if (headers is! Map<String, dynamic>) {
            errors.add('Host $hk: headers must be a string-keyed object');
          } else {
            for (final e in headers.entries) {
              if (e.value is! String) {
                errors.add('Host $hk: headers.${e.key} must be a string');
              }
            }
          }
        }
      }
    }
  }

  for (final entry in contextByAuthId.entries) {
    final authId = entry.key;
    final c = entry.value.context;
    final token = c['token'];
    if (token is Map<String, dynamic>) {
      for (final src in normalizeExchangeSources(token)) {
        if (!contextByAuthId.containsKey(src)) {
          errors.add('$authId: token.exchangeSource references unknown context $src');
        }
      }
    }
  }

  final rootRaw = raw['rootCallbackAuthId'];
  if (rootRaw != null) {
    if (rootRaw is! String || rootRaw.trim().isEmpty) {
      errors.add('rootCallbackAuthId must be a non-empty string when set');
    } else {
      final root = rootRaw.trim();
      if (!contextByAuthId.containsKey(root)) {
        errors.add('rootCallbackAuthId: unknown auth id $root');
      }
    }
  }

  if (errors.isNotEmpty) throw ConfigValidationError(errors);

  return ResolvedMorphConfig(
    config: raw,
    contextByAuthId: contextByAuthId,
    contextsByProvider: contextsByProvider,
    hostByKey: hostByKey,
  );
}
