import type { AuthContextConfig } from '../types.js';

/**
 * Normalizes `token.exchangeSource` to a non-empty auth id list.
 * Supports legacy single string or array (multiple subject-token sources for this context).
 */
export function normalizeExchangeSources(token: AuthContextConfig['token']): string[] {
  const ex = token.exchangeSource;
  if (ex === undefined || ex === null) return [];
  if (Array.isArray(ex)) return ex.map((s) => String(s).trim()).filter(Boolean);
  if (typeof ex === 'string' && ex.trim()) return [ex.trim()];
  return [];
}

export function hasExchangeSources(token: AuthContextConfig['token']): boolean {
  return normalizeExchangeSources(token).length > 0;
}
