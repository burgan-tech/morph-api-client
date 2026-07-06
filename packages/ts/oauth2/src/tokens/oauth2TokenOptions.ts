import type { MorphCallbacks, TokenExchangeGrant, TokenSet } from '@morph/core';

export interface OAuth2TokenOptions {
  callbacks: MorphCallbacks;
  variables: Record<string, string>;
  onTokenExchange?: (grant: TokenExchangeGrant) => Promise<TokenSet | null>;
  onClientJwtAssertion?: (authId: string) => Promise<string | null>;
  autoAcquireNonInteractive?: boolean;
  onLog?: (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;
}
