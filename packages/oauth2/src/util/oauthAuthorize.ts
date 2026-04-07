import { resolveEndpoint } from './url.js';

/** Build an OAuth 2.0 authorization endpoint URL (browser redirect). */
export function buildOAuth2AuthorizationUrl(opts: {
  /** Provider `baseUrl` from config. */
  baseUrl: string;
  /** Context `authorization.endpoint` (path or absolute URL). */
  authorizationPath: string;
  clientId: string;
  redirectUri: string;
  scopes?: string[];
  /** Default `code`. */
  responseType?: string;
  /** Provider-specific query keys, e.g. Google `access_type`, `prompt`. */
  extraParams?: Record<string, string>;
  state: string;
}): string {
  const u = resolveEndpoint(opts.baseUrl, opts.authorizationPath);
  const params = new URLSearchParams();
  params.set('client_id', opts.clientId);
  params.set('redirect_uri', opts.redirectUri);
  params.set('response_type', opts.responseType ?? 'code');
  if (opts.scopes?.length) params.set('scope', opts.scopes.join(' '));
  params.set('state', opts.state);
  for (const [k, v] of Object.entries(opts.extraParams ?? {})) {
    if (v !== undefined && v !== '') params.set(k, v);
  }
  return `${u}?${params.toString()}`;
}
