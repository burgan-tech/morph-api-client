import type {
  AuthContextConfig,
  AuthPlugin,
  CtxRef,
  LogoutReason,
  ProviderConfig,
  StorageProvider,
  TokenExchangeGrant,
  TokenSet,
} from '@morph/core';
import type { ResolvedMorphConfig } from '@morph/core';
import { AuthError, UnknownContextError } from '@morph/core';
import type { OAuth2TokenOptions } from './oauth2TokenOptions.js';

export type { OAuth2TokenOptions } from './oauth2TokenOptions.js';
import { TokenVault } from './tokenVault.js';
import {
  buildClientAuthFields,
  mergeHeaders,
  postTokenRequest,
  tokenUrl,
} from '../oauth/tokenHttp.js';
import { computeExpiresAt, isExpired } from '../util/expiry.js';
import { parseDurationMs } from '../util/duration.js';
import { resolveEndpoint } from '../util/url.js';
import { hasExchangeSources, normalizeExchangeSources } from '../util/exchangeSources.js';
import { interpolateString } from '../util/interpolate.js';
import { listAuthIdsForProvider } from '../util/listAuthIds.js';

const TOKEN_EXCHANGE_GRANT = 'urn:ietf:params:oauth:grant-type:token-exchange';
const ACCESS_TOKEN_TYPE = 'urn:ietf:params:oauth:token-type:access_token';

export class TokenLifecycle implements AuthPlugin {
  readonly vault: TokenVault;
  private readonly locks = new Map<string, Promise<unknown>>();
  private readonly inflightSubmitCode = new Map<string, Promise<void>>();

  constructor(
    private readonly resolved: ResolvedMorphConfig,
    private readonly opts: OAuth2TokenOptions,
    private readonly variables: Record<string, string>,
    private readonly log: OAuth2TokenOptions['onLog'],
    storage: StorageProvider,
  ) {
    this.vault = new TokenVault(variables, storage);
  }

  dispose(): void {
    this.locks.clear();
    this.inflightSubmitCode.clear();
  }

  private doLog(level: 'debug' | 'info' | 'warn' | 'error', msg: string, err?: Error, ctx?: Record<string, unknown>): void {
    this.log?.(level, msg, err, ctx);
  }

  private withLock<T>(authId: string, fn: () => Promise<T>): Promise<T> {
    const prev = this.locks.get(authId) ?? Promise.resolve();
    const next = prev.then(() => fn());
    this.locks.set(authId, next.then(() => undefined, () => undefined));
    return next;
  }

  private providerTokenHttpBase(provider: ProviderConfig): string {
    const raw = provider.tokenHttpBaseUrl?.trim();
    if (raw && raw.length > 0) {
      const resolved = interpolateString(raw, this.variables).trim();
      if (resolved.length > 0) return resolved;
    }
    return interpolateString(provider.baseUrl.trim(), this.variables);
  }

  private oauthToSet(ctx: AuthContextConfig, r: { access_token: string; refresh_token?: string; expires_in?: number }, preserveRefresh?: string): TokenSet {
    const exp = computeExpiresAt(r.access_token, r.expires_in, ctx.tokenTypes.access.maxTtl);
    return { accessToken: r.access_token, refreshToken: r.refresh_token ?? preserveRefresh, expiresAt: exp };
  }

  private async persistAndNotify(authId: string, ref: CtxRef, set: TokenSet | null): Promise<void> {
    if (set) await this.vault.save(authId, ref.provider, ref.context, set);
    else await this.vault.clear(authId, ref.provider, ref.context);
    this.opts.callbacks.onTokenChange?.(authId, set);
  }

  async loadTokens(authId: string, ref: CtxRef): Promise<TokenSet | null> {
    return this.vault.load(authId, ref.provider, ref.context);
  }

  // ── Consolidated token grant ──────────────────────────────────────────

  private async executeGrant(
    authId: string,
    ref: CtxRef,
    grantType: string,
    extraFields: Record<string, string>,
    grantInfo: TokenExchangeGrant,
    preserveRefresh?: string,
  ): Promise<TokenSet> {
    const { provider, context: ctx } = ref;
    const useEx = grantType === TOKEN_EXCHANGE_GRANT && !!ctx.token.exchangeEndpoint;
    const url = tokenUrl(this.providerTokenHttpBase(provider), ctx, useEx, this.variables);
    const clientFields = await buildClientAuthFields(authId, ctx, this.variables, this.opts);
    const headers = mergeHeaders(provider, ctx, this.variables);
    const body: Record<string, string> = { ...clientFields, grant_type: grantType, ...extraFields };
    if (grantType !== 'authorization_code' && ctx.audience) {
      body.audience = interpolateString(ctx.audience, this.variables, { key: ctx.key });
    }
    if (ctx.scopes?.length) body.scope = ctx.scopes.join(' ');

    const custom = await this.opts.onTokenExchange?.(grantInfo);
    if (custom) return custom;

    const r = await postTokenRequest(url, body, headers, provider, ctx, this.log);
    return this.oauthToSet(ctx, r, preserveRefresh);
  }

