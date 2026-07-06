import { parseDurationMs } from '../util/duration.js';
import { resolveEndpoint } from '../util/url.js';
import type { AuthContextConfig, NetworkPolicy, ProviderConfig } from '@morph/core';
import { TokenEndpointError } from '@morph/core';
import { interpolateRecord, interpolateString } from '../util/interpolate.js';

export interface OAuthTokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
  token_type?: string;
}

function mergeHeaders(
  provider: ProviderConfig,
  ctx: AuthContextConfig,
  variables: Record<string, string>,
): Record<string, string> {
  const base = interpolateRecord(provider.headers, variables) ?? {};
  const extra = interpolateRecord(ctx.headers, variables, { key: ctx.key }) ?? {};
  return { ...base, ...extra };
}

function policyFor(provider: ProviderConfig, ctx: AuthContextConfig): NetworkPolicy | undefined {
  return ctx.networkPolicy ?? provider.networkPolicy;
}

/** Executes a POST to the token endpoint with retries, reading policy and content-type from provider/ctx. */
export async function postTokenRequest(
  url: string,
  body: Record<string, string>,
  headers: Record<string, string>,
  provider: ProviderConfig,
  ctx: AuthContextConfig,
  log?: (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void,
): Promise<OAuthTokenResponse> {

  const contentType = provider.contentType ?? 'application/x-www-form-urlencoded';
  const isJson = contentType === 'application/json';
  
  const policy = policyFor(provider, ctx);
  const timeoutMs = parseDurationMs(policy?.timeout, 30_000);
  const retries = policy?.retry?.count ?? 0;
  const delayMs = parseDurationMs(policy?.retry?.delay, 200);

  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ac = new AbortController();
    const signal = ac.signal;
    const timer = setTimeout(() => ac.abort(), timeoutMs);
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': contentType,
          ...headers,
        },
        body: isJson ? JSON.stringify(body) : new URLSearchParams(body),
        signal,
      });
      clearTimeout(timer);
      const text = await res.text();
      let json: unknown;
      try {
        json = JSON.parse(text);
      } catch {
        json = { raw: text };
      }
      if (!res.ok) {
        log?.('warn', `Token endpoint HTTP ${res.status}`, undefined, { url, json });
        throw new TokenEndpointError(res.status, text);
      }
      return json as OAuthTokenResponse;
    } catch (e) {
      clearTimeout(timer);
      // Never retry successful HTTP responses that failed validation (4xx/5xx body).
      // Authorization codes are single-use — retries can cause "Code not valid".
      if (e instanceof TokenEndpointError) {
        throw e;
      }
      lastErr = e;
      if (attempt < retries) await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  throw lastErr;
}

/** Resolve token (or token-exchange) URL; `endpoint` strings support `$variable` interpolation. */
export function tokenUrl(
  tokenHttpBase: string,
  ctx: AuthContextConfig,
  useExchangeEndpoint: boolean,
  variables: Record<string, string>,
): string {
  const epRaw = useExchangeEndpoint && ctx.token.exchangeEndpoint
    ? ctx.token.exchangeEndpoint
    : ctx.token.endpoint;
  const ep = interpolateString(epRaw.trim(), variables, { key: ctx.key });
  return resolveEndpoint(tokenHttpBase, ep);
}

export async function buildClientAuthFields(
  authId: string,
  ctx: AuthContextConfig,
  variables: Record<string, string>,
  options: { onClientJwtAssertion?: (authId: string) => Promise<string | null> },
): Promise<Record<string, string>> {
  const clientId = ctx.clientId ? interpolateString(ctx.clientId, variables, { key: ctx.key }) : '';
  const out: Record<string, string> = { client_id: clientId };
  const auth = ctx.clientAuth ?? 'client_secret_post';
  if (auth === 'private_key_jwt') {
    const assertion =
      (options.onClientJwtAssertion && (await options.onClientJwtAssertion(authId))) ?? null;
    if (assertion) {
      out.client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';
      out.client_assertion = assertion;
      return out;
    }
  }
  if (ctx.clientSecret) {
    out.client_secret = interpolateString(ctx.clientSecret, variables, { key: ctx.key });
  }
  return out;
}

export { mergeHeaders };
