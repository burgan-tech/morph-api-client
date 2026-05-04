import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

import '../../morph_init.dart';
import '../poc_simulation.dart';
import 'http_trace_log.dart';

class MockApiSheet extends StatefulWidget {
  const MockApiSheet({super.key, required this.morph, required this.cfg});

  final MorphClient morph;
  final PocSimulationConfig cfg;

  @override
  State<MockApiSheet> createState() => _MockApiSheetState();
}

class _MockApiSheetState extends State<MockApiSheet> {
  bool _busy = false;
  String _message = '';
  bool _lastIsError = false;
  Object? _lastBody;

  Future<void> _run(PocSimStep step) async {
    setState(() {
      _busy = true;
      _message = '';
      _lastBody = null;
    });
    final result = await runPocSimStep(widget.morph, widget.cfg, step);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastIsError = result.isError;
      _message =
          '${result.status}${result.detail != null ? ' — ${result.detail}' : ''}';
      _lastBody = result.body;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mock API',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'docs/poc/poc-simulation.json',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Step buttons
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.cfg.steps.map((step) {
                  final isDanger = step is PocSimLogoutStep;
                  return FilledButton.tonal(
                    onPressed: _busy ? null : () => _run(step),
                    style: isDanger
                        ? FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.errorContainer,
                            foregroundColor:
                                Theme.of(context).colorScheme.onErrorContainer,
                          )
                        : null,
                    child: Text(step.label,
                        style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ),
            // Status message
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
            if (_message.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _message,
                  style: TextStyle(
                    fontSize: 12,
                    color: _lastIsError
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            if (_lastBody != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    _lastBody is Map || _lastBody is List
                        ? const JsonEncoder.withIndent('  ')
                            .convert(_lastBody)
                        : _lastBody.toString(),
                    style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            const Divider(height: 1),
            // HTTP trace log
            Expanded(
              child: StatefulBuilder(
                builder: (_, refresh) => HttpTraceLog(
                  traces: List.from(morphHttpTraces),
                  onClear: () {
                    morphHttpTraces.clear();
                    refresh(() {});
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
