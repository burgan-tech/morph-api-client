import { shallowRef } from 'vue';
import type { MorphHttpTraceEvent } from '@morph/core';

export type HostHttpTraceRow = MorphHttpTraceEvent & { id: string };

const MAX = 50;
let seq = 0;

/** Latest-first list for the Mock API playground (`onHttpTrace`). */
export const hostHttpTraces = shallowRef<HostHttpTraceRow[]>([]);

export function pushHostHttpTrace(e: MorphHttpTraceEvent): void {
  seq += 1;
  hostHttpTraces.value = [{ ...e, id: `http-${seq}` }, ...hostHttpTraces.value].slice(0, MAX);
}

export function clearHostHttpTraces(): void {
  hostHttpTraces.value = [];
}

/**
 * Log a simulation `fetch` step into the same list as SDK `onHttpTrace` (host calls use `hostKey` from config;
 * these use `hostKey: "fetch"` and `authId: "(fetch)"`).
 */
export function pushFetchStyleHttpTrace(opts: {
  method: string;
  url: string;
  path: string;
  durationMs: number;
  requestHeaders: Record<string, string>;
  statusCode: number;
  responseHeaders: Record<string, string>;
  responseBody: unknown;
  networkError?: string;
}): void {
  pushHostHttpTrace({
    kind: 'host_http',
    hostKey: 'fetch',
    method: opts.method.toUpperCase(),
    url: opts.url,
    path: opts.path,
    authId: '(fetch)',
    requestHeaders: opts.requestHeaders,
    statusCode: opts.statusCode,
    responseHeaders: opts.responseHeaders,
    responseBody: opts.responseBody,
    durationMs: opts.durationMs,
    networkError: opts.networkError,
  });
}
