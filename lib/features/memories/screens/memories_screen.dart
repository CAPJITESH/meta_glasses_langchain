/// lib/features/memories/screens/memories_screen.dart
///
/// What the assistant remembers, as a product surface (Section 10). The empty
/// state is a designed moment that teaches the feature — not a bare fallback
/// string — and each entry can be forgotten with one tap.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/services/memory_store.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final MemoryStore _store = MemoryStore.instance;

  @override
  Widget build(BuildContext context) {
    final entries = _store.allEntries();
    return Scaffold(
      appBar: AppBar(title: const Text('Memories')),
      body: entries.isEmpty
          ? const _EmptyMemories()
          : ListView.separated(
              padding: const EdgeInsets.all(AppTheme.s4),
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppTheme.s3),
              itemBuilder: (context, index) =>
                  _MemoryCard(entry: entries[index], onForget: _forget),
            ),
    );
  }

  void _forget(MemoryEntry entry) {
    setState(() => _store.forget(entry.topic));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Forgot "${entry.topic}".')),
    );
  }
}

class _EmptyMemories extends StatelessWidget {
  const _EmptyMemories();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppTheme.s5),
            Text('Nothing remembered yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.s2),
            Text(
              'Ask the glasses to keep something for you —\n'
              '"Remember my parking spot is on level 3."',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.entry, required this.onForget});

  final MemoryEntry entry;
  final void Function(MemoryEntry) onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.s4,
          AppTheme.s3,
          AppTheme.s2,
          AppTheme.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.topic.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppTheme.s1),
                  Text(entry.content, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Forget',
              onPressed: () => onForget(entry),
            ),
          ],
        ),
      ),
    );
  }
}