  private executeRefresh(authId: string, ref: CtxRef, refreshToken: string): Promise<TokenSet> {
    const preserve = ref.context.refreshPolicy?.strategy === 'static' ? refreshToken : undefined;
    return this.executeGrant(authId, ref, 'refresh_token', { refresh_token: refreshToken },
      { type: 'refresh_token', authId, refreshToken }, preserve);
  }

  private async fetchClientCredentialsSet(
    authId: string,
    ref: CtxRef,
    grantType = 'client_credentials',
  ): Promise<TokenSet> {
    let extraFields: Record<string, string> = {};
    if (grantType !== 'client_credentials' && this.opts.callbacks.onCustomGrant) {
      extraFields = await this.opts.callbacks.onCustomGrant({
        authId,
        grantType,
        context: ref.context,
        variables: this.variables,
      }) ?? {};
    }
    return this.executeGrant(authId, ref, grantType, extraFields,
      { type: 'client_credentials', authId });
  }

  private executeTokenExchange(
    sourceAuthId: string, targetAuthId: string, targetRef: CtxRef, subjectToken: string,
  ): Promise<TokenSet> {
    return this.executeGrant(targetAuthId, targetRef, TOKEN_EXCHANGE_GRANT,
      { subject_token: subjectToken, subject_token_type: ACCESS_TOKEN_TYPE },
      { type: 'token_exchange', authId: targetAuthId, sourceAuthId, sourceToken: subjectToken });
  }

  // ── Public token operations ───────────────────────────────────────────

  async submitCode(
    authId: string, ref: CtxRef, code: string,
    opts?: { codeVerifier?: string; redirectUriOverride?: string },
  ): Promise<void> {
    const key = `${authId}:${code}`;
    const existing = this.inflightSubmitCode.get(key);
    if (existing) return existing;
    const done = (async () => {
      await this.withLock(authId, async () => {
        const { context: ctx } = ref;
        if (!ctx.authorization?.redirectUri) throw new Error('authorization.redirectUri is required for submitCode');
        const redirectUri =
          opts?.redirectUriOverride?.trim() && opts.redirectUriOverride.trim().length > 0
            ? opts.redirectUriOverride.trim()
            : interpolateString(ctx.authorization.redirectUri, this.variables, { key: ctx.key });
        const extra: Record<string, string> = { code, redirect_uri: redirectUri };
        if (opts?.codeVerifier) extra.code_verifier = opts.codeVerifier;
        const set = await this.executeGrant(authId, ref, 'authorization_code', extra,
          { type: 'authorization_code', authId, code, codeVerifier: opts?.codeVerifier });
        await this.persistAndNotify(authId, ref, set);
        this.doLog('info', 'Tokens stored (authorization_code)', undefined, { authId });
      });
    })().finally(() => { this.inflightSubmitCode.delete(key); });
    this.inflightSubmitCode.set(key, done);
    return done;
  }

  async acquireWithClientCredentials(authId: string, ref: CtxRef): Promise<void> {
    await this.withLock(authId, async () => {
      const grantType = ref.context.token.grantType ?? 'client_credentials';
      const set = await this.fetchClientCredentialsSet(authId, ref, grantType);
      await this.persistAndNotify(authId, ref, set);
      this.doLog('info', 'Client credentials token stored', undefined, { authId });
    });
  }

  async exchangeToken(sourceAuthId: string, sourceRef: CtxRef, targetAuthId: string): Promise<void> {
    const target = this.resolved.contextByAuthId.get(targetAuthId);
    if (!target) throw new UnknownContextError(targetAuthId);
    await this.withLock(targetAuthId, async () => {
      const srcAccess = await this.resolveAccessToken(sourceAuthId, sourceRef, 'http');
      const newSet = await this.executeTokenExchange(sourceAuthId, targetAuthId, target, srcAccess);
      await this.persistAndNotify(targetAuthId, target, newSet);
      this.doLog('info', 'Token exchange completed', undefined, { sourceAuthId, targetAuthId });
    });
  }

  async setTokens(authId: string, ref: CtxRef, tokens: TokenSet): Promise<void> {
    await this.withLock(authId, async () => {
      let exp = tokens.expiresAt;
      if (exp === undefined) exp = computeExpiresAt(tokens.accessToken, undefined, ref.context.tokenTypes.access.maxTtl);
      await this.persistAndNotify(authId, ref, { ...tokens, expiresAt: exp });
    });
  }

