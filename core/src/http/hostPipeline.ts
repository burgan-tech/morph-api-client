import type {
  HostConfig,
  MorphOptions,
  MorphResponse,
} from '../types.js';
import type { ResolvedMorphConfig } from '../config/validate.js';
import type { TokenLifecycle } from '../tokens/tokenLifecycle.js';
import { interpolateRecord } from '../config/interpolate.js';
import { resolveEndpoint } from '../util/url.js';
import { parseDurationMs } from '../util/duration.js';
import { AuthError, InvalidAuthForHostError, MorphHttpError, UnknownContextError } from '../errors.js';
import { redactedRequestHeaders, responseBodyForTrace, responseHeadersRecord } from '../util/httpTrace.js';

type HostFetchInit = RequestInit & {
  auth?: string | string[];
  timeout?: string;
  sign?: boolean;
  encrypted?: boolean;
  _token?: string;
  _authId?: string;
};

export class HostPipeline {
  constructor(
    private readonly resolved: ResolvedMorphConfig,
    private readonly options: MorphOptions,
    private readonly variables: Record<string, string>,
    private readonly tokens: TokenLifecycle,
  ) {}

  // ── Public ────────────────────────────────────────────────────────────

  async hostFetch<T>(
    host: HostConfig,
    path: string,
    init: RequestInit & { auth?: string | string[]; timeout?: string; sign?: boolean; encrypted?: boolean },
  ): Promise<MorphResponse<T>> {
    const authList = this.normalizeAuthOption(host, init.auth);
    let lastErr: unknown;
    for (const authId of authList) {
      this.ensureAuthAllowed(host, authId);
      const ref = this.resolved.contextByAuthId.get(authId);
      if (!ref) throw new UnknownContextError(authId);
      try {
        const token = await this.tokens.resolveAccessToken(authId, ref, 'http');
        return await this.performFetch(host, path, { ...init, _token: token, _authId: authId });
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
  }

  // ── Private ───────────────────────────────────────────────────────────

  private ensureAuthAllowed(host: HostConfig, authId: string): void {
    if (!host.allowedAuth.includes(authId)) {
      throw new InvalidAuthForHostError(host.key, authId, host.allowedAuth);
    }
  }

  private normalizeAuthOption(host: HostConfig, auth?: string | string[]): string[] {
    if (auth === undefined) {
      if (!host.defaultAuth) throw new Error(`Host ${host.key} has no defaultAuth; pass { auth } on each request`);
      return [host.defaultAuth];
    }
    return Array.isArray(auth) ? auth : [auth];
  }

  private toFetchInit(init: HostFetchInit, headers: Headers, body: BodyInit | null | undefined, signal: AbortSignal): RequestInit {
    const { auth: _a, timeout: _to, sign: _s, encrypted: _e, _token: _tk, _authId: _ai, ...rest } = init;
    return { ...rest, headers, body, signal };
  }

  /** Single fetch attempt with timeout, trace emission, and abort cleanup. */
  private async fetchWithTrace(
    host: HostConfig, path: string, init: HostFetchInit & { _authId: string },
    url: string, headers: Headers, body: BodyInit | null | undefined, timeoutMs: number,
  ): Promise<Response> {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), timeoutMs);
    const t = performance.now();
    try {
      const res = await fetch(url, this.toFetchInit(init, headers, body, ac.signal));
      clearTimeout(timer);
      await this.emitTrace(host, path, init, url, headers, res, t);
      return res;
    } catch (e) {
      clearTimeout(timer);
      const msg = e instanceof Error ? e.message : String(e);
      await this.emitTrace(host, path, init, url, headers, null, t, msg);
      throw e instanceof Error ? e : new Error(msg);
    }
  }

