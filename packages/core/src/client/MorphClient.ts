import type { MorphConfig, MorphOptions, MorphProviderMeta, MorphTokenStatus, OAuthReturnResult } from '../types.js';
import { createRuntime, MorphRuntime } from '../runtime.js';
import { AuthHandle } from './AuthHandle.js';
import { HostClient } from './HostClient.js';

export class MorphClient {
  private readonly rt: MorphRuntime;

  static init(config: MorphConfig, options: MorphOptions): MorphClient {
    return new MorphClient(config, options);
  }

  private constructor(config: MorphConfig, options: MorphOptions) {
    this.rt = createRuntime(config, options);
  }

  host(key: string): HostClient {
    this.rt.assertAlive();
    return new HostClient(this.rt, this.rt.getHost(key));
  }

  auth(authId: string): AuthHandle {
    this.rt.assertAlive();
    // Validate id exists
    this.rt.parseAuthRef(authId);
    return new AuthHandle(this.rt, authId);
  }

  /** All configured contexts: vault snapshot + JWT decode. No refresh / network. */
  getTokenStatus(): Promise<MorphTokenStatus[]> {
    this.rt.assertAlive();
    return this.rt.getTokenStatus();
  }

  /** Sanitized provider + contexts (no secrets). */
  getProviderMeta(providerKey: string): MorphProviderMeta {
    this.rt.assertAlive();
    return this.rt.getProviderMeta(providerKey);
  }

  /**
   * Contexts that list `sourceAuthId` in `token.exchangeSource` (sorted).
   * Prefer {@link getExchangeSources} on the target context for dropdown UIs.
   */
  getExchangeTargets(sourceAuthId: string): string[] {
    this.rt.assertAlive();
    return this.rt.getExchangeTargets(sourceAuthId);
  }

  /**
   * `token.exchangeSource` for this context (string or array, normalized to ordered auth ids).
   * Build target-row UIs: dropdown of sources → exchange into this context.
   */
  getExchangeSources(targetAuthId: string): string[] {
    this.rt.assertAlive();
    return this.rt.getExchangeSources(targetAuthId);
  }

  /** `authorization_code` context: client credentials + `authorization` block resolvable via `variables`. */
  isAuthContextReady(authId: string): boolean {
    this.rt.assertAlive();
    return this.rt.isAuthContextReady(authId);
  }

  /** True when every `authorization_code` context on the provider is ready for authorize. */
  isProviderEnvReady(providerKey: string): boolean {
    this.rt.assertAlive();
    return this.rt.isProviderEnvReady(providerKey);
  }

  /** OAuth2 authorize redirect URL from config + `MorphOptions.variables`. */
  getAuthorizationUrl(authId: string, opts?: { state?: string }): string {
    this.rt.assertAlive();
    return this.rt.getAuthorizationUrl(authId, opts);
  }

  /** Complete an OAuth callback by decoding state and exchanging the code. Works from any route. */
  completeOAuthCallback(params: {
    code?: string | null;
    state?: string | null;
    error?: string | null;
    errorDescription?: string | null;
  }): Promise<OAuthReturnResult> {
    this.rt.assertAlive();
    return this.rt.completeOAuthCallback(params);
  }

  /**
   * If the current browser URL is the app root with `?code=` or `?error=`, completes OAuth via
   * {@link completeOAuthCallback}. Otherwise returns `{ status: 'none' }`. For arbitrary callback routes, call
   * {@link completeOAuthCallback} with URL params directly (preferred).
   */
  completeOAuthReturn(): Promise<OAuthReturnResult> {
    this.rt.assertAlive();
    return this.rt.completeOAuthReturn();
  }

  dispose(): void {
    this.rt.dispose();
  }
}
