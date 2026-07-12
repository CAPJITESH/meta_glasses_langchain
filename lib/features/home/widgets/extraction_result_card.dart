/// lib/features/home/widgets/extraction_result_card.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/extraction_result.dart';

class ExtractionResultCard extends StatelessWidget {
  final HomeExtractionView result;

  const ExtractionResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.glassesMessage,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('intent: ${result.intent}')),
                Chip(label: Text('confidence: ${result.confidence.toStringAsFixed(2)}')),
                if (result.humanTime != null)
                  Chip(label: Text('time: ${result.humanTime}')),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Parameters'),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text(
                    encoder.convert(result.parameters),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Raw model output'),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text(
                    result.raw,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
