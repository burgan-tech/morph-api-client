import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

/// Scrollable log of [MorphHttpTraceEvent] entries.
class HttpTraceLog extends StatefulWidget {
  const HttpTraceLog({super.key, required this.traces, this.onClear});

  final List<MorphHttpTraceEvent> traces;
  final VoidCallback? onClear;

  @override
  State<HttpTraceLog> createState() => _HttpTraceLogState();
}

class _HttpTraceLogState extends State<HttpTraceLog> {
  String? _expandedId;
  _TraceTab _tab = _TraceTab.request;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('HTTP Trace',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            const Spacer(),
            if (widget.onClear != null)
              TextButton(onPressed: widget.onClear, child: const Text('Clear')),
          ],
        ),
        if (widget.traces.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No traces yet.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.traces.length,
            itemBuilder: (_, i) => _TraceRow(
              event: widget.traces[i],
              expanded: _expandedId == _idFor(widget.traces[i], i),
              currentTab: _tab,
              onTap: () => setState(() {
                final id = _idFor(widget.traces[i], i);
                if (_expandedId == id) {
                  _expandedId = null;
                } else {
                  _expandedId = id;
                  _tab = _TraceTab.request;
                }
              }),
              onTabChange: (t) => setState(() => _tab = t),
            ),
          ),
      ],
    );
  }

  String _idFor(MorphHttpTraceEvent e, int index) =>
      '${e.method}-${e.url}-$index';
}

enum _TraceTab { request, response, body }

class _TraceRow extends StatelessWidget {
  const _TraceRow({
    required this.event,
    required this.expanded,
    required this.currentTab,
    required this.onTap,
    required this.onTabChange,
  });

  final MorphHttpTraceEvent event;
  final bool expanded;
  final _TraceTab currentTab;
  final VoidCallback onTap;
  final void Function(_TraceTab) onTabChange;

  Color _statusColor(int code) {
    if (code >= 200 && code < 300) return Colors.green;
    if (code >= 400 && code < 500) return Colors.orange;
    if (code >= 500) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final statusOk = event.statusCode >= 200 && event.statusCode < 300;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(event.statusCode).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${event.statusCode}',
                style: TextStyle(
                  color: _statusColor(event.statusCode),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              '${event.method} ${event.path}',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${event.hostKey} · ${event.durationMs}ms · ${event.authId}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!statusOk && event.networkError != null)
                  const Icon(Icons.error_outline,
                      size: 16, color: Colors.red),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16),
              ],
            ),
            onTap: onTap,
          ),
          if (expanded) _DetailPanel(event: event, tab: currentTab, onTabChange: onTabChange),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.event,
    required this.tab,
    required this.onTabChange,
  });

  final MorphHttpTraceEvent event;
  final _TraceTab tab;
  final void Function(_TraceTab) onTabChange;

  @override
  Widget build(BuildContext context) {
    const enc = JsonEncoder.withIndent('  ');

    String content;
    switch (tab) {
      case _TraceTab.request:
        content = enc.convert(event.requestHeaders);
      case _TraceTab.response:
        content = enc.convert(event.responseHeaders);
      case _TraceTab.body:
        final b = event.responseBody;
        content = b == null
            ? '(empty)'
            : b is Map || b is List
                ? enc.convert(b)
                : b.toString();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: _TraceTab.values.map((t) {
              final label = switch (t) {
                _TraceTab.request => 'Request headers',
                _TraceTab.response => 'Response headers',
                _TraceTab.body => 'Body',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: tab == t,
                  onSelected: (_) => onTabChange(t),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
