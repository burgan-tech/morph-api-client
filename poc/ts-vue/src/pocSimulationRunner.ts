import { AuthError, MorphHttpError, type MorphClient } from '@morph/core';
import type {
  PocSimulationConfig,
  PocSimFetchStep,
  PocSimHostStep,
  PocSimLogoutStep,
  PocSimStep,
  PocSimCondition,
} from './pocSimulation';
import { resolveSimulationMockBaseUrl } from './pocSimulation';
import { pushFetchStyleHttpTrace } from './hostHttpTraceStore';

export type PocSimRunResult = {
  label: string;
  status: number | string;
  ms: number;
  detail: string;
  authFailedAuthId?: string;
  body?: unknown;
};

export type PlaygroundStepRef = {
  step: PocSimStep;
  when?: PocSimCondition;
  blockId?: string;
};

export function isLogoutStep(step: PocSimStep): step is PocSimLogoutStep {
  return step.type === 'logout_provider';
}

function skipInAutoSim(step: PocSimStep): boolean {
  if (isLogoutStep(step)) return true;
  if ('skipInAutoSim' in step && step.skipInAutoSim === true) return true;
  return false;
}

/** Steps executed on each simulation tick (root `steps` only). */
export function filterStepsForAutoTick(steps: PocSimStep[]): PocSimStep[] {
  return steps.filter((s) => !skipInAutoSim(s));
}

export function filterBlockStepForAutoTick(step: PocSimStep): boolean {
  return !skipInAutoSim(step);
}

/** Mock API modal + manual triggers: root steps then each conditional block’s steps (with `when`). */
export function collectPlaygroundSteps(cfg: PocSimulationConfig): PlaygroundStepRef[] {
  const out: PlaygroundStepRef[] = cfg.steps.map((step) => ({ step }));
  for (const b of cfg.conditionalBlocks ?? []) {
    for (const step of b.steps) {
      out.push({ step, when: b.when, blockId: b.id });
    }
  }
  return out;
}

export async function runPocSimFetchStep(
  cfg: PocSimulationConfig,
  step: PocSimFetchStep,
): Promise<PocSimRunResult> {
  const t0 = performance.now();
  const base = resolveSimulationMockBaseUrl(cfg);
  const pathNorm = step.path.startsWith('/') ? step.path : `/${step.path}`;
  const url = `${base}${pathNorm}`;
  let status: number | string = '?';
  let detail = '';
  let body: unknown;
  const requestHeaders: Record<string, string> = { Accept: '*/*' };

  const responseHeadersRecord = (res: Response): Record<string, string> => {
    const o: Record<string, string> = {};
    res.headers.forEach((v, k) => {
      o[k.toLowerCase()] = v;
    });
    return o;
  };

  try {
    const res = await fetch(url);
    const text = await res.text();
    status = res.status;
    const ct = res.headers.get('content-type') ?? '';
    const trim = text.trim();
    const looksJson = ct.includes('json') || (trim.startsWith('{') && trim.endsWith('}'));
    if (looksJson && trim.length) {
      try {
        body = JSON.parse(trim) as unknown;
      } catch {
        body = undefined;
      }
    }
    if (step.expectStatus !== undefined && res.status === step.expectStatus && looksJson) {
      detail = 'expected status (JSON)';
    } else if (step.expectStatus !== undefined && res.status === step.expectStatus && !looksJson) {
      detail =
        '404 but body is HTML — mock-api missing route? Restart `poc/mock-api` or fix VITE_MOCK_API_BASE.';
    } else {
      detail = text.length > 200 ? `${text.slice(0, 200)}…` : text;
      if (step.expectStatus !== undefined && res.status !== step.expectStatus) {
        detail = `expected ${step.expectStatus}, got ${res.status}; ${detail}`;
      }
    }

    const traceBody: unknown =
      body !== undefined ? body : trim.length ? (trim.length > 2000 ? `${trim.slice(0, 2000)}…` : trim) : null;
    pushFetchStyleHttpTrace({
      method: 'GET',
      url,
      path: pathNorm,
      durationMs: Math.round(performance.now() - t0),
      requestHeaders,
      statusCode: res.status,
      responseHeaders: responseHeadersRecord(res),
      responseBody: traceBody,
    });
  } catch (e) {
    status = 'NET';
    detail = e instanceof Error ? e.message : String(e);
    pushFetchStyleHttpTrace({
      method: 'GET',
      url,
      path: pathNorm,
      durationMs: Math.round(performance.now() - t0),
      requestHeaders,
      statusCode: 0,
      responseHeaders: {},
      responseBody: null,
      networkError: detail,
    });
  }
  return {
    label: step.label,
    status,
    ms: Math.round(performance.now() - t0),
    detail,
    body,
  };
}

export async function runPocSimHostStep(
  client: MorphClient,
  step: PocSimHostStep,
  tick: number,
): Promise<PocSimRunResult> {
  const t0 = performance.now();
  const auth = step.auth;
  const host = client.host(step.hostKey);
  try {
    const opts: { auth: string; headers?: Record<string, string> } = { auth };
    const tickHeader = step.tickHeaderName?.trim();
    if (step.headers || tickHeader) {
      opts.headers = { ...step.headers };
      if (tickHeader) opts.headers[tickHeader] = String(tick);
    }
    const method = step.method;
    let res;
    if (method === 'GET') res = await host.get(step.path, opts);
    else if (method === 'POST') res = await host.post(step.path, step.body, opts);
    else if (method === 'PUT') res = await host.put(step.path, step.body, opts);
    else if (method === 'PATCH') res = await host.patch(step.path, step.body, opts);
    else if (method === 'DELETE') res = await host.delete(step.path, opts);
    else throw new Error(`Unsupported method ${String(method)}`);
    return {
      label: step.label,
      status: res.statusCode,
      ms: Math.round(performance.now() - t0),
      detail: 'OK',
      body: res.body,
      authFailedAuthId: undefined,
    };
  } catch (e) {
    if (e instanceof MorphHttpError) {
      return {
        label: step.label,
        status: e.statusCode,
        ms: Math.round(performance.now() - t0),
        detail:
          typeof e.body === 'object' && e.body !== null
            ? JSON.stringify(e.body).slice(0, 200)
            : String(e.body),
      };
    }
    if (e instanceof AuthError) {
      return {
        label: step.label,
        status: 'AUTH',
        ms: Math.round(performance.now() - t0),
        detail: `${e.authId} · ${e.reason}`,
        authFailedAuthId: auth,
      };
    }
    return {
      label: step.label,
      status: 'ERR',
      ms: Math.round(performance.now() - t0),
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function runPocSimLogoutStep(client: MorphClient, step: PocSimLogoutStep): Promise<PocSimRunResult> {
  const t0 = performance.now();
  try {
    await client.auth(step.providerKey).logout();
    return {
      label: step.label,
      status: 'OK',
      ms: Math.round(performance.now() - t0),
      detail: 'Logged out',
    };
  } catch (e) {
    return {
      label: step.label,
      status: 'ERR',
      ms: Math.round(performance.now() - t0),
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function runPocSimStep(
  client: MorphClient,
  cfg: PocSimulationConfig,
  step: PocSimStep,
  tick: number,
): Promise<PocSimRunResult> {
  if (isLogoutStep(step)) return runPocSimLogoutStep(client, step);
  if (step.type === 'fetch') return runPocSimFetchStep(cfg, step);
  return runPocSimHostStep(client, step, tick);
}