  private async performFetch<T>(
    host: HostConfig,
    path: string,
    init: HostFetchInit & { _token: string; _authId: string },
  ): Promise<MorphResponse<T>> {
    const ref = this.resolved.contextByAuthId.get(init._authId)!;
    const headerCfg = ref.context.tokenTypes.access.header ?? { name: 'Authorization', scheme: 'Bearer' };
    const url = resolveEndpoint(host.baseUrl, path.startsWith('/') ? path : `/${path}`);
    const timeoutMs = parseDurationMs(init.timeout, 30_000);

    let body = init.body as string | undefined;
    if (init.body && typeof init.body !== 'string' && !(init.body instanceof FormData) && !(init.body instanceof Blob)) {
      body = JSON.stringify(init.body);
    }

    if (init.sign) {
      if (!this.options.onSignPayload || !body) throw new Error('sign: true requires a JSON body and onSignPayload');
      const sig = await this.options.onSignPayload(body, init._authId);
      init.headers = new Headers(init.headers);
      (init.headers as Headers).set('X-JWS-Signature', sig);
    }

    const headers = new Headers();
    const hostHeaders = interpolateRecord(host.headers, this.variables) ?? {};
    for (const [k, v] of Object.entries(hostHeaders)) headers.set(k, v);
    new Headers(init.headers).forEach((v, k) => headers.set(k, v));
    headers.set(headerCfg.name, `${headerCfg.scheme} ${init._token}`);

    let res = await this.fetchWithTrace(host, path, init, url, headers, body ?? init.body, timeoutMs);

    // 401 + refresh policy → attempt refresh then retry
    if (res.status === 401 && ref.context.recoveryPolicy?.onUnauthorized === 'refresh') {
      await this.tokens.handle401Recovery(init._authId, ref);
      const token2 = await this.tokens.resolveAccessToken(init._authId, ref, 'http');
      headers.set(headerCfg.name, `${headerCfg.scheme} ${token2}`);
      res = await this.fetchWithTrace(host, path, init, url, headers, body ?? init.body, timeoutMs);
    }

    // 401 + delegate policy → notify app, throw
    if (res.status === 401 && ref.context.recoveryPolicy?.onUnauthorized === 'delegate') {
      this.tokens.fireAuthRequired(init._authId, ref.context);
      throw new AuthError(init._authId, 'delegation_required');
    }

    let text = await res.text();
    if (init.encrypted) {
      if (!this.options.onDecryptResponse) throw new Error('encrypted: true requires onDecryptResponse');
      text = await this.options.onDecryptResponse(text, init._authId);
    }

    let parsed: unknown = text;
    const ct = res.headers.get('content-type') ?? '';
    if (ct.includes('application/json') && text.length) {
      try { parsed = JSON.parse(text); } catch { parsed = text; }
    }

    const headersOut: Record<string, string> = {};
    res.headers.forEach((v, k) => { headersOut[k.toLowerCase()] = v; });

    if (!res.ok) throw new MorphHttpError(res.status, path, parsed, init._authId);

    return { statusCode: res.status, headers: headersOut, body: parsed as T, resolvedAuth: init._authId, raw: res };
  }

  // ── Trace emission ────────────────────────────────────────────────────

  private async emitTrace(
    host: HostConfig, path: string, init: RequestInit & { _authId: string },
    url: string, reqHeaders: Headers, res: Response | null, startedAt: number, networkError?: string,
  ): Promise<void> {
    const cb = this.options.onHttpTrace;
    if (!cb) return;
    const method = String(init.method ?? 'GET').toUpperCase();
    const durationMs = Math.round(performance.now() - startedAt);
    const pathNorm = path.startsWith('/') ? path : `/${path}`;
    if (networkError !== undefined) {
      cb({ kind: 'host_http', hostKey: host.key, method, url, path: pathNorm, authId: init._authId,
        requestHeaders: redactedRequestHeaders(reqHeaders), statusCode: 0, responseHeaders: {}, responseBody: null, durationMs, networkError });
      return;
    }
    const r = res as Response;
    cb({ kind: 'host_http', hostKey: host.key, method, url, path: pathNorm, authId: init._authId,
      requestHeaders: redactedRequestHeaders(reqHeaders), statusCode: r.status,
      responseHeaders: responseHeadersRecord(r), responseBody: await responseBodyForTrace(r), durationMs });
  }
}
