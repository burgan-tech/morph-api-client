import 'package:morph_core/morph_core.dart';

import 'oauth_callbacks.dart';
import 'token_lifecycle.dart';

/// Options for [oauth2Plugin]. TS parity: [`OAuth2PluginOptions`](/packages/ts/oauth2/src/index.ts).
final class OAuth2PluginOptions {
  const OAuth2PluginOptions({
    this.storage,
    this.logger,
    this.variables,
    this.callbacks,
    this.onTokenExchange,
    this.onClientJwtAssertion,
    this.autoAcquireNonInteractive,
  });

  /// [StorageProvider] or inline plugin that exposes storage via [MorphPlugin.install].
  final Object? storage;

  /// Plugin (e.g. logger) installed on the same [MorphPluginContext], or [MorphLogFn].
  final Object? logger;

  final Map<String, String>? variables;
  final MorphOAuthCallbacksPartial? callbacks;
  final Future<TokenSet?> Function(TokenExchangeGrant grant)? onTokenExchange;
  final Future<String?> Function(String authId)? onClientJwtAssertion;
  final bool? autoAcquireNonInteractive;
}

MorphLogFn? _resolveLogFn(Object? logger, MorphPluginContext ctx) {
  if (logger == null) return ctx.options.onLog;
  if (logger is MorphPlugin) {
    logger.install(ctx);
    return ctx.options.onLog;
  }
  if (logger is MorphLogFn) return logger;
  return ctx.options.onLog;
}

/// OAuth2 auth plugin parity with TS [`oauth2Plugin`](/packages/ts/oauth2/src/index.ts).
MorphPlugin oauth2Plugin([OAuth2PluginOptions? opts]) =>
    _OAuth2MorphPlugin(opts ?? const OAuth2PluginOptions());

final class _OAuth2MorphPlugin implements MorphPlugin {
  _OAuth2MorphPlugin(this.opts);

  final OAuth2PluginOptions opts;

  @override
  void dispose() {}

  @override
  String get name => '@morph/oauth2';

  @override
  List<String>? get provides => const ['auth'];

  @override
  List<String>? get requires {
    final storageOpt = opts.storage;
    final hasExplicit =
        storageOpt is MorphPlugin || storageOpt is StorageProvider;
    return hasExplicit ? <String>[] : const ['storage'];
  }

  @override
  void install(MorphPluginContext ctx) {
    final log = _resolveLogFn(opts.logger, ctx);

    StorageProvider? direct;
    final storageOpt = opts.storage;
    if (storageOpt is MorphPlugin) {
      storageOpt.install(ctx);
    } else if (storageOpt is StorageProvider) {
      direct = storageOpt;
    }

    final resolvedStorage = direct ?? ctx.options.resolvedStorage;
    if (resolvedStorage == null) {
      throw StateError(
        'OAuth2 plugin requires storage. Pass storage in options or add a storage plugin.',
      );
    }

    void defaultOnAuthRequired(String authId, DelegateMetadata metadata) {
      log?.call('warn', 'onAuthRequired: $authId', null,
          {'authId': authId});
    }

    void defaultOnLogout(String authId, LogoutReason reason) {
      log?.call(
        'info',
        'onLogout: $authId ($reason)',
        null,
        {'authId': authId, 'reason': reason},
      );
    }

    final variables = <String, String>{
      ...ctx.variables,
      ...?opts.variables,
    };

    final partial = opts.callbacks;
    final callbacks = MorphOAuthCallbacks(
      onAuthRequired: partial?.onAuthRequired ?? defaultOnAuthRequired,
      onLogout: partial?.onLogout ?? defaultOnLogout,
      onTokenChange: partial?.onTokenChange,
    );

    final tokenOpts = OAuth2TokenOptions(
      callbacks: callbacks,
      variables: variables,
      onTokenExchange: opts.onTokenExchange,
      onClientJwtAssertion: opts.onClientJwtAssertion,
      autoAcquireNonInteractive: opts.autoAcquireNonInteractive,
      onLog: log,
    );

    final auth = TokenLifecycle(ctx.resolved, tokenOpts, variables, log, resolvedStorage);
    ctx.provideAuth(auth);
  }
}
