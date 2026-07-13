/// lib/features/home/screens/home_screen.dart
library;

import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../data/home_repository.dart';
import '../models/extraction_result.dart';
import '../widgets/extraction_result_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeRepository _repository = HomeRepository();
  final TextEditingController _transcriptController = TextEditingController();

  final List<HomeExtractionView> _history = [];

  bool _modelLoading = true;
  String? _modelError;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    setState(() {
      _modelLoading = true;
      _modelError = null;
    });
    try {
      await _repository.ensureModelLoaded();
      setState(() => _modelLoading = false);
    } catch (e) {
      setState(() {
        _modelLoading = false;
        _modelError = e.toString();
      });
    }
  }

  void _goToDownloadModel() {
    Navigator.pushNamed(context, '/download-model');
  }

  Future<void> _runExtraction() async {
    final transcript = _transcriptController.text.trim();
    if (transcript.isEmpty || _running) return;

    setState(() => _running = true);
    try {
      final result = await _repository.runExtraction(transcript: transcript);
      setState(() {
        _history.insert(0, result);
        _transcriptController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Extraction failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Type to the Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Back to glasses',
            onPressed: () => Navigator.pushNamed(context, '/glasses'),
          ),
        ],
      ),
      body: _modelLoading
          ? const Center(child: CircularProgressIndicator())
          : _modelError != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.downloading_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.s4),
            Text('The model isn\'t ready', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.s2),
            Text(
              _modelError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.s5),
            FilledButton(onPressed: _loadModel, child: const Text('Retry')),
            const SizedBox(height: AppTheme.s2),
            OutlinedButton(
              onPressed: _goToDownloadModel,
              child: const Text('Go to model download'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _transcriptController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What did the user say?',
                  hintText: 'e.g. "Remind me to call mom tomorrow at 5pm"',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _runExtraction(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _running ? null : _runExtraction,
                  child: _running
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Run'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _history.isEmpty
              ? const _EmptyHistory()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) =>
                      ExtractionResultCard(result: _history[index]),
                ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

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
                Icons.chat_bubble_outline,
                size: 30,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppTheme.s5),
            Text('Try the assistant', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTheme.s2),
            Text(
              'Type what you would say to the glasses —\n'
              '"Set a timer for 10 minutes" or "Remember my wifi password."',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
