export type LogoutReason = 'user_initiated' | 'unauthorized' | 'refresh_failed' | 'session_expired';

export type InteractionMode = 'interactive' | 'non-interactive' | 'redirect';

export interface DelegateMetadata {
  workflow: string;
  grantHint: string;
  interaction: InteractionMode;
}

export interface NetworkPolicy {
  timeout?: string;
  retry?: { count?: number; delay?: string };
}

export interface TokenHeaderConfig {
  name: string;
  scheme: string;
}

export interface StorageConfig {
  scope: string;
  type: string;
  protection: string;
  key: string;
}

export interface TokenTypeConfig {
  header?: TokenHeaderConfig;
  expiryPolicy: string;
  maxTtl?: string;
  storage: StorageConfig;
}

export interface RecoveryPolicy {
  onUnauthorized?: string;
  onRefreshFail?: string;
}

export interface AuthContextConfig {
  key: string;
  clientId?: string;
  clientSecret?: string;
  clientAuth?: string;
  audience?: string;
  identity?: { subject?: string; actor?: string };
  authorization?: {
    endpoint: string;
    redirectUri?: string;
    /** OAuth authorize `response_type` (default `code`). */
    responseType?: string;
    /** Extra query parameters for the authorize request (provider-specific). */
    extraParams?: Record<string, string>;
  };
  token: {
    endpoint: string;
    exchangeEndpoint?: string;
    /**
     * Auth id(s) whose access token may be exchanged (RFC 8693) for this context's tokens.
     * Use an array when this context can be issued from more than one subject token.
     */
    exchangeSource?: string | string[];
  };
  logout?: { endpoint: string };
  scopes?: string[];
  pkce?: { codeChallengeMethod?: string };
  refreshPolicy?: { strategy?: string; refreshBeforeExpiry?: string };
  recoveryPolicy?: RecoveryPolicy;
  delegateMetadata?: DelegateMetadata;
  sessionPolicy?: Record<string, string>;
  networkPolicy?: NetworkPolicy;
  headers?: Record<string, string>;
  tokenTypes: Record<string, TokenTypeConfig>;
}

export interface ProviderConfig {
  key: string;
  type: 'oauth2';
  /** Canonical issuer / default base (supports `$variable` interpolation). Used when `tokenHttpBaseUrl` is unset or resolves empty after interpolation. */
  baseUrl: string;
  /**
   * If set (supports `$variable` interpolation), browser authorize redirects use this origin instead of `baseUrl`.
   * Use when `baseUrl` points at a same-origin dev proxy: the IdP login page must load from the real host so `/resources/...`
   * assets resolve.
   */
  authorizationBrowserBaseUrl?: string;
  /**
   * If set (supports `$variable` interpolation), token endpoint, refresh, token-exchange, and logout HTTP use this base
   * instead of `baseUrl`. Use for same-origin CORS proxies (e.g. Vite `/__keycloak`) while keeping `baseUrl` as the real issuer.
   */
  tokenHttpBaseUrl?: string;
  networkPolicy?: NetworkPolicy;
  headers?: Record<string, string>;
  contexts: AuthContextConfig[];
}

export interface HostConfig {
  key: string;
  baseUrl: string;
  /** Explicit list of provider/context ids allowed for this host */
  allowedAuth: string[];
  /** If set, used when a request omits `auth` */
  defaultAuth?: string;
  /**
   * Default headers for every request to this host (after `$variable` interpolation).
   * Per-request {@link HostRequestOptions.headers} override these for the same header name.
   */
  headers?: Record<string, string>;
}

export interface MorphConfig {
  providers: ProviderConfig[];
  hosts: HostConfig[];
  /**
   * When an IdP redirects to the app root (`/?code=…`) instead of a dedicated `/oauth/callback` route,
   * {@link MorphClient.completeOAuthReturn} exchanges the code for this `provider/context` auth id.
   */
  rootCallbackAuthId?: string;
}

/** Result of {@link MorphClient.completeOAuthReturn} and {@link MorphClient.completeOAuthCallback}. */
export type OAuthReturnStatus = 'none' | 'success' | 'oauth_error' | 'error';

export interface OAuthReturnResult {
  status: OAuthReturnStatus;
  message?: string;
}

/**
 * Safe provider/config snapshot for UIs and docs (no `clientSecret`).
 * From {@link MorphClient.getProviderMeta}.
 */
export interface MorphContextMeta {
  key: string;
  /** `providerKey/contextKey` */
  authId: string;
  clientId?: string;
  clientAuth?: string;
  audience?: string;
  identity?: AuthContextConfig['identity'];
  authorization?: AuthContextConfig['authorization'];
  token: AuthContextConfig['token'];
  logout?: AuthContextConfig['logout'];
  scopes?: string[];
  pkce?: AuthContextConfig['pkce'];
  refreshPolicy?: AuthContextConfig['refreshPolicy'];
  recoveryPolicy?: AuthContextConfig['recoveryPolicy'];
  delegateMetadata?: AuthContextConfig['delegateMetadata'];
  sessionPolicy?: AuthContextConfig['sessionPolicy'];
  networkPolicy?: AuthContextConfig['networkPolicy'];
  headers?: AuthContextConfig['headers'];
  tokenTypes: AuthContextConfig['tokenTypes'];
}

export interface MorphProviderMeta {
  key: string;
  type: 'oauth2';
  baseUrl: string;
  authorizationBrowserBaseUrl?: string;
  tokenHttpBaseUrl?: string;
  networkPolicy?: NetworkPolicy;
  headers?: Record<string, string>;
  contexts: MorphContextMeta[];
}

