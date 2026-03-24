import type { AuthContextConfig, HostConfig, MorphConfig, ProviderConfig } from '../types.js';
import { ConfigValidationError } from '../errors.js';
import { normalizeExchangeSources } from '../util/exchangeSources.js';

export type CtxRef = { provider: ProviderConfig; context: AuthContextConfig };

export interface ResolvedMorphConfig {
  config: MorphConfig;
  contextByAuthId: Map<string, CtxRef>;
  contextsByProvider: Map<string, AuthContextConfig[]>;
  hostByKey: Map<string, HostConfig>;
}

export function validateAndIndexConfig(raw: MorphConfig): ResolvedMorphConfig {
  const errors: string[] = [];
  if (!raw.providers?.length) errors.push('At least one provider is required');
  if (!raw.hosts?.length) errors.push('At least one host is required');

  const contextByAuthId = new Map<string, { provider: ProviderConfig; context: AuthContextConfig }>();
  const contextsByProvider = new Map<string, AuthContextConfig[]>();
  const providerKeys = new Set<string>();

  for (const p of raw.providers ?? []) {
    if (!p.key) errors.push('Provider missing key');
    if (providerKeys.has(p.key)) errors.push(`Duplicate provider key: ${p.key}`);
    providerKeys.add(p.key);
    if (p.type !== 'oauth2') errors.push(`Provider ${p.key}: only oauth2 is supported`);
    if (!p.baseUrl) errors.push(`Provider ${p.key}: baseUrl is required`);
    if (p.authorizationBrowserBaseUrl !== undefined && typeof p.authorizationBrowserBaseUrl !== 'string') {
      errors.push(`Provider ${p.key}: authorizationBrowserBaseUrl must be a string`);
    }
    if (p.tokenHttpBaseUrl !== undefined && typeof p.tokenHttpBaseUrl !== 'string') {
      errors.push(`Provider ${p.key}: tokenHttpBaseUrl must be a string`);
    }
    const ctxKeys = new Set<string>();
    for (const c of p.contexts ?? []) {
      if (!c.key) errors.push(`Provider ${p.key}: context missing key`);
      if (ctxKeys.has(c.key)) errors.push(`Provider ${p.key}: duplicate context key ${c.key}`);
      ctxKeys.add(c.key);
      if (!c.token?.endpoint) errors.push(`Provider ${p.key}/${c.key}: token.endpoint is required`);
      if (!c.tokenTypes?.access) errors.push(`Provider ${p.key}/${c.key}: tokenTypes.access is required`);
      const authId = `${p.key}/${c.key}`;
      if (contextByAuthId.has(authId)) errors.push(`Duplicate auth id ${authId}`);
      contextByAuthId.set(authId, { provider: p, context: c });
    }
    contextsByProvider.set(p.key, p.contexts ?? []);
  }

  const hostByKey = new Map<string, HostConfig>();
  const hostKeys = new Set<string>();
  for (const h of raw.hosts ?? []) {
    if (!h.key) errors.push('Host missing key');
    if (hostKeys.has(h.key)) errors.push(`Duplicate host key: ${h.key}`);
    hostKeys.add(h.key);
    hostByKey.set(h.key, h);
    if (!h.baseUrl) errors.push(`Host ${h.key}: baseUrl is required`);
    if (!h.allowedAuth?.length) errors.push(`Host ${h.key}: allowedAuth must be a non-empty array`);
    for (const aid of h.allowedAuth ?? []) {
      if (!contextByAuthId.has(aid)) errors.push(`Host ${h.key}: allowedAuth references unknown ${aid}`);
    }
    if (h.defaultAuth && !contextByAuthId.has(h.defaultAuth)) {
      errors.push(`Host ${h.key}: defaultAuth ${h.defaultAuth} is unknown`);
    }
    if (h.defaultAuth && !(h.allowedAuth ?? []).includes(h.defaultAuth)) {
      errors.push(`Host ${h.key}: defaultAuth must be listed in allowedAuth`);
    }
    if (h.headers !== undefined) {
      if (typeof h.headers !== 'object' || h.headers === null || Array.isArray(h.headers)) {
        errors.push(`Host ${h.key}: headers must be a string-keyed object`);
      } else {
        for (const [hk, hv] of Object.entries(h.headers)) {
          if (typeof hv !== 'string') errors.push(`Host ${h.key}: headers.${hk} must be a string`);
        }
      }
    }
  }

  for (const [authId, { context: c }] of contextByAuthId) {
    for (const src of normalizeExchangeSources(c.token)) {
      if (!contextByAuthId.has(src)) {
        errors.push(`${authId}: token.exchangeSource references unknown context ${src}`);
      }
    }
  }

  const rootCallback = raw.rootCallbackAuthId?.trim();
  if (raw.rootCallbackAuthId !== undefined) {
    if (typeof raw.rootCallbackAuthId !== 'string' || !rootCallback) {
      errors.push('rootCallbackAuthId must be a non-empty string when set');
    } else if (!contextByAuthId.has(rootCallback)) {
      errors.push(`rootCallbackAuthId: unknown auth id ${rootCallback}`);
    }
  }

  if (errors.length) throw new ConfigValidationError(errors);

  return { config: raw, contextByAuthId, contextsByProvider, hostByKey };
}

export function listAuthIdsForProvider(providerKey: string, resolved: ResolvedMorphConfig): string[] {
  const ctxs = resolved.contextsByProvider.get(providerKey) ?? [];
  const p = resolved.config.providers.find((x) => x.key === providerKey);
  if (!p) return [];
  return ctxs.map((c) => `${p.key}/${c.key}`);
}
