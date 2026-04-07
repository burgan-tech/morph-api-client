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

export type LogFn = (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;

export interface OAuth2PluginOptions {
  storage?: StorageProvider | MorphPlugin;
  logger?: MorphPlugin | LogFn;
  variables?: Record<string, string>;
  callbacks?: Partial<MorphCallbacks>;
  onTokenExchange?: (grant: TokenExchangeGrant) => Promise<TokenSet | null>;
  onClientJwtAssertion?: (authId: string) => Promise<string | null>;
  autoAcquireNonInteractive?: boolean;
}

function isMorphPlugin(s: unknown): s is MorphPlugin {
  return typeof s === 'object' && s !== null && 'install' in s && typeof (s as MorphPlugin).install === 'function';
}

function resolveLogFn(logger: MorphPlugin | LogFn | undefined, ctx: { options: { onLog?: LogFn } }): LogFn | undefined {
  if (!logger) return ctx.options.onLog;
  if (typeof logger === 'function') return logger;
  if (isMorphPlugin(logger)) {
    logger.install(ctx as Parameters<MorphPlugin['install']>[0]);
    return ctx.options.onLog;
  }
  return ctx.options.onLog;
}

export function oauth2Plugin(opts?: OAuth2PluginOptions): MorphPlugin {
  const storageOpt = opts?.storage;
  const hasInlineStoragePlugin = storageOpt && isMorphPlugin(storageOpt);
  const hasDirectStorage = storageOpt && !isMorphPlugin(storageOpt);

  return {
    name: '@morph/oauth2',
    provides: ['auth'],
    requires: (hasInlineStoragePlugin || hasDirectStorage) ? [] : ['storage'],
    install(ctx) {
      const log = resolveLogFn(opts?.logger, ctx);

      if (hasInlineStoragePlugin) {
        (storageOpt as MorphPlugin).install(ctx);
      }

      const storage = hasDirectStorage
        ? (storageOpt as StorageProvider)
        : ctx.options._resolvedStorage;

      if (!storage) throw new Error('OAuth2 plugin requires storage. Pass storage in options or add a storage plugin.');

      const defaultOnAuthRequired = (authId: string, _metadata: DelegateMetadata): void => {
        log?.('warn', `onAuthRequired: ${authId}`, undefined, { authId });
      };
      const defaultOnLogout = (authId: string, reason: LogoutReason): void => {
        log?.('info', `onLogout: ${authId} (${reason})`, undefined, { authId, reason });
      };

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
        onLog: log,
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
