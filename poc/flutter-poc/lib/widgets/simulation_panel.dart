import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

import '../poc_simulation.dart';

class SimulationPanel extends StatefulWidget {
  const SimulationPanel({
    super.key,
    required this.morph,
    required this.cfg,
    this.onStatusChanged,
  });

  final MorphClient morph;
  final PocSimulationConfig cfg;
  final VoidCallback? onStatusChanged;

  @override
  State<SimulationPanel> createState() => _SimulationPanelState();
}

class _SimulationPanelState extends State<SimulationPanel> {
  bool _running = false;
  bool _probe404Enabled = false;
  final List<PocSimStepResult> _results = [];
  String _sessionDeadMessage = '';

  List<PocSimStep> get _autoSteps => widget.cfg.steps
      .where((s) =>
          s is! PocSimFetchStep || !s.skipInAutoSim)
      .where((s) =>
          s is! PocSimHostStep || !s.skipInAutoSim)
      .where((s) {
        if (s is PocSimFetchStep && s.path == '/sim/not-found') {
          return _probe404Enabled;
        }
        return true;
      })
      .toList();

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
      _sessionDeadMessage = '';
    });

    for (final step in _autoSteps) {
      if (!mounted) break;
      final result = await runPocSimStep(widget.morph, widget.cfg, step);

      if (!mounted) break;
      setState(() => _results.add(result));

      // Session dead check
      if (result.status == 'AUTH') {
        final detail = result.detail ?? '';
        final isSessionDead = widget.cfg.sessionDeadAuthIds.any(
          (id) => step is PocSimHostStep && step.auth == id,
        );
        if (isSessionDead &&
            (detail.contains('invalid_grant') ||
                detail.contains('Token is not active'))) {
          setState(() => _sessionDeadMessage = widget.cfg.sessionDeadMessage);
          break;
        }
      }
    }

    if (mounted) {
      setState(() => _running = false);
      widget.onStatusChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              // Title lives in HomeScreen (`_SectionHeader('Simulation')`).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('404 probe',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                  Switch.adaptive(
                    value: _probe404Enabled,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _probe404Enabled = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 16),
                label: Text(_running ? 'Running…' : 'Run simulation'),
                onPressed: _running ? null : _runAll,
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _running
                      ? null
                      : () => setState(() {
                            _results.clear();
                            _sessionDeadMessage = '';
                          }),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ),
        if (_sessionDeadMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              _sessionDeadMessage,
              style: TextStyle(
                  fontSize: 12, color: colorScheme.error),
            ),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Column(
              children: _results
                  .map((r) => _ResultRow(result: r))
                  .toList(),
            ),
          ),
        if (_running && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});
  final PocSimStepResult result;

  @override
  Widget build(BuildContext context) {
    final isOk = !result.isError;
    final statusStr = result.status.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: isOk ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              result.label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusStr,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: isOk ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
          if (result.detail != null) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                result.detail!,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
