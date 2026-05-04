import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:morph_core/morph_core.dart';

class ProviderConfigSheet extends StatelessWidget {
  const ProviderConfigSheet({
    super.key,
    required this.morph,
    required this.providerKey,
  });

  final MorphClient morph;
  final String providerKey;

  @override
  Widget build(BuildContext context) {
    Object meta;
    try {
      final m = morph.getProviderMeta(providerKey);
      meta = {
        'key': m.key,
        'type': m.type,
        'baseUrl': m.baseUrl,
        if (m.authorizationBrowserBaseUrl != null)
          'authorizationBrowserBaseUrl': m.authorizationBrowserBaseUrl,
        if (m.tokenHttpBaseUrl != null)
          'tokenHttpBaseUrl': m.tokenHttpBaseUrl,
        'contexts': m.contexts
            .map((c) => {
                  'key': c.key,
                  'authId': c.authId,
                  if (c.clientId != null) 'clientId': c.clientId,
                  if (c.clientAuth != null) 'clientAuth': c.clientAuth,
                  if (c.audience != null) 'audience': c.audience,
                  if (c.scopes != null) 'scopes': c.scopes,
                })
            .toList(),
      };
    } catch (e) {
      meta = {'_error': e.toString()};
    }

    final formatted =
        const JsonEncoder.withIndent('  ').convert(meta);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Provider config',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          "morph.getProviderMeta('$providerKey')",
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    formatted,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
