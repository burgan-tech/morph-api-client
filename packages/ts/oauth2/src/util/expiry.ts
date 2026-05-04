import { decodeJwtPayload, getJwtExpirySeconds } from '@morph/core';
import { parseDurationMs } from './duration.js';

/**
 * Computes expiresAt (unix seconds) from token response and JWT.
 * Applies maxTtl cap from `iat` (or now) when configured.
 */
export function computeExpiresAt(
  accessToken: string,
  expiresIn: number | undefined,
  maxTtl?: string,
): number | undefined {
  const fromJwt = getJwtExpirySeconds(accessToken);
  const now = Math.floor(Date.now() / 1000);
  let exp = fromJwt;
  if (exp === undefined && expiresIn !== undefined) {
    exp = now + expiresIn;
  }
  if (exp === undefined) return undefined;
  if (maxTtl) {
    let iat: number | undefined;
    try {
      iat = decodeJwtPayload(accessToken).iat as number | undefined;
    } catch {
      iat = undefined;
    }
    const issued = typeof iat === 'number' ? iat : now;
    const cap = issued + Math.floor(parseDurationMs(maxTtl) / 1000);
    exp = Math.min(exp, cap);
  }
  return exp;
}

export function isExpired(expiresAt: number | undefined, skewSeconds: number): boolean {
  if (expiresAt === undefined) return false;
  const now = Math.floor(Date.now() / 1000);
  return now >= expiresAt - skewSeconds;
}
