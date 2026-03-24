export interface JwtPayload {
  sub?: string;
  act?: string;
  exp?: number;
  iat?: number;
  azp?: string;
  aud?: string | string[];
  [key: string]: unknown;
}

export function decodeJwtPayload(token: string): JwtPayload {
  const parts = token.split('.');
  if (parts.length < 2) throw new Error('Invalid JWT format');
  const payload = parts[1];
  const json = base64UrlDecode(payload);
  return JSON.parse(json) as JwtPayload;
}

export function getJwtExpirySeconds(token: string): number | undefined {
  try {
    const { exp } = decodeJwtPayload(token);
    return typeof exp === 'number' ? exp : undefined;
  } catch {
    return undefined;
  }
}

export function getJwtSubject(token: string, claim: string | undefined): string | undefined {
  if (!claim) return undefined;
  try {
    const p = decodeJwtPayload(token);
    const v = p[claim];
    return typeof v === 'string' ? v : undefined;
  } catch {
    return undefined;
  }
}

function base64UrlDecode(s: string): string {
  const pad = (4 - (s.length % 4)) % 4;
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat(pad);
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}
