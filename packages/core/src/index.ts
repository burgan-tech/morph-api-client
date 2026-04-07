export { MorphClient } from './client/MorphClient.js';
export { HostClient } from './client/HostClient.js';
export { AuthHandle } from './client/AuthHandle.js';

export type {
  MorphConfig,
  MorphOptions,
  MorphCallbacks,
  MorphResponse,
  HostRequestOptions,
  HostFullRequestOptions,
  TokenSet,
  MorphTokenStatus,
  MorphProviderMeta,
  MorphContextMeta,
  TokenExchangeGrant,
  StorageProvider,
  StorageConfig,
  NetworkDelegate,
  NetworkConfig,
  NetworkPolicy,
  HostConfig,
  ProviderConfig,
  AuthContextConfig,
  CtxRef,
  AuthPlugin,
  AuthPluginFactory,
  DelegateMetadata,
  InteractionMode,
  LogoutReason,
  MorphHttpTraceEvent,
  OAuthReturnResult,
  OAuthReturnStatus,
} from './types.js';

export {
  ConfigValidationError,
  UnknownHostError,
  UnknownProviderError,
  UnknownContextError,
  InvalidAuthForHostError,
  AuthError,
  TokenEndpointError,
  MorphHttpError,
} from './errors.js';

export { validateAndIndexConfig } from './config/validate.js';
export type { ResolvedMorphConfig } from './config/validate.js';

export { decodeJwtPayload, getJwtExpirySeconds, getJwtSubject } from './util/jwt.js';
export type { JwtPayload } from './util/jwt.js';
export { buildOAuth2AuthorizationUrl } from './util/oauthAuthorize.js';
export { stripOAuthReturnSearchParams, cleanOAuthReturnFromBrowser } from './util/oauthReturn.js';
export { encodeOAuthState, decodeOAuthState } from './util/oauthState.js';
export { normalizeLoopbackOrigin } from './util/normalizeOrigin.js';
