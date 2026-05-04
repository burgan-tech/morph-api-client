import 'package:morph_core/morph_core.dart';

import 'create_logger.dart';

/// Parity [`loggerPlugin`](/packages/logger/src/index.ts).
MorphPlugin loggerPlugin([LoggerPluginOptions? opts]) =>
    _LoggerMorphPlugin(opts ?? const LoggerPluginOptions());

final class _LoggerMorphPlugin implements MorphPlugin {
  _LoggerMorphPlugin(this.opts);

  final LoggerPluginOptions opts;

  @override
  String get name => '@morph/logger';

  @override
  List<String>? get provides => const ['logger'];

  @override
  List<String>? get requires => null;

  @override
  void dispose() {}

  @override
  void install(MorphPluginContext ctx) {
    final logFn = createLogger(opts);
    final prevLog = ctx.options.onLog;
    ctx.options.onLog = (String lvl, String msg, [Object? err, Map<String, Object?>? context]) {
      logFn(lvl, msg, err, context);
      prevLog?.call(lvl, msg, err, context);
    };

    final wantsTrace = opts.httpTrace ?? true;
    if (wantsTrace) {
      final traceFn = opts.onHttpTrace ?? morphDefaultHttpTrace(opts.prefix);
      final prevTrace = ctx.options.onHttpTrace;
      ctx.options.onHttpTrace = (MorphHttpTraceEvent event) {
        traceFn(event);
        prevTrace?.call(event);
      };
    }
  }
}
