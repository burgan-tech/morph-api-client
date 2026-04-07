import {
  MorphClient,
  normalizeLoopbackOrigin,
  type MorphConfig,
  type MorphOptions,
} from '@morph/core';
import { oauth2Plugin } from '@morph/oauth2';
import { browserStoragePlugin } from '@morph/browser-storage';
import { loggerPlugin } from '@morph/logger';
import morphConfigJson from '../../../docs/poc/poc-config.json';
import { pushHostHttpTrace } from './hostHttpTraceStore';

/**
 * Deep-clone `docs/poc/poc-config.json` and apply PoC-wide runtime flags only (no per-provider key hacks — proxies live in config + `variables`).
 */
function buildMorphConfig(): MorphConfig {
  const c = JSON.parse(JSON.stringify(morphConfigJson)) as MorphConfig;
  if (import.meta.env.VITE_SIMULATION_MODE === 'true') {
    for (const p of c.providers) {
      for (const ctx of p.contexts) {
        if (ctx.refreshPolicy) {
          ctx.refreshPolicy = { ...ctx.refreshPolicy, refreshBeforeExpiry: '5s' };
        }
      }
    }
  }
  return c;
}

/** Mock API origin for raw `fetch` (public routes). Host `main-api` uses the same default. */
export function getMockApiBaseUrl(): string {
  return (import.meta.env.VITE_MOCK_API_BASE as string | undefined)?.replace(/\/$/, '') ?? 'http://localhost:3000';
}

const SIM_VERBOSE_KEY = 'morph-poc:sim-verbose';

export function setSimulationConsoleVerbose(on: boolean): void {
  if (typeof sessionStorage === 'undefined') return;
  try {
    if (on) sessionStorage.setItem(SIM_VERBOSE_KEY, '1');
    else sessionStorage.removeItem(SIM_VERBOSE_KEY);
  } catch {
    /* ignore */
  }
}

export function getSimulationConsoleVerbose(): boolean {
  if (typeof sessionStorage === 'undefined') return false;
  try {
    return sessionStorage.getItem(SIM_VERBOSE_KEY) === '1';
  } catch {
    return false;
  }
}

const morphConfig = buildMorphConfig();

const STORAGE_PREFIX = 'morph-poc:tk:';

/**
 * Mobile model: device token uses stable deviceId + installationId (GUID created on first install).
 * Web PoC simulation: browser profile ≈ device (localStorage), browser tab session ≈ install (sessionStorage — new tab/session ⇒ new installationId).
 * Set VITE_DEVICE_ID / VITE_INSTALLATION_ID to pin values (CI, demos).
 */
const WEB_SIM_DEVICE_KEY = 'morph-poc:device-id';
const WEB_SIM_INSTALL_KEY = 'morph-poc:installation-id';

function readOrCreateWebSimDeviceId(): string {
  const fromEnv = import.meta.env.VITE_DEVICE_ID?.trim();
  if (fromEnv) return fromEnv;
  if (typeof localStorage === 'undefined') return 'poc-device-anon';
  try {
    let id = localStorage.getItem(WEB_SIM_DEVICE_KEY);
    if (!id) {
      id = crypto.randomUUID();
      localStorage.setItem(WEB_SIM_DEVICE_KEY, id);
    }
    return id;
  } catch {
    return `poc-device-${crypto.randomUUID()}`;
  }
}

function readOrCreateWebSimInstallationId(): string {
  const fromEnv = import.meta.env.VITE_INSTALLATION_ID?.trim();
  if (fromEnv) return fromEnv;
  if (typeof sessionStorage === 'undefined') return 'poc-install-anon';
  try {
    let id = sessionStorage.getItem(WEB_SIM_INSTALL_KEY);
    if (!id) {
      id = crypto.randomUUID();
      sessionStorage.setItem(WEB_SIM_INSTALL_KEY, id);
    }
    return id;
  } catch {
    return `poc-install-${crypto.randomUUID()}`;
  }
}

function keycloakRealmOidcPath(host: string): string {
  return `${host.replace(/\/$/, '')}/realms/morph/protocol/openid-connect`;
}

