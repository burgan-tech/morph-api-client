import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../morph_init.dart';
import '../poc_simulation.dart';
import '../widgets/mock_api_sheet.dart';
import '../widgets/provider_config_sheet.dart';
import '../widgets/simulation_panel.dart';
import '../widgets/token_status_card.dart';


const _kStatusLabels = {
  'morph-auth/device': 'Device',
  'morph-auth/2fa': 'Login (2fa)',
  'morph-auth/1fa': 'Session (1fa)',
  'google-auth/google': 'Google',
};

String _labelFor(MorphTokenStatus s) =>
    _kStatusLabels[s.authId] ?? s.authId;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.morph});

  final MorphClient morph;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MorphTokenStatus> _tokenStatus = [];
  String _message = '';
  bool _busy = false;
  PocSimulationConfig? _simCfg;

  MorphClient get _morph => widget.morph;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      print('[morph-poc] _init start');
      await _refreshStatus();
      print('[morph-poc] _init: loading sim config…');
      final cfg = await loadPocSimulation(getMockApiBase());
      print('[morph-poc] _init: sim config loaded (${cfg.steps.length} steps)');
      if (mounted) setState(() => _simCfg = cfg);
    } catch (e, st) {
      print('[morph-poc] _init THREW: $e\n$st');
      if (mounted) setState(() => _message = 'Init error: $e');
    }
  }

  Future<void> _refreshStatus() async {
    try {
      print('[morph-poc] _refreshStatus start');
      final status = await _morph.getTokenStatus();
      print('[morph-poc] _refreshStatus: ${status.length} entries — ${status.map((s) => "${s.authId}:${s.hasAccessToken ? 'token' : 'none'}").join(", ")}');
      if (mounted) setState(() => _tokenStatus = status);
    } catch (e, st) {
      print('[morph-poc] _refreshStatus THREW: $e\n$st');
      _setMessage('Error refreshing status: $e');
    }
  }

  void _setMessage(String msg) {
    if (mounted) setState(() => _message = msg);
  }

  void _setBusy(bool v) {
    if (mounted) setState(() => _busy = v);
  }

  // ── Per-row dynamic actions (mirrors TS buildActionsForRow) ───────────────

  List<_ContextAction> _actionsForRow(MorphTokenStatus row) {
    final actions = <_ContextAction>[];
    final gh = row.grantHint;

    if (gh == 'client_credentials') {
      actions.add(_ContextAction(
        label: 'Acquire token',
        onPressed: _busy ? null : () => _runAcquire(row.authId),
      ));
    }
    if (gh == 'authorization_code') {
      if (row.providerKey == 'morph-auth') {
        actions.add(_ContextAction(
          label: 'Keycloak login',
          onPressed: _busy ? null : _startLogin,
        ));
      }
      // Google: show disabled button with hint
      if (row.providerKey == 'google-auth') {
        actions.add(_ContextAction(
          label: 'Google login',
          onPressed: null,
          tooltip: 'Configure GOOGLE_CLIENT_ID env (not set in PoC)',
        ));
      }
    }
    if (row.hasAccessToken || row.hasRefreshToken) {
      actions.add(_ContextAction(
        label: 'Logout',
        danger: true,
        onPressed: _busy ? null : () => _runLogout(row.authId),
      ));
    }
    return actions;
  }

  // ── Auth actions ──────────────────────────────────────────────────────────

  Future<void> _runAcquire(String authId) async {
    _setBusy(true);
    _setMessage('');
    try {
      await _morph.auth(authId).acquireWithClientCredentials();
      _setMessage('Token acquired ($authId).');
    } catch (e) {
      _setMessage('Acquire failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  Future<void> _startLogin() async {
    const authId = 'morph-auth/2fa';
    _setMessage('');
    try {
      final url = _morph.getAuthorizationUrl(authId);
      if (kIsWeb) {
        // On web: navigate the CURRENT tab so Keycloak redirects back here
        // with ?code=...&state=... — handled in main() before runApp.
        // webOnlyWindowName: '_self' replaces the current tab instead of opening a new one.
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
      } else {
        if (!await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication)) {
          _setMessage('Could not open browser for login.');
        }
      }
    } catch (e) {
      _setMessage('Login failed: $e');
    }
  }

  Future<void> _runLogout(String authId) async {
    _setBusy(true);
    _setMessage('');
    try {
      await _morph.auth(authId).logout();
      _setMessage('Logged out ($authId).');
    } catch (e) {
      _setMessage('Logout failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  Future<void> _runExchange(String sourceAuthId, String targetAuthId) async {
    _setBusy(true);
    _setMessage('');
    try {
      await _morph.auth(sourceAuthId).exchangeToken(targetAuthId);
      _setMessage('Exchanged $sourceAuthId → $targetAuthId.');
    } catch (e) {
      _setMessage('Exchange failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  // ── Open sheets ───────────────────────────────────────────────────────────

  void _openMockApi() {
    final cfg = _simCfg;
    if (cfg == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MockApiSheet(morph: _morph, cfg: cfg),
    ).then((_) => _refreshStatus());
  }

  void _openProviderConfig(String providerKey) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          ProviderConfigSheet(morph: _morph, providerKey: providerKey),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Group token statuses by providerKey preserving order.
  Map<String, List<MorphTokenStatus>> get _byProvider {
    final out = <String, List<MorphTokenStatus>>{};
    for (final s in _tokenStatus) {
      out.putIfAbsent(s.providerKey, () => []).add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Morph Flutter PoC'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload token snapshot',
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status ──
              _SectionHeader('Status'),
              if (_tokenStatus.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Loading…'),
                )
              else
                ..._byProvider.entries.map((entry) {
                  try {
                    return _ProviderSection(
                      providerKey: entry.key,
                      rows: entry.value,
                      busy: _busy,
                      morph: _morph,
                      actionsForRow: _actionsForRow,
                      onExchange: _runExchange,
                      onConfigTap: () => _openProviderConfig(entry.key),
                      onJwtTap: (s) => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => TokenClaimsSheet(status: s),
                      ),
                    );
                  } catch (e, st) {
                    print('[morph-poc] _ProviderSection build THREW for ${entry.key}: $e\n$st');
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('UI error (${entry.key}): $e',
                          style: const TextStyle(color: Colors.red, fontSize: 11)),
                    );
                  }
                }),

              // ── Mock API ──
              _SectionHeader('Mock API'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.api_outlined),
                  label: const Text('Open Mock API & HTTP log'),
                  onPressed:
                      (_simCfg == null || _busy) ? null : _openMockApi,
                ),
              ),

              // ── Status message ──
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Text(_message,
                      style: const TextStyle(fontSize: 13)),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),

              // ── Simulation ──
              const _SectionHeader('Simulation'),
              if (_simCfg == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Loading simulation config…',
                      style: TextStyle(fontSize: 13)),
                )
              else
                SimulationPanel(
                  morph: _morph,
                  cfg: _simCfg!,
                  onStatusChanged: _refreshStatus,
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider section widget
// ---------------------------------------------------------------------------

class _ProviderSection extends StatefulWidget {
  const _ProviderSection({
    required this.providerKey,
    required this.rows,
    required this.busy,
    required this.morph,
    required this.actionsForRow,
    required this.onExchange,
    required this.onConfigTap,
    required this.onJwtTap,
  });

  final String providerKey;
  final List<MorphTokenStatus> rows;
  final bool busy;
  final MorphClient morph;
  final List<_ContextAction> Function(MorphTokenStatus) actionsForRow;
  final Future<void> Function(String source, String target) onExchange;
  final VoidCallback onConfigTap;
  final void Function(MorphTokenStatus) onJwtTap;

  @override
  State<_ProviderSection> createState() => _ProviderSectionState();
}

class _ProviderSectionState extends State<_ProviderSection> {
  /// Selected exchange source per target authId.
  final Map<String, String> _exchangePick = {};

  @override
  void didUpdateWidget(_ProviderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncExchangePicks();
  }

  @override
  void initState() {
    super.initState();
    _syncExchangePicks();
  }

  void _syncExchangePicks() {
    for (final row in widget.rows) {
      final sources = widget.morph.getExchangeSources(row.authId);
      if (sources.isEmpty) {
        _exchangePick.remove(row.authId);
      } else {
        final cur = _exchangePick[row.authId];
        if (cur == null || !sources.contains(cur)) {
          _exchangePick[row.authId] = sources.first;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider header row
          Row(
            children: [
              Text(
                widget.providerKey.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.06,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onConfigTap,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11)),
                child: const Text('Config'),
              ),
            ],
          ),
          // Context rows
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: widget.rows.asMap().entries.map((e) {
                final idx = e.key;
                final row = e.value;
                final isLast = idx == widget.rows.length - 1;
                final sources =
                    widget.morph.getExchangeSources(row.authId);
                final actions = widget.actionsForRow(row);

                return Column(
                  children: [
                    // Token summary button (tap → JWT claims)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: TokenStatusCard(
                        status: row,
                        label: _labelFor(row),
                        onTap: () => widget.onJwtTap(row),
                      ),
                    ),
                    // Action buttons
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: actions.map((a) {
                            return _SmallButton(
                              label: a.label,
                              danger: a.danger,
                              tooltip: a.tooltip,
                              onPressed: widget.busy ? null : a.onPressed,
                            );
                          }).toList(),
                        ),
                      ),
                    // Exchange dropdown (only for target contexts)
                    if (sources.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: _ExchangeRow(
                          targetAuthId: row.authId,
                          sources: sources,
                          picked: _exchangePick[row.authId] ?? sources.first,
                          busy: widget.busy,
                          onPickChanged: (v) =>
                              setState(() => _exchangePick[row.authId] = v),
                          onExchange: () {
                            final src = _exchangePick[row.authId];
                            if (src != null) {
                              widget.onExchange(src, row.authId);
                            }
                          },
                        ),
                      ),
                    if (!isLast)
                      const Divider(height: 12, indent: 8, endIndent: 8),
                    if (isLast) const SizedBox(height: 8),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExchangeRow extends StatelessWidget {
  const _ExchangeRow({
    required this.targetAuthId,
    required this.sources,
    required this.picked,
    required this.busy,
    required this.onPickChanged,
    required this.onExchange,
  });

  final String targetAuthId;
  final List<String> sources;
  final String picked;
  final bool busy;
  final void Function(String) onPickChanged;
  final VoidCallback onExchange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Subject',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B21A8))),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButton<String>(
            value: picked,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 11, color: Color(0xFF1E1B4B)),
            items: sources
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                          '${_kStatusLabels[s] ?? s} ($s)',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: busy ? null : (v) => v != null ? onPickChanged(v) : null,
          ),
        ),
        const SizedBox(width: 6),
        _SmallButton(
          label: 'Exchange',
          onPressed: busy ? null : onExchange,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _ContextAction {
  const _ContextAction({
    required this.label,
    this.onPressed,
    this.danger = false,
    this.tooltip,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final String? tooltip;
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    this.onPressed,
    this.danger = false,
    this.tooltip,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: danger
          ? OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11))
          : OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11)),
      child: Text(label),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

