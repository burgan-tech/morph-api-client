const STATE_PREFIX = 'morph1.';

/** Encode authId into OAuth state parameter (URL-safe base64). */
export function encodeOAuthState(authId: string): string {
  const payload = JSON.stringify({ a: authId, n: crypto.randomUUID() });
  const b64 = btoa(payload);
  return `${STATE_PREFIX}${b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`;
}

/** Decode authId from OAuth state. Returns null if state format is unrecognized. */
export function decodeOAuthState(state: string): { authId: string } | null {
  if (!state.startsWith(STATE_PREFIX)) return null;
  try {
    let b = state.slice(STATE_PREFIX.length).replace(/-/g, '+').replace(/_/g, '/');
    while (b.length % 4) b += '=';
    const o = JSON.parse(atob(b)) as { a?: unknown };
    if (typeof o.a === 'string' && o.a.includes('/')) return { authId: o.a };
  } catch {
    /* ignore */
  }
  return null;
}
