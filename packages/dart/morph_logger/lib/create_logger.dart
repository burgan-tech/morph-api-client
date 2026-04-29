import 'dart:developer' as dev;

typedef LogLevel = String;

typedef MorphLoggerLogFn = void Function(
  LogLevel level,
  String message, [
  Object? error,
  Map<String, Object?>? context,
]);

const Map<String, int> _levels = {'debug': 0, 'info': 1, 'warn': 2, 'error': 3};

/// Default logging function (`packages/logger` parity).
MorphLoggerLogFn createLogger({
  LogLevel minLevel = 'info',
  String prefix = '[morph] ',
  MorphLoggerLogFn? onLog,
}) {
  if (onLog != null) return onLog;
  final min = _levels[minLevel] ?? 1;
  return (level, message, [error, context]) {
    final ord = _levels[level] ?? 1;
    if (ord < min) return;
    dev.log('$prefix[$level] $message', level: ord * 250, error: error);
    if (context != null && context.isNotEmpty) {
      dev.log('$prefix ctx: $context', level: ord * 250);
    }
  };
}
