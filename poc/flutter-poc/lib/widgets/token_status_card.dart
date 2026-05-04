import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

/// Labels that mirror the TS PoC `STATUS_LABELS` map.
const _kLabels = <String, String>{
  'morph-auth/device': 'Device',
  'morph-auth/2fa': 'Login (2fa)',
  'morph-auth/1fa': 'Session (1fa)',
  'google-auth/google': 'Google',
};

/// A card displaying the status of one [MorphTokenStatus] entry.
class TokenStatusCard extends StatelessWidget {
  const TokenStatusCard({super.key, required this.status, this.onTap});

  final MorphTokenStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = _kLabels[status.authId] ?? status.authId;
    final hasToken = status.hasAccessToken;
    final valid = status.accessLikelyValid;
    final expiry = _formatExp(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                hasToken
                    ? (valid ? Icons.check_circle : Icons.warning_amber)
                    : Icons.cancel_outlined,
                color: hasToken
                    ? (valid ? Colors.green : Colors.orange)
                    : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      hasToken ? expiry : 'No token',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (status.grantHint != null)
                Chip(
                  label: Text(
                    status.grantHint!,
                    style: const TextStyle(fontSize: 11),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatExp(MorphTokenStatus s) {
    final sec = s.jwtExp ?? s.expiresAt;
    if (sec == null) return 'No expiry info';
    final exp = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    final left = exp.difference(DateTime.now());
    final iso = '${exp.toUtc().toIso8601String().substring(0, 19)}Z';
    if (left.isNegative) {
      return '$iso (expired ${left.inSeconds.abs()}s ago)';
    }
    return '$iso (in ${left.inSeconds}s)';
  }
}

/// Bottom sheet showing JWT claims for the given [MorphTokenStatus].
class TokenClaimsSheet extends StatelessWidget {
  const TokenClaimsSheet({super.key, required this.status});

  final MorphTokenStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _kLabels[status.authId] ?? status.authId;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label — JWT claims',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (status.decodeError != null)
              Text('Decode error: ${status.decodeError}',
                  style: const TextStyle(color: Colors.red))
            else if (status.claims != null)
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: _JsonView(data: status.claims!),
                ),
              )
            else
              const Text('No claims available'),
          ],
        ),
      ),
    );
  }
}

class _JsonView extends StatelessWidget {
  const _JsonView({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    return SelectableText(
      encoder.convert(data),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }
}
