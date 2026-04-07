import type { ResolvedMorphConfig } from '@morph/core';

export function listAuthIdsForProvider(providerKey: string, resolved: ResolvedMorphConfig): string[] {
  const ctxs = resolved.contextsByProvider.get(providerKey) ?? [];
  const p = resolved.config.providers.find((x) => x.key === providerKey);
  if (!p) return [];
  return ctxs.map((c) => `${p.key}/${c.key}`);
}
