import type {
  AuthPlugin,
  AuthPluginFactory,
  MorphOptions,
} from '@morph/core';
import { TokenLifecycle } from './tokens/tokenLifecycle.js';

export function createOAuth2Plugin(resolved: Parameters<AuthPluginFactory>[0], options: MorphOptions, variables?: Record<string, string>): AuthPlugin {
  return new TokenLifecycle(resolved, options, variables ?? options.variables ?? {}, options.onLog);
}

export const oauth2Plugin: AuthPluginFactory = (resolved, options, variables) => {
  return new TokenLifecycle(resolved, options, variables, options.onLog);
};

export { TokenLifecycle } from './tokens/tokenLifecycle.js';
export { TokenVault } from './tokens/tokenVault.js';

export { buildOAuth2AuthorizationUrl } from './util/oauthAuthorize.js';
export { stripOAuthReturnSearchParams, cleanOAuthReturnFromBrowser } from './util/oauthReturn.js';
export { encodeOAuthState, decodeOAuthState } from './util/oauthState.js';
export { normalizeLoopbackOrigin } from './util/normalizeOrigin.js';
