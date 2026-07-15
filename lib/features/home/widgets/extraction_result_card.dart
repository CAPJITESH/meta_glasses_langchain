/// lib/features/home/widgets/extraction_result_card.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../app/theme.dart';
import '../models/extraction_result.dart';

class ExtractionResultCard extends StatelessWidget {
  final HomeExtractionView result;

  const ExtractionResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    final theme = Theme.of(context);
    final phaseColors = theme.extension<PhaseColors>()!;
    // Same traffic-light logic as the confidence gate: green above the
    // fallback threshold, amber borderline, red is a server-fallback turn.
    final confidenceColor = result.confidence >= 0.75
        ? phaseColors.speaking
        : result.confidence >= 0.5
            ? phaseColors.thinking
            : phaseColors.error;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${result.transcript}"', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppTheme.s2),
            Text(
              result.glassesMessage,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text(result.intent)),
                Chip(
                  avatar: Icon(Icons.circle, size: 10, color: confidenceColor),
                  label: Text(
                    'confidence ${result.confidence.toStringAsFixed(2)}',
                  ),
                ),
                if (result.humanTime != null)
                  Chip(label: Text(result.humanTime!)),
                if (result.usedServerFallback)
                  Chip(
                    avatar: Icon(
                      Icons.cloud_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    label: const Text('server fallback'),
                  ),
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
