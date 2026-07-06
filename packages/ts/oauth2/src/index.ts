import type {
  AuthPlugin,
  DelegateMetadata,
  LogoutReason,
  MorphCallbacks,
  MorphPlugin,
  ResolvedMorphConfig,
  StorageProvider,
  TokenExchangeGrant,
  TokenSet,
} from '@morph/core';
import { TokenLifecycle } from './tokens/tokenLifecycle.js';
import type { OAuth2TokenOptions } from './tokens/oauth2TokenOptions.js';

export type { OAuth2TokenOptions } from './tokens/oauth2TokenOptions.js';

export type LogFn = (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;

/**
 * Inputs handed to a custom {@link AuthPluginFactory} so it can build a tailored
 * {@link AuthPlugin} (typically by extending {@link TokenLifecycle}).
 */
export interface AuthPluginFactoryDeps {
  resolved: ResolvedMorphConfig;
  tokenOpts: OAuth2TokenOptions;
  variables: Record<string, string>;
  storage: StorageProvider;
  log?: LogFn;
}

/**
 * Build a custom {@link AuthPlugin} for {@link oauth2Plugin}. When omitted,
 * the default {@link TokenLifecycle} is used.
 */
export type AuthPluginFactory = (deps: AuthPluginFactoryDeps) => AuthPlugin;

export interface OAuth2PluginOptions {
  storage?: StorageProvider | MorphPlugin;
  logger?: MorphPlugin | LogFn;
  variables?: Record<string, string>;
  callbacks?: Partial<MorphCallbacks>;
  onTokenExchange?: (grant: TokenExchangeGrant) => Promise<TokenSet | null>;
  onClientJwtAssertion?: (authId: string) => Promise<string | null>;
  autoAcquireNonInteractive?: boolean;
  /**
   * Provide a custom {@link AuthPlugin} implementation. Called once during install
   * with the resolved config, token options, variables, storage, and log function.
   * When omitted, the default {@link TokenLifecycle} is instantiated.
   */
  authPlugin?: AuthPluginFactory;
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

      const variables = ctx.variables;
      const callbacks: MorphCallbacks = {
        onAuthRequired: opts?.callbacks?.onAuthRequired ?? defaultOnAuthRequired,
        onLogout: opts?.callbacks?.onLogout ?? defaultOnLogout,
        onTokenChange: opts?.callbacks?.onTokenChange,
        onCustomGrant: opts?.callbacks?.onCustomGrant,
      };
      const tokenOpts: OAuth2TokenOptions = {
        callbacks,
        variables,
        onTokenExchange: opts?.onTokenExchange,
        onClientJwtAssertion: opts?.onClientJwtAssertion,
        autoAcquireNonInteractive: opts?.autoAcquireNonInteractive,
        onLog: log,
      };
      const auth = opts?.authPlugin
        ? opts.authPlugin({ resolved: ctx.resolved, tokenOpts, variables, storage, log })
        : new TokenLifecycle(ctx.resolved, tokenOpts, variables, tokenOpts.onLog, storage);
      ctx.provideAuth(auth);
    },
  };
}

export { TokenLifecycle } from './tokens/tokenLifecycle.js';
export { TokenVault } from './tokens/tokenVault.js';

// Building blocks for hosts that provide a custom AuthPlugin (see
// AuthPluginFactory). These are the internal helpers TokenLifecycle is built
// from — exporting them lets a host-owned lifecycle (e.g. the
// vnext-client-workflow-manager sample's TokenManagerLifecycle) compile
// without duplicating them.
export { buildClientAuthFields, mergeHeaders, postTokenRequest } from './oauth/tokenHttp.js';
export type { OAuthTokenResponse } from './oauth/tokenHttp.js';
export { computeExpiresAt, isExpired } from './util/expiry.js';
export { parseDurationMs } from './util/duration.js';
export { resolveEndpoint } from './util/url.js';
export { hasExchangeSources, normalizeExchangeSources } from './util/exchangeSources.js';
export { interpolateString } from './util/interpolate.js';
export { listAuthIdsForProvider } from './util/listAuthIds.js';

export type { AuthPlugin, ResolvedMorphConfig } from '@morph/core';

export { buildOAuth2AuthorizationUrl } from './util/oauthAuthorize.js';
export { stripOAuthReturnSearchParams, cleanOAuthReturnFromBrowser } from './util/oauthReturn.js';
export { encodeOAuthState, decodeOAuthState } from './util/oauthState.js';
export { normalizeLoopbackOrigin } from './util/normalizeOrigin.js';