function variables(): Record<string, string> {
  const v = import.meta.env;
  const origin = typeof window !== 'undefined' ? window.location.origin : 'http://localhost:5173';
  const useDynamicRedirect = import.meta.env.DEV;
  const oauthBase = useDynamicRedirect ? normalizeLoopbackOrigin(origin) : origin.replace(/\/$/, '');
  return {
    deviceId: readOrCreateWebSimDeviceId(),
    installationId: readOrCreateWebSimInstallationId(),
    deviceClientSecret: v.VITE_DEVICE_CLIENT_SECRET ?? '',
    loginClientSecret: v.VITE_LOGIN_CLIENT_SECRET ?? '',
    sessionClientSecret: v.VITE_SESSION_CLIENT_SECRET ?? '',
    keycloakOidcBase: keycloakRealmOidcPath(v.VITE_KEYCLOAK_ORIGIN?.trim() || 'http://localhost:8080'),
    /**
     * Dev: Vite `/__keycloak` proxy for token HTTP (empty in prod → SDK uses `keycloakOidcBase`).
     * Set in `syncOAuthRedirectUrisFromBrowser` when the tab origin changes.
     */
    pocKeycloakTokenHttpBase: (() => {
      if (import.meta.env.DEV && typeof window !== 'undefined') {
        return `${normalizeLoopbackOrigin(window.location.origin)}/__keycloak${keycloakRealmOidcPath('')}`;
      }
      return '';
    })(),
    /** Dev: same-origin base for Google token proxy; empty in prod. */
    pocGoogleTokenHttpBase: (() => {
      if (import.meta.env.DEV && typeof window !== 'undefined') {
        return normalizeLoopbackOrigin(window.location.origin);
      }
      return '';
    })(),
    /** Dev: relative path to Vite `/__google-oauth/token`; prod: absolute Google token URL. */
    pocGoogleTokenEndpoint: (() => {
      if (import.meta.env.DEV && typeof window !== 'undefined') {
        return '/__google-oauth/token';
      }
      return 'https://oauth2.googleapis.com/token';
    })(),
    keycloakBrowserBaseUrl: keycloakRealmOidcPath(v.VITE_KEYCLOAK_ORIGIN?.trim() || 'http://localhost:8080'),
    /** Shared OAuth redirect for all authorization_code contexts (Keycloak, Google, …). Override with VITE_OAUTH_REDIRECT_URI. */
    oauthCallbackUri: v.VITE_OAUTH_REDIRECT_URI?.trim() || `${oauthBase}/oauth/callback`,
    googleClientId: v.VITE_GOOGLE_CLIENT_ID ?? '',
    googleClientSecret: v.VITE_GOOGLE_CLIENT_SECRET ?? '',
  };
}

/** One snapshot for MorphClient and authorize URL so redirect_uri is identical everywhere. */
const morphVariables = variables();

/** Values sent as X-Device-Id / X-Installation-Id (see web simulation in module comment above). */
export function getWebSimDeviceIdentity(): { deviceId: string; installationId: string } {
  return { deviceId: morphVariables.deviceId, installationId: morphVariables.installationId };
}

/**
 * Dev: syncs OAuth redirect URI and Vite token-proxy bases (`pocKeycloakTokenHttpBase`, `pocGoogle*`) to the current tab origin.
 * Prod: optional `VITE_OAUTH_REDIRECT_URI` override only.
 */
export function syncOAuthRedirectUrisFromBrowser(): void {
  if (typeof window === 'undefined') return;
  if (import.meta.env.DEV) {
    const o = normalizeLoopbackOrigin(window.location.origin);
    morphVariables.oauthCallbackUri = `${o}/oauth/callback`;
    morphVariables.pocKeycloakTokenHttpBase = `${o}/__keycloak${keycloakRealmOidcPath('')}`;
    morphVariables.pocGoogleTokenHttpBase = o;
    morphVariables.pocGoogleTokenEndpoint = '/__google-oauth/token';
  } else {
    const uri = import.meta.env.VITE_OAUTH_REDIRECT_URI?.trim();
    if (uri) morphVariables.oauthCallbackUri = uri;
  }
}

/** Warn when dev origin is not loopback — IdP redirect URI allowlists must include the exact browser origin. */
export function warnPocOAuthRedirectIfNonLoopback(): void {
  if (!import.meta.env.DEV || typeof window === 'undefined') return;
  const { hostname } = window.location;
  const loopback =
    hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '::1' ||
    hostname === '[::1]';
  if (loopback) return;
  const o = normalizeLoopbackOrigin(window.location.origin);
  console.warn(
    `[morph-poc] OAuth redirect URI is "${o}/oauth/callback" for all IdPs in this PoC. Register that exact URI (and your raw origin variant if needed) in Keycloak and Google Cloud.`,
  );
}

const logger = loggerPlugin({
  level: getSimulationConsoleVerbose() ? 'debug' : 'info',
  prefix: '[morph] ',
});

const options: MorphOptions = {
  plugins: [
    logger,
    oauth2Plugin({
      logger,
      storage: browserStoragePlugin({ prefix: STORAGE_PREFIX, logger }),
      variables: morphVariables,
      autoAcquireNonInteractive: true,
      callbacks: {
        onTokenChange(authId, tokens) {
          console.debug('[morph] onTokenChange', authId, !!tokens);
        },
      },
    }),
  ],
  variables: morphVariables,
  onHttpTrace: (e) => pushHostHttpTrace(e),
};

export const morph = MorphClient.init(morphConfig, options);

/**
 * Builds the IdP authorize URL (SDK embeds `authId` in `state` by default).
 * This function syncs redirect URIs first.
 */
export function pocGetAuthorizationUrl(authId: string): string {
  syncOAuthRedirectUrisFromBrowser();
  return morph.getAuthorizationUrl(authId);
}
