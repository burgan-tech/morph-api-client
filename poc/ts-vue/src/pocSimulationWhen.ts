import type { MorphClient } from '@morph/core';
import type { PocSimCondition } from './pocSimulation';

export type PocSimConditionEvalContext = {
  morph: MorphClient;
  isProviderEnvReady: (providerKey: string) => boolean;
  getProbe404: () => boolean;
};

export async function evalPocSimCondition(
  cond: PocSimCondition,
  ctx: PocSimConditionEvalContext,
): Promise<boolean> {
  switch (cond.type) {
    case 'ui_flag_probe_404':
      return ctx.getProbe404();
    case 'provider_env_ready':
      return ctx.isProviderEnvReady(cond.providerKey);
    case 'has_valid_token':
      return await ctx.morph.auth(cond.authId).hasValidToken();
    case 'all': {
      for (const c of cond.all) {
        if (!(await evalPocSimCondition(c, ctx))) return false;
      }
      return true;
    }
    default: {
      const _exhaustive: never = cond;
      return _exhaustive;
    }
  }
}
