import type { MorphPlugin } from '@morph/core';
import { createBrowserSessionStorage, createBrowserLocalStorage } from './browserStorage.js';

export type LogFn = (level: 'debug' | 'info' | 'warn' | 'error', message: string, error?: Error, context?: Record<string, unknown>) => void;

export interface BrowserStoragePluginOptions {
  prefix?: string;
  type?: 'session' | 'local';
  logger?: MorphPlugin | LogFn;
}

function isMorphPlugin(s: unknown): s is MorphPlugin {
  return typeof s === 'object' && s !== null && 'install' in s && typeof (s as MorphPlugin).install === 'function';
}

export function browserStoragePlugin(optsOrPrefix?: string | BrowserStoragePluginOptions, type?: 'session' | 'local'): MorphPlugin {
  const resolved = typeof optsOrPrefix === 'string'
    ? { prefix: optsOrPrefix, type: type ?? 'session' as const, logger: undefined as MorphPlugin | LogFn | undefined }
    : { prefix: optsOrPrefix?.prefix ?? 'morph:tk:', type: optsOrPrefix?.type ?? 'session' as const, logger: optsOrPrefix?.logger };

  return {
    name: '@morph/browser-storage',
    provides: ['storage'],
    install(ctx) {
      if (resolved.logger && isMorphPlugin(resolved.logger)) {
        resolved.logger.install(ctx as Parameters<MorphPlugin['install']>[0]);
      } else if (typeof resolved.logger === 'function') {
        const prev = ctx.options.onLog;
        ctx.options.onLog = (lvl, msg, err, context) => {
          (resolved.logger as LogFn)(lvl, msg, err, context);
          prev?.(lvl, msg, err, context);
        };
      }

      const storage = resolved.type === 'local'
        ? createBrowserLocalStorage(resolved.prefix)
        : createBrowserSessionStorage(resolved.prefix);
      ctx.provideStorage(storage);
      ctx.options.onLog?.('debug', `Storage initialized (${resolved.type}Storage, prefix: "${resolved.prefix}")`, undefined, { plugin: '@morph/browser-storage' });
    },
  };
}

export { createBrowserSessionStorage, createBrowserLocalStorage } from './browserStorage.js';
