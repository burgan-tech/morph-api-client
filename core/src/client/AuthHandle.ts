import type { LogoutReason, TokenSet } from '../types.js';
import type { MorphRuntime } from '../runtime.js';
import { listAuthIdsForProvider } from '../config/validate.js';

export class AuthHandle {
  constructor(
    private readonly rt: MorphRuntime,
    readonly authId: string,
  ) {}

  async submitCode(code: string, opts?: { codeVerifier?: string; redirectUriOverride?: string }): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('submitCode requires a provider/context auth id');
    this.rt.assertAlive();
    await this.rt.tokens.submitCode(r.authId, r.ref, code, opts);
  }

  async acquireWithClientCredentials(): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('acquireWithClientCredentials requires a provider/context auth id');
    this.rt.assertAlive();
    await this.rt.tokens.acquireWithClientCredentials(r.authId, r.ref);
  }

  async exchangeToken(targetAuthId: string): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('exchangeToken requires a provider/context auth id as the source');
    this.rt.assertAlive();
    await this.rt.tokens.exchangeToken(r.authId, r.ref, targetAuthId);
  }

  async setTokens(tokens: TokenSet): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('setTokens requires a provider/context auth id');
    this.rt.assertAlive();
    await this.rt.tokens.setTokens(r.authId, r.ref, tokens);
  }

  async clearTokens(): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    this.rt.assertAlive();
    if (r.kind === 'context') {
      await this.rt.tokens.clearTokens(r.authId, r.ref);
      return;
    }
    const ids = listAuthIdsForProvider(r.providerKey, this.rt.resolved);
    for (const id of ids) {
      const ref = this.rt.resolved.contextByAuthId.get(id)!;
      await this.rt.tokens.clearTokens(id, ref);
    }
  }

  async logout(reason: LogoutReason = 'user_initiated'): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    this.rt.assertAlive();
    if (r.kind === 'context') {
      await this.rt.tokens.logout(r.authId, r.ref, reason);
      return;
    }
    await this.rt.tokens.logoutProvider(r.providerKey, reason);
  }

  async hasValidToken(): Promise<boolean> {
    const r = this.rt.parseAuthRef(this.authId);
    this.rt.assertAlive();
    if (r.kind === 'context') return this.rt.tokens.hasValidTokenContext(r.authId, r.ref);
    return this.rt.tokens.hasValidTokenProvider(r.providerKey);
  }

  async refreshTokens(): Promise<void> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('refreshTokens requires a provider/context auth id');
    this.rt.assertAlive();
    await this.rt.tokens.refreshTokensManual(r.authId, r.ref);
  }

  async peekTokens(): Promise<TokenSet | null> {
    const r = this.rt.parseAuthRef(this.authId);
    if (r.kind !== 'context') throw new Error('peekTokens requires a provider/context auth id');
    this.rt.assertAlive();
    return this.rt.tokens.loadTokens(r.authId, r.ref);
  }
}
