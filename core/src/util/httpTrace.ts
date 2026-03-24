/** Serialize request headers for traces; mask bearer-style credentials. */
export function redactedRequestHeaders(h: Headers): Record<string, string> {
  const o: Record<string, string> = {};
  h.forEach((v, k) => {
    if (k.toLowerCase() === 'authorization') {
      const parts = v.trim().split(/\s+/);
      o[k] = parts.length >= 2 ? `${parts[0]} <redacted>` : '<redacted>';
    } else {
      o[k] = v;
    }
  });
  return o;
}

export function responseHeadersRecord(res: Response): Record<string, string> {
  const o: Record<string, string> = {};
  res.headers.forEach((v, k) => {
    o[k.toLowerCase()] = v;
  });
  return o;
}

/** Parse body from a clone of `res` for tracing (does not consume the original body stream). */
export async function responseBodyForTrace(res: Response): Promise<unknown> {
  try {
    const text = await res.clone().text();
    const ct = res.headers.get('content-type') ?? '';
    if (ct.includes('application/json') && text.length) {
      try {
        return JSON.parse(text) as unknown;
      } catch {
        return text;
      }
    }
    return text.length ? text : null;
  } catch {
    return '<unreadable>';
  }
}
