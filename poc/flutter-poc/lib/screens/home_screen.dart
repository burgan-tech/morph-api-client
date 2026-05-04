import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../morph_init.dart';
import '../widgets/http_trace_log.dart';
import '../widgets/token_status_card.dart';

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

  MorphRuntime get _rt => widget.morph.runtime;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _rt.getTokenStatus();
      if (mounted) setState(() => _tokenStatus = status);
    } catch (e) {
      _setMessage('Error refreshing status: $e');
    }
  }

  void _setMessage(String msg) {
    if (mounted) setState(() => _message = msg);
  }

  void _setBusy(bool v) {
    if (mounted) setState(() => _busy = v);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _acquireDeviceToken() async {
    _setBusy(true);
    _setMessage('');
    try {
      await _rt.tokens.acquireWithClientCredentials(
        'morph-auth/device',
        _rt.resolved.contextByAuthId['morph-auth/device']!,
      );
      _setMessage('Device token acquired.');
    } catch (e) {
      _setMessage('Acquire device token failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  Future<void> _login() async {
    const authId = 'morph-auth/2fa';
    try {
      final url = _rt.getAuthorizationUrl(authId);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _setMessage('Could not open browser for login.');
      }
    } catch (e) {
      _setMessage('Login failed: $e');
    }
  }

  Future<void> _exchangeToken() async {
    _setBusy(true);
    _setMessage('');
    try {
      await _rt.tokens.exchangeToken(
        'morph-auth/2fa',
        _rt.resolved.contextByAuthId['morph-auth/2fa']!,
        'morph-auth/1fa',
      );
      _setMessage('Token exchange complete (2fa → 1fa).');
    } catch (e) {
      _setMessage('Token exchange failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  Future<void> _logout(String authId) async {
    _setBusy(true);
    _setMessage('');
    try {
      final ref = _rt.resolved.contextByAuthId[authId];
      if (ref != null) {
        await _rt.tokens.logout(authId, ref, 'user-initiated');
        _setMessage('Logged out ($authId).');
      }
    } catch (e) {
      _setMessage('Logout failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  Future<void> _callMockApi() async {
    _setBusy(true);
    _setMessage('');
    try {
      final host = _rt.getHost('main-api');
      final response = await _rt.http.hostFetch<dynamic>(
        host,
        '/ping',
        method: 'GET',
      );
      _setMessage('Mock API → ${response.statusCode}: ${response.body}');
    } catch (e) {
      _setMessage('Mock API call failed: $e');
    } finally {
      _setBusy(false);
      await _refreshStatus();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasDevice = _tokenStatus
        .any((s) => s.authId == 'morph-auth/device' && s.hasAccessToken);
    final has2fa = _tokenStatus
        .any((s) => s.authId == 'morph-auth/2fa' && s.hasAccessToken);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Morph Flutter PoC'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh token status',
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
              // ── Token status ──
              _SectionHeader('Token Status'),
              if (_tokenStatus.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Loading…'),
                )
              else
                ..._tokenStatus.map(
                  (s) => TokenStatusCard(
                    status: s,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => TokenClaimsSheet(status: s),
                    ),
                  ),
                ),

              // ── Actions ──
              _SectionHeader('Actions'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _ActionButton(
                      label: 'Acquire Device Token',
                      icon: Icons.devices,
                      onPressed: _busy ? null : _acquireDeviceToken,
                    ),
                    _ActionButton(
                      label: 'Login (2fa)',
                      icon: Icons.login,
                      onPressed: _busy ? null : _login,
                    ),
                    _ActionButton(
                      label: 'Exchange → 1fa',
                      icon: Icons.swap_horiz,
                      onPressed: (_busy || !has2fa) ? null : _exchangeToken,
                    ),
                    _ActionButton(
                      label: 'Logout 2fa',
                      icon: Icons.logout,
                      onPressed: (_busy || !has2fa)
                          ? null
                          : () => _logout('morph-auth/2fa'),
                    ),
                    _ActionButton(
                      label: 'Logout Device',
                      icon: Icons.device_unknown,
                      onPressed: (_busy || !hasDevice)
                          ? null
                          : () => _logout('morph-auth/device'),
                    ),
                  ],
                ),
              ),

              // ── Mock API ──
              _SectionHeader('Mock API'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('GET /ping'),
                  onPressed: _busy ? null : _callMockApi,
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

              // ── HTTP trace ──
              _SectionHeader('HTTP Trace'),
              StatefulBuilder(
                builder: (_, refresh) => HttpTraceLog(
                  traces: List.from(morphHttpTraces),
                  onClear: () {
                    morphHttpTraces.clear();
                    refresh(() {});
                  },
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
