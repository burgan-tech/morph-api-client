import type { MorphPlugin, MorphHttpTraceEvent } from '@morph/core';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export type LogFn = (level: LogLevel, message: string, error?: Error, context?: Record<string, unknown>) => void;

export interface LoggerPluginOptions {
  level?: LogLevel;
  prefix?: string;
  onLog?: LogFn;
  onHttpTrace?: (event: MorphHttpTraceEvent) => void;
  httpTrace?: boolean;
}

const LEVEL_ORDER: Record<LogLevel, number> = { debug: 0, info: 1, warn: 2, error: 3 };

function defaultLog(prefix: string, minLevel: LogLevel): LogFn {
  const min = LEVEL_ORDER[minLevel];
  return (level, message, error, context) => {
    if (LEVEL_ORDER[level] < min) return;
    const line = `${prefix}[${level}] ${message}`;
    const args: unknown[] = [];
    if (context) args.push(context);
    if (error) args.push(error);
    switch (level) {
      case 'error': console.error(line, ...args); break;
      case 'warn': console.warn(line, ...args); break;
      case 'info': console.info(line, ...args); break;
      default: console.debug(line, ...args);
    }
  };
}

function defaultHttpTrace(prefix: string) {
  return (event: MorphHttpTraceEvent) => {
    const status = event.networkError ? `ERR ${event.networkError}` : String(event.statusCode);
    console.log(`${prefix}${event.method} ${event.path} → ${status} (${event.durationMs}ms)`);
  };
}

export function createLogger(opts?: LoggerPluginOptions): LogFn {
  return opts?.onLog ?? defaultLog(opts?.prefix ?? '[morph] ', opts?.level ?? 'info');
}

export function loggerPlugin(opts?: LoggerPluginOptions): MorphPlugin {
  const httpTrace = opts?.httpTrace ?? true;
  const logFn = createLogger(opts);
  const traceFn = opts?.onHttpTrace ?? defaultHttpTrace(opts?.prefix ?? '[morph] ');

  return {
    name: '@morph/logger',
    provides: ['logger'],
    install(ctx) {
      const prevLog = ctx.options.onLog;
      ctx.options.onLog = (lvl, msg, err, context) => {
        logFn(lvl, msg, err, context);
        prevLog?.(lvl, msg, err, context);
      };

      if (httpTrace) {
        const prevTrace = ctx.options.onHttpTrace;
        ctx.options.onHttpTrace = (event) => {
          traceFn(event);
          prevTrace?.(event);
        };
      }
    },
  };
}
