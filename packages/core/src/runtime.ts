import type {
  AuthPlugin,
  AuthPluginFactory,
  HostConfig,
  MorphConfig,
  MorphContextMeta,
  MorphOptions,
  MorphProviderMeta,
  MorphTokenStatus,
  OAuthReturnResult,
} from './types.js';
import type { ResolvedMorphConfig, CtxRef } from './config/validate.js';
import { validateAndIndexConfig } from './config/validate.js';
import { interpolateString } from './config/interpolate.js';
import { buildOAuth2AuthorizationUrl } from './util/oauthAuthorize.js';
import { UnknownContextError, UnknownHostError, UnknownProviderError } from './errors.js';
import { decodeJwtPayload } from './util/jwt.js';
import { normalizeExchangeSources } from './util/exchangeSources.js';
import { stripOAuthReturnSearchParams } from './util/oauthReturn.js';
import { encodeOAuthState, decodeOAuthState } from './util/oauthState.js';
import { HostPipeline } from './http/hostPipeline.js';

function resolveAuthPlugin(auth: AuthPlugin | AuthPluginFactory, resolved: ResolvedMorphConfig, options: MorphOptions, variables: Record<string, string>): AuthPlugin {
  if (typeof auth === 'function') return auth(resolved, options, variables);
  return auth;
}

export class MorphRuntime {
  readonly tokens: AuthPlugin;
  readonly http: HostPipeline;
  private disposed = false;

  constructor(
    readonly resolved: ResolvedMorphConfig,
    readonly options: MorphOptions,
    private readonly variables: Record<string, string>,
  ) {
    this.tokens = resolveAuthPlugin(options.auth, resolved, options, variables);
    this.http = new HostPipeline(resolved, options, variables, this.tokens);
  }

  log(level: Parameters<NonNullable<MorphOptions['onLog']>>[0], message: string, err?: Error, ctx?: Record<string, unknown>): void {
    this.options.onLog?.(level, message, err, ctx);
  }

  dispose(): void {
    this.disposed = true;
    this.tokens.dispose();
  }

  assertAlive(): void {
    if (this.disposed) throw new Error('MorphClient has been disposed');
  }

  // ── Config queries ────────────────────────────────────────────────────

  getHost(key: string): HostConfig {
    const h = this.resolved.hostByKey.get(key);
    if (!h) throw new UnknownHostError(key);
    return h;
  }

  parseAuthRef(authId: string): { kind: 'context'; ref: CtxRef; authId: string } | { kind: 'provider'; providerKey: string } {
    const parts = authId.split('/');
    if (parts.length === 2 && parts[0] && parts[1]) {
      const ref = this.resolved.contextByAuthId.get(authId);
      if (!ref) throw new UnknownContextError(authId);
      return { kind: 'context', ref, authId };
    }
    if (parts.length === 1 && parts[0]) {
      const pk = parts[0];
      if (!this.resolved.contextsByProvider.has(pk)) throw new UnknownContextError(authId);
      return { kind: 'provider', providerKey: pk };
    }
    throw new UnknownContextError(authId);
  }

  isAuthContextReady(authId: string): boolean {
    try {
      const r = this.parseAuthRef(authId);
      if (r.kind !== 'context') return false;
      const c = r.ref.context;
      if (c.delegateMetadata?.grantHint !== 'authorization_code') return false;
      if (!c.clientId?.trim() || !c.clientSecret?.trim()) return false;
      try {
        if (!interpolateString(c.clientId.trim(), this.variables).trim()) return false;
        if (!interpolateString(c.clientSecret.trim(), this.variables).trim()) return false;
      } catch { return false; }
      const authz = c.authorization;
      if (!authz?.endpoint?.trim() || !authz.redirectUri?.trim()) return false;
      try { interpolateString(authz.redirectUri.trim(), this.variables); }
      catch { return false; }
      return true;
    } catch { return false; }
  }

  isProviderEnvReady(providerKey: string): boolean {
    try {
      const ctxs = this.resolved.contextsByProvider.get(providerKey) ?? [];
      for (const c of ctxs) {
        if (c.delegateMetadata?.grantHint === 'authorization_code') {
          if (!this.isAuthContextReady(`${providerKey}/${c.key}`)) return false;
        }
      }
      return true;
    } catch { return false; }
  }