  async clearTokens(authId: string, ref: CtxRef): Promise<void> {
    await this.withLock(authId, async () => {
      await this.vault.clear(authId, ref.provider, ref.context);
      this.opts.callbacks.onTokenChange?.(authId, null);
    });
  }

  async logout(authId: string, ref: CtxRef, reason: LogoutReason): Promise<void> {
    const set = await this.loadTokens(authId, ref);
    const { provider, context: ctx } = ref;
    if (ctx.logout?.endpoint) {
      try {
        const url = resolveEndpoint(this.providerTokenHttpBase(provider), ctx.logout.endpoint);
        const clientFields = await buildClientAuthFields(authId, ctx, this.variables, this.opts);
        const headers = mergeHeaders(provider, ctx, this.variables);
        const body: Record<string, string> = { ...clientFields };
        if (set?.refreshToken) body.refresh_token = set.refreshToken;
        await postTokenRequest(url, body, headers, provider, ctx, this.log);
      } catch (e) {
        this.doLog('warn', 'Logout endpoint failed', e instanceof Error ? e : undefined, { authId });
      }
    }
    await this.clearTokens(authId, ref);
    this.opts.callbacks.onLogout(authId, reason);
  }

  async logoutProvider(providerKey: string, reason: LogoutReason): Promise<void> {
    const ids = listAuthIdsForProvider(providerKey, this.resolved);
    for (const id of ids) {
      const ref = this.resolved.contextByAuthId.get(id)!;
      await this.logout(id, ref, reason);
    }
  }

  async hasValidTokenContext(authId: string, ref: CtxRef): Promise<boolean> {
    try { await this.resolveAccessToken(authId, ref, 'probe'); return true; }
    catch { return false; }
  }

  async hasValidTokenProvider(providerKey: string): Promise<boolean> {
    const ids = listAuthIdsForProvider(providerKey, this.resolved);
    for (const id of ids) {
      const ref = this.resolved.contextByAuthId.get(id)!;
      if (await this.hasValidTokenContext(id, ref)) return true;
    }
    return false;
  }

  // ── Callbacks ─────────────────────────────────────────────────────────

  fireAuthRequired(authId: string, ctx: AuthContextConfig): void {
    const meta = ctx.delegateMetadata;
    if (!meta) {
      this.opts.callbacks.onAuthRequired(authId, { workflow: 'unknown', grantHint: 'unknown', interaction: 'interactive' });
      return;
    }
    this.opts.callbacks.onAuthRequired(authId, meta);
    if (this.opts.autoAcquireNonInteractive && meta.interaction === 'non-interactive') {
      const ref = this.resolved.contextByAuthId.get(authId);
      if (ref) {
        this.acquireWithClientCredentials(authId, ref).catch((e) => {
          this.doLog('warn', 'autoAcquireNonInteractive failed', e instanceof Error ? e : undefined, { authId });
        });
      }
    }
  }

  private emitRefreshFailCallbacks(ref: CtxRef, authId: string, mode: 'probe' | 'http'): void {
    if (mode !== 'http') return;
    if (ref.context.recoveryPolicy?.onRefreshFail === 'delegate') this.fireAuthRequired(authId, ref.context);
    this.opts.callbacks.onLogout?.(authId, 'refresh_failed');
  }

  // ── 401 recovery (called by HostPipeline) ─────────────────────────────

  async handle401Recovery(authId: string, ref: CtxRef): Promise<void> {
    await this.withLock(authId, async () => {
      const set = await this.loadTokens(authId, ref);
      if (set?.refreshToken) {
        try {
          const newSet = await this.executeRefresh(authId, ref, set.refreshToken);
          await this.persistAndNotify(authId, ref, newSet);
          this.doLog('info', 'Access token refreshed after 401', undefined, { authId });
        } catch {
          await this.vault.clear(authId, ref.provider, ref.context);
          this.opts.callbacks.onTokenChange?.(authId, null);
          this.emitRefreshFailCallbacks(ref, authId, 'http');
        }
      } else {
        this.fireAuthRequired(authId, ref.context);
      }
    });
  }

  // ── Token resolution (refresh → client_creds → exchange → fail) ───────