export interface TokenSet {
  accessToken: string;
  refreshToken?: string;
  /** Unix timestamp (seconds) */
  expiresAt?: number;
  metadata?: Record<string, unknown>;
}

/**
 * One configured context: vault snapshot + optional JWT decode.
 * From {@link MorphClient.getTokenStatus} — no network, no refresh, no `onAuthRequired`.
 */
export interface MorphTokenStatus {
  authId: string;
  providerKey: string;
  contextKey: string;
  /** Config `delegateMetadata.grantHint` when set (e.g. `client_credentials`, `authorization_code`). */
  grantHint?: string;
  hasAccessToken: boolean;
  hasRefreshToken: boolean;
  /** True when an access token exists and stored `expiresAt` (if present) is still in the future. */
  accessLikelyValid: boolean;
  /** Unix seconds from stored {@link TokenSet.expiresAt} (SDK-computed). */
  expiresAt?: number;
  /** JWT `exp` claim when the access token decodes as a JWT. */
  jwtExp?: number;
  /** Access token JWT payload (debug only; treat as sensitive). */
  claims?: Record<string, unknown>;
  /** When `hasAccessToken` but the string is not a decodable JWT. */
  decodeError?: string;
  /** Refresh token JWT payload when decodable (many providers use opaque refresh strings). */
  refreshClaims?: Record<string, unknown>;
  /** JWT `exp` on refresh token when decodable. */
  refreshJwtExp?: number;
  /** Refresh string looked like JWT but payload decode failed. */
  refreshDecodeError?: string;
}

export interface StorageProvider {
  read(key: string, storageConfig: StorageConfig): Promise<string | null>;
  write(key: string, value: string, storageConfig: StorageConfig): Promise<void>;
  delete(key: string, storageConfig: StorageConfig): Promise<void>;
  deleteByPrefix(prefix: string, storageConfig: StorageConfig): Promise<void>;
}

export interface MorphCallbacks {
  onAuthRequired: (authId: string, metadata: DelegateMetadata) => void;
  onLogout: (authId: string, reason: LogoutReason) => void;
  onTokenChange?: (authId: string, tokens: TokenSet | null) => void;
}

export interface ProxyConfig {
  url: string;
}

export interface ClientCertificate {
  cert: string;
  key: string;
  passphrase?: string;
}

export interface NetworkConfig {
  certificatePins?: string[];
  proxy?: ProxyConfig;
  clientCertificate?: ClientCertificate;
}

export interface NetworkDelegate {
  getNetworkConfig(hostname: string): Promise<NetworkConfig | null>;
}

export interface TokenExchangeGrant {
  type: 'authorization_code' | 'client_credentials' | 'token_exchange' | 'refresh_token';
  authId: string;
  code?: string;
  codeVerifier?: string;
  sourceAuthId?: string;
  sourceToken?: string;
  refreshToken?: string;
}

export interface MorphOptions {
  storage: StorageProvider;
  variables?: Record<string, string>;
  callbacks: MorphCallbacks;
  networkDelegate?: NetworkDelegate;
  onTokenExchange?: (grant: TokenExchangeGrant) => Promise<TokenSet | null>;
  onSignPayload?: (payload: string, authId: string) => Promise<string>;
  onDecryptResponse?: (encryptedBody: string, authId: string) => Promise<string>;
  onLog?: (
    level: 'debug' | 'info' | 'warn' | 'error',
    message: string,
    error?: Error,
    context?: Record<string, unknown>,
  ) => void;
  /**
   * After each host HTTP attempt (including a 401 refresh retry as a second event).
   * Use for debug UIs; not a substitute for application logging — see {@link onLog}.
   */
  onHttpTrace?: (event: MorphHttpTraceEvent) => void;
  /**
   * When `clientAuth` is `private_key_jwt`, return a signed client assertion JWT for the token endpoint.
   * If omitted and `clientSecret` is present, client_secret is used instead (e.g. PoC Keycloak).
   */
  onClientJwtAssertion?: (authId: string) => Promise<string | null>;
  /** When true, SDK automatically calls `acquireWithClientCredentials` for contexts with `interaction: 'non-interactive'` on `onAuthRequired`. Default false. */
  autoAcquireNonInteractive?: boolean;
}

export interface HostRequestOptions {
  auth?: string | string[];
  headers?: Record<string, string>;
  queryParams?: Record<string, string>;
  timeout?: string;
  sign?: boolean;
  encrypted?: boolean;
}

export interface HostFullRequestOptions extends HostRequestOptions {
  method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';
  path: string;
  body?: unknown;
}

export interface MorphResponse<T = unknown> {
  statusCode: number;
  headers: Record<string, string>;
  body: T;
  resolvedAuth: string;
  raw: Response;
}

/**
 * Structured trace for a single `host(...).get/post/...` HTTP round-trip.
 * Emitted via {@link MorphOptions.onHttpTrace} — separate from {@link MorphOptions.onLog} (human-oriented lines).
 * `Authorization` is redacted in {@link MorphHttpTraceEvent.requestHeaders}.
 */
export interface MorphHttpTraceEvent {
  kind: 'host_http';
  hostKey: string;
  method: string;
  url: string;
  path: string;
  authId: string;
  requestHeaders: Record<string, string>;
  statusCode: number;
  responseHeaders: Record<string, string>;
  responseBody: unknown;
  durationMs: number;
  /** Set when `fetch()` rejects (network failure, abort, etc.). */
  networkError?: string;
}
