import raw from '../../../docs/poc/poc-simulation.json';
import { getMockApiBaseUrl } from './morph';

export type PocSimMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

/** Base for `fetch`-type steps only (`host` steps use Morph hosts from `docs/poc/poc-config.json`). */
export interface PocSimMockApi {
  /**
   * Mock HTTP API origin (no trailing slash). This is the single source of truth for simulation `fetch` URLs.
   */
  baseUrl: string;
  /**
   * Optional: if `import.meta.env[envOverride]` is set at build time, it wins over `baseUrl` (e.g. `VITE_MOCK_API_BASE`).
   */
  envOverride?: string;
}

export interface PocSimFetchStep {
  type: 'fetch';
  label: string;
  path: string;
  expectStatus?: number;
  /** If true, skipped by the auto simulation loop (still listed in Mock API playground). */
  skipInAutoSim?: boolean;
}

export interface PocSimHostStep {
  type: 'host';
  label: string;
  hostKey: string;
  method: PocSimMethod;
  path: string;
  /** Provider/context auth id, e.g. morph-auth/1fa */
  auth: string;
  /** Optional JSON body for POST/PUT/PATCH */
  body?: unknown;
  /** Extra headers for this call only (merged with host defaults from poc-config). */
  headers?: Record<string, string>;
  /**
   * If set (non-empty), adds this header with the current simulation tick index (auto loop) or
   * playground timestamp (Mock API modal) as the value — only for this step, not global.
   */
  tickHeaderName?: string;
  /** If true, skipped by the auto simulation loop (still listed in Mock API playground). */
  skipInAutoSim?: boolean;
}

export interface PocSimLogoutStep {
  type: 'logout_provider';
  label: string;
  /** Provider key, e.g. `morph-auth` — logs out all contexts for that provider. */
  providerKey: string;
}

export type PocSimStep = PocSimFetchStep | PocSimHostStep | PocSimLogoutStep;

/**
 * Declarative `when` for conditional blocks (evaluated in the Vue app).
 * Compose with `{ "type": "all", "all": [ ... ] }` for AND.
 */
export type PocSimCondition =
  | { type: 'ui_flag_probe_404' }
  | { type: 'provider_env_ready'; providerKey: string }
  | { type: 'has_valid_token'; authId: string }
  | { type: 'all'; all: PocSimCondition[] };

export interface PocSimConditionalBlock {
  id: string;
  when: PocSimCondition;
  /** When `when` is false, one SKIP row is recorded (e.g. Google not logged in). */
  skipRow?: { label: string; detail: string };
  steps: PocSimStep[];
}

export interface PocSimulationConfig {
  version: number;
  description?: string;
  /** Base URL for `fetch` steps; omit only for legacy files (falls back to `getMockApiBaseUrl()`). */
  mockApi?: PocSimMockApi;
  sessionDeadCheck?: {
    authIds: string[];
    message: string;
  };
  steps: PocSimStep[];
  conditionalBlocks?: PocSimConditionalBlock[];
}

export function getPocSimulationConfig(): PocSimulationConfig {
  const c = raw as PocSimulationConfig;
  if (c.version !== 1) {
    throw new Error(`Unsupported poc-simulation.json version: ${String(c.version)}`);
  }
  return c;
}

/**
 * Resolves mock base for `fetch` steps: `mockApi.envOverride` (if set + env truthy) → `mockApi.baseUrl` → `getMockApiBaseUrl()`.
 */
export function resolveSimulationMockBaseUrl(cfg: PocSimulationConfig): string {
  const key = cfg.mockApi?.envOverride?.trim();
  if (key) {
    const fromEnv = (import.meta.env as Record<string, string | undefined>)[key]?.trim();
    if (fromEnv) return fromEnv.replace(/\/$/, '');
  }
  const fromCfg = cfg.mockApi?.baseUrl?.trim();
  if (fromCfg) return fromCfg.replace(/\/$/, '');
  return getMockApiBaseUrl();
}
