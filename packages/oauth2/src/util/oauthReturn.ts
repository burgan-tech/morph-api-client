const OAUTH_RETURN_PARAMS = [
  'code',
  'state',
  'session_state',
  'iss',
  'scope',
  'error',
  'error_description',
] as const;

/** Returns `pathname`, optional `?query`, and `hash` with common OAuth return query params removed (browser `history` not updated). */
export function stripOAuthReturnSearchParams(href: string): string {
  const url = new URL(href);
  for (const k of OAUTH_RETURN_PARAMS) {
    url.searchParams.delete(k);
  }
  const qs = url.searchParams.toString();
  return qs ? `${url.pathname}?${qs}${url.hash}` : `${url.pathname}${url.hash}`;
}

/** Strip OAuth return params from the current browser URL and update history (no-op outside browser). */
export function cleanOAuthReturnFromBrowser(): void {
  if (typeof globalThis.window === 'undefined') return;
  const w = globalThis.window;
  w.history.replaceState({}, '', stripOAuthReturnSearchParams(w.location.href));
}