  // ── Token status (read-only, no network) ──────────────────────────────

  async getTokenStatus(): Promise<MorphTokenStatus[]> {
    this.assertAlive();
    const ids = [...this.resolved.contextByAuthId.keys()].sort();
    const out: MorphTokenStatus[] = [];
    const now = Math.floor(Date.now() / 1000);
    for (const authId of ids) {
      const ref = this.resolved.contextByAuthId.get(authId)!;
      const set = await this.tokens.loadTokens(authId, ref);
      const hasAccessToken = Boolean(set?.accessToken);
      const exp = set?.expiresAt;
      const row: MorphTokenStatus = {
        authId,
        providerKey: ref.provider.key,
        contextKey: ref.context.key,
        grantHint: ref.context.delegateMetadata?.grantHint,
        hasAccessToken,
        hasRefreshToken: Boolean(set?.refreshToken),
        accessLikelyValid: hasAccessToken && (exp === undefined || exp > now),
        expiresAt: exp,
      };
      const accessFormat = ref.context.tokenTypes.access?.format ?? 'jwt';
      const refreshFormat = ref.context.tokenTypes.refresh?.format ?? 'jwt';
      if (set?.accessToken && accessFormat === 'jwt') {
        try {
          const payload = decodeJwtPayload(set.accessToken);
          row.jwtExp = typeof payload.exp === 'number' ? payload.exp : undefined;
          row.claims = { ...payload } as Record<string, unknown>;
        } catch (e) { row.decodeError = e instanceof Error ? e.message : String(e); }
      }
      if (set?.refreshToken && refreshFormat === 'jwt' && set.refreshToken.split('.').length >= 2) {
        try {
          const rp = decodeJwtPayload(set.refreshToken);
          row.refreshJwtExp = typeof rp.exp === 'number' ? rp.exp : undefined;
          row.refreshClaims = { ...rp } as Record<string, unknown>;
        } catch (e) { row.refreshDecodeError = e instanceof Error ? e.message : String(e); }
      }
      out.push(row);
    }
    return out;
  }

  getProviderMeta(providerKey: string): MorphProviderMeta {
    this.assertAlive();
    const p = this.resolved.config.providers.find((x) => x.key === providerKey);
    if (!p) throw new UnknownProviderError(providerKey);
    const contexts: MorphContextMeta[] = (p.contexts ?? []).map((c) => ({
      key: c.key, authId: `${p.key}/${c.key}`, clientId: c.clientId, clientAuth: c.clientAuth,
      audience: c.audience, identity: c.identity, authorization: c.authorization, token: c.token,
      logout: c.logout, scopes: c.scopes, pkce: c.pkce, refreshPolicy: c.refreshPolicy,
      recoveryPolicy: c.recoveryPolicy, delegateMetadata: c.delegateMetadata,
      sessionPolicy: c.sessionPolicy, networkPolicy: c.networkPolicy, headers: c.headers,
      tokenTypes: c.tokenTypes,
    }));
    return {
      key: p.key, type: p.type, baseUrl: p.baseUrl,
      authorizationBrowserBaseUrl: p.authorizationBrowserBaseUrl,
      tokenHttpBaseUrl: p.tokenHttpBaseUrl,
      networkPolicy: p.networkPolicy, headers: p.headers, contexts,
    };
  }

  getExchangeTargets(sourceAuthId: string): string[] {
    this.assertAlive();
    const parsed = this.parseAuthRef(sourceAuthId);
    if (parsed.kind !== 'context') throw new Error(`getExchangeTargets(${sourceAuthId}): expected provider/context`);
    const targets: string[] = [];
    for (const [authId, { context: c }] of this.resolved.contextByAuthId) {
      if (normalizeExchangeSources(c.token).includes(sourceAuthId)) targets.push(authId);
    }
    return targets.sort();
  }

  getExchangeSources(targetAuthId: string): string[] {
    this.assertAlive();
    const parsed = this.parseAuthRef(targetAuthId);
    if (parsed.kind !== 'context') throw new Error(`getExchangeSources(${targetAuthId}): expected provider/context`);
    return normalizeExchangeSources(parsed.ref.context.token);
  }

