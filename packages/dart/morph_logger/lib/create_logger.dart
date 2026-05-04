import 'dart:developer' as dev;

import 'package:morph_core/morph_core.dart';

/// Same level names as TS [`LogLevel`](/packages/ts/logger/src/index.ts).
typedef LogLevel = String;

const Map<String, int> _levelOrder = {
  'debug': 0,
  'info': 1,
  'warn': 2,
  'error': 3,
};

/// Parity [`LoggerPluginOptions`](/packages/ts/logger/src/index.ts).
final class LoggerPluginOptions {
  const LoggerPluginOptions({
    this.level = 'info',
    this.prefix = '[morph] ',
    this.onLog,
    this.onHttpTrace,
    this.httpTrace,
  });

  final LogLevel level;
  final String prefix;
  final MorphLogFn? onLog;

  /// Overrides the default HTTP trace line writer.
  final void Function(MorphHttpTraceEvent event)? onHttpTrace;

  /// When `true` (default), chains [MorphOptions.onHttpTrace] with defaults.
  final bool? httpTrace;
}

/// Human-readable trace line without emitting (TS `defaultHttpTrace` text).
String morphHttpTraceMessage(String prefix, MorphHttpTraceEvent event) {
  final status =
      event.networkError != null ? 'ERR ${event.networkError}' : '${event.statusCode}';
  return '$prefix${event.method} ${event.path} → $status (${event.durationMs}ms)';
}

/// Default HTTP trace line (TS `defaultHttpTrace`).
void Function(MorphHttpTraceEvent event) morphDefaultHttpTrace(String prefix) {
  return (MorphHttpTraceEvent event) {
    dev.log(morphHttpTraceMessage(prefix, event));
  };
}

MorphLogFn _defaultLog(String prefix, LogLevel minLevel) {
  final min = _levelOrder[minLevel] ?? 1;
  return (String level, String message, [Object? error, Map<String, Object?>? context]) {
    final ord = _levelOrder[level] ?? 1;
    if (ord < min) return;
    dev.log('$prefix[$level] $message', level: ord * 250, error: error);
    if (context != null && context.isNotEmpty) {
      dev.log('$prefix ctx: $context', level: ord * 250);
    }
  };
}

/// Returns a [`MorphLogFn`] (TS [`createLogger`](/packages/ts/logger/src/index.ts)).
MorphLogFn createLogger([LoggerPluginOptions opts = const LoggerPluginOptions()]) {
  return opts.onLog ?? _defaultLog(opts.prefix, opts.level);
}
