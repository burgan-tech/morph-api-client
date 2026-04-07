import type {
  DelegateMetadata,
  LogoutReason,
  MorphCallbacks,
  MorphPlugin,
  StorageProvider,
  TokenExchangeGrant,
  TokenSet,
} from '@morph/core';
import { TokenLifecycle } from './tokens/tokenLifecycle.js';
import type { OAuth2TokenOptions } from './tokens/tokenLifecycle.js';

export type { OAuth2TokenOptions } from './tokens/tokenLifecycle.js';

export interface OAuth2PluginOptions {
  storage?: StorageProvider | MorphPlugin;
  variables?: Record<string, string>;
  callbacks?: Partial<MorphCallbacks>;
  onTokenExchange?: (grant: TokenExchangeGrant) => Promise<TokenSet | null>;
  onClientJwtAssertion?: (authId: string) => Promise<string | null>;
  autoAcquireNonInteractive?: boolean;
  onLog?: (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;
}

function defaultOnAuthRequired(authId: string, _metadata: DelegateMetadata): void {
  console.warn(`[morph] onAuthRequired: ${authId}`);
}

function defaultOnLogout(authId: string, reason: LogoutReason): void {
  console.info(`[morph] onLogout: ${authId} (${reason})`);
}

function isStoragePlugin(s: StorageProvider | MorphPlugin): s is MorphPlugin {
  return typeof s === 'object' && 'install' in s && typeof s.install === 'function';
}

export function oauth2Plugin(opts?: OAuth2PluginOptions): MorphPlugin {
  const storageOpt = opts?.storage;
  const hasInlineStoragePlugin = storageOpt && isStoragePlugin(storageOpt);
  const hasDirectStorage = storageOpt && !isStoragePlugin(storageOpt);

  return {
    name: '@morph/oauth2',
    provides: ['auth'],
    requires: (hasInlineStoragePlugin || hasDirectStorage) ? [] : ['storage'],
    install(ctx) {
      if (hasInlineStoragePlugin) {
        (storageOpt as MorphPlugin).install(ctx);
      }

      const storage = hasDirectStorage
        ? (storageOpt as StorageProvider)
        : ctx.options._resolvedStorage;

      if (!storage) throw new Error('OAuth2 plugin requires storage. Pass storage in options or add a storage plugin.');

      const variables = { ...ctx.variables, ...opts?.variables };
      const callbacks: MorphCallbacks = {
        onAuthRequired: opts?.callbacks?.onAuthRequired ?? defaultOnAuthRequired,
        onLogout: opts?.callbacks?.onLogout ?? defaultOnLogout,
        onTokenChange: opts?.callbacks?.onTokenChange,
      };
      const tokenOpts: OAuth2TokenOptions = {
        callbacks,
        variables,
        onTokenExchange: opts?.onTokenExchange,
        onClientJwtAssertion: opts?.onClientJwtAssertion,
        autoAcquireNonInteractive: opts?.autoAcquireNonInteractive,
        onLog: opts?.onLog ?? ctx.options.onLog,
      };
      const auth = new TokenLifecycle(ctx.resolved, tokenOpts, variables, tokenOpts.onLog, storage);
      ctx.provideAuth(auth);
    },
  };
}

export { TokenLifecycle } from './tokens/tokenLifecycle.js';
export { TokenVault } from './tokens/tokenVault.js';

export { buildOAuth2AuthorizationUrl } from './util/oauthAuthorize.js';
export { stripOAuthReturnSearchParams, cleanOAuthReturnFromBrowser } from './util/oauthReturn.js';
export { encodeOAuthState, decodeOAuthState } from './util/oauthState.js';
export { normalizeLoopbackOrigin } from './util/normalizeOrigin.js';