  // ── OAuth flow ────────────────────────────────────────────────────────

  getAuthorizationUrl(authId: string, opts?: { state?: string }): string {
    this.assertAlive();
    if (!this.isAuthContextReady(authId)) {
      throw new Error(`${authId}: not ready for authorize`);
    }
    const r = this.parseAuthRef(authId);
    if (r.kind !== 'context') throw new UnknownContextError(authId);
    const { provider: p, context: c } = r.ref;
    const authz = c.authorization!;
    const redirectUri = interpolateString(authz.redirectUri!.trim(), this.variables);
    const clientId = interpolateString(c.clientId!.trim(), this.variables);
    const state = opts?.state ?? encodeOAuthState(authId);
    const browserBaseRaw = p.authorizationBrowserBaseUrl?.trim();
    const authorizeBase = browserBaseRaw && browserBaseRaw.length > 0
      ? interpolateString(browserBaseRaw, this.variables)
      : interpolateString(p.baseUrl.trim(), this.variables);
    return buildOAuth2AuthorizationUrl({
      baseUrl: authorizeBase,
      authorizationPath: interpolateString(authz.endpoint.trim(), this.variables),
      clientId, redirectUri, scopes: c.scopes,
      responseType: authz.responseType, extraParams: authz.extraParams, state,
    });
  }

  async completeOAuthCallback(params: {
    code?: string | null; state?: string | null;
    error?: string | null; errorDescription?: string | null;
  }): Promise<OAuthReturnResult> {
    this.assertAlive();
    if (params.error) {
      return { status: 'oauth_error', message: `OAuth error: ${params.error}${params.errorDescription ? ` — ${params.errorDescription}` : ''}` };
    }
    if (!params.code) return { status: 'none' };

    const decoded = params.state ? decodeOAuthState(params.state) : null;
    if (decoded) {
      const ref = this.resolved.contextByAuthId.get(decoded.authId);
      if (!ref) return { status: 'error', message: `Unknown auth id from state: ${decoded.authId}` };
      try {
        await this.tokens.submitCode(decoded.authId, ref, params.code);
        return { status: 'success', message: `Signed in (${decoded.authId}).` };
      } catch (e) { return { status: 'error', message: e instanceof Error ? e.message : String(e) }; }
    }

    const rootId = this.resolved.config.rootCallbackAuthId?.trim();
    if (!rootId) return { status: 'error', message: 'Missing or invalid OAuth state and no rootCallbackAuthId configured.' };
    const ref = this.resolved.contextByAuthId.get(rootId);
    if (!ref) return { status: 'error', message: `Unknown rootCallbackAuthId: ${rootId}` };
    const redirectOverride = typeof globalThis.window !== 'undefined' ? `${globalThis.window.location.origin}/` : undefined;
    try {
      await this.tokens.submitCode(rootId, ref, params.code, { redirectUriOverride: redirectOverride });
      return { status: 'success', message: 'Authorization code exchanged.' };
    } catch (e) { return { status: 'error', message: e instanceof Error ? e.message : String(e) }; }
  }

  async completeOAuthReturn(): Promise<OAuthReturnResult> {
    this.assertAlive();
    if (typeof globalThis.window === 'undefined') return { status: 'none' };
    const w = globalThis.window;
    const path = w.location.pathname;
    if (path !== '/' && path !== '') return { status: 'none' };
    const p = new URLSearchParams(w.location.search);
    const result = await this.completeOAuthCallback({
      code: p.get('code'), state: p.get('state'),
      error: p.get('error'), errorDescription: p.get('error_description'),
    });
    if (result.status !== 'none') w.history.replaceState({}, '', stripOAuthReturnSearchParams(w.location.href));
    return result;
  }

  async completeAuthorizationReturnFromUrl(): Promise<OAuthReturnResult> {
    return this.completeOAuthReturn();
  }
}

export function createRuntime(config: MorphConfig, options: MorphOptions): MorphRuntime {
  const resolved = validateAndIndexConfig(config);
  return new MorphRuntime(resolved, options, options.variables ?? {});
}