  async resolveAccessToken(authId: string, ref: CtxRef, mode: 'probe' | 'http'): Promise<string> {
    return this.withLock(authId, async () => {
      let set = await this.loadTokens(authId, ref);
      const skew = 30;
      let refreshBefore = ref.context.refreshPolicy?.refreshBeforeExpiry
        ? Math.ceil(parseDurationMs(ref.context.refreshPolicy.refreshBeforeExpiry) / 1000)
        : skew;

      if (!ref.context.refreshPolicy?.refreshBeforeExpiry && set?.expiresAt != null) {
        const ttlSec = set.expiresAt - Math.floor(Date.now() / 1000);
        if (ttlSec > 0 && ttlSec < refreshBefore) refreshBefore = Math.max(1, ttlSec - 5);
      }

      if (set && !isExpired(set.expiresAt, refreshBefore)) return set.accessToken;

      let recoveryEmitted = false;
      let deferredRefreshFail = false;

      if (set?.refreshToken) {
        try {
          const newSet = await this.executeRefresh(authId, ref, set.refreshToken);
          await this.persistAndNotify(authId, ref, newSet);
          this.doLog('info', 'Access token refreshed', undefined, { authId });
          return newSet.accessToken;
        } catch (e) {
          this.doLog('warn', 'Refresh failed', e instanceof Error ? e : undefined, { authId });
          await this.vault.clear(authId, ref.provider, ref.context);
          this.opts.callbacks.onTokenChange?.(authId, null);
          set = null;
          deferredRefreshFail = hasExchangeSources(ref.context.token);
          if (!deferredRefreshFail) {
            this.emitRefreshFailCallbacks(ref, authId, mode);
            recoveryEmitted = true;
          }
        }
      }

      if (set && isExpired(set.expiresAt, refreshBefore) && !set.refreshToken &&
          ref.context.delegateMetadata?.grantHint === 'client_credentials') {
        try {
          const newSet = await this.fetchClientCredentialsSet(authId, ref);
          await this.persistAndNotify(authId, ref, newSet);
          this.doLog('info', 'Access token renewed (client_credentials)', undefined, { authId });
          return newSet.accessToken;
        } catch (e) {
          this.doLog('warn', 'Client credentials re-acquire failed', e instanceof Error ? e : undefined, { authId });
        }
      }

      const exSrcs = normalizeExchangeSources(ref.context.token);
      if (exSrcs.length > 0) {
        let exchanged = false;
        for (const exSrc of exSrcs) {
          try {
            const srcRef = this.resolved.contextByAuthId.get(exSrc);
            if (!srcRef) throw new Error(`Invalid exchangeSource ${exSrc}`);
            const srcToken = await this.resolveAccessToken(exSrc, srcRef, mode);
            const newSet = await this.executeTokenExchange(exSrc, authId, ref, srcToken);
            await this.persistAndNotify(authId, ref, newSet);
            this.doLog('info', 'Access token issued (token_exchange)', undefined, { authId, exchangeSource: exSrc });
            deferredRefreshFail = false;
            exchanged = true;
            return newSet.accessToken;
          } catch (e) {
            this.doLog('warn', 'Auto token exchange failed', e instanceof Error ? e : undefined, { authId, exSrc });
          }
        }
        if (!exchanged && deferredRefreshFail) {
          this.emitRefreshFailCallbacks(ref, authId, mode);
          recoveryEmitted = true;
        }
      }

      if (mode === 'http' && ref.context.recoveryPolicy?.onRefreshFail === 'delegate') {
        if (!recoveryEmitted) this.fireAuthRequired(authId, ref.context);
        throw new AuthError(authId, 'delegation_required');
      }

      throw new AuthError(authId, set ? 'refresh_failed' : 'no_token');
    });
  }

  async refreshTokensManual(authId: string, ref: CtxRef): Promise<void> {
    await this.withLock(authId, async () => {
      const set = await this.loadTokens(authId, ref);
      if (set?.refreshToken) {
        try {
          const newSet = await this.executeRefresh(authId, ref, set.refreshToken);
          await this.persistAndNotify(authId, ref, newSet);
          this.doLog('info', 'Access token refreshed (manual)', undefined, { authId });
          return;
        } catch (e) {
          const exSrcs = normalizeExchangeSources(ref.context.token);
          for (const exSrc of exSrcs) {
            try {
              const srcRef = this.resolved.contextByAuthId.get(exSrc);
              if (!srcRef) throw new Error(`Invalid exchangeSource ${exSrc}`);
              const srcToken = await this.resolveAccessToken(exSrc, srcRef, 'http');
              const newSet = await this.executeTokenExchange(exSrc, authId, ref, srcToken);
              await this.persistAndNotify(authId, ref, newSet);
              this.doLog('info', 'Access token issued (manual: exchange after refresh fail)', undefined, { authId, exchangeSource: exSrc });
              return;
            } catch { /* try next source */ }
          }
          await this.vault.clear(authId, ref.provider, ref.context);
          this.opts.callbacks.onTokenChange?.(authId, null);
          this.emitRefreshFailCallbacks(ref, authId, 'http');
          throw e;
        }
      }
      if (ref.context.delegateMetadata?.grantHint === 'client_credentials') {
        const newSet = await this.fetchClientCredentialsSet(authId, ref);
        await this.persistAndNotify(authId, ref, newSet);
        this.doLog('info', 'Access token renewed (client_credentials, manual)', undefined, { authId });
        return;
      }
      throw new Error(`${authId}: no refresh token; use login or token exchange`);
    });
  }
}
