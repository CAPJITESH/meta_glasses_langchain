import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../data/llm_download_repository.dart';
import '../models/llm_model.dart';
import '../widgets/download_progress_widget.dart';

class DownloadLlmNotifier extends ChangeNotifier {
  final LlmDownloadRepository _repository;

  LlmModel? _model;
  DownloadProgress? _progress;
  bool _isLoading = true;
  String? _error;

  DownloadLlmNotifier(this._repository);

  LlmModel? get model => _model;
  DownloadProgress? get progress => _progress;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.init();
      final saved = await _repository.getSavedModel();

      if (saved != null && saved.isDownloaded) {
        _model = saved;
      } else {
        _model = _repository.getDefaultModel();
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load model: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startDownload() async {
    if (_model == null) return;

    _progress = null;
    _error = null;
    notifyListeners();

    try {
      await for (final progress in _repository.downloadModel(_model!)) {
        _progress = progress;
        notifyListeners();

        if (progress.status == DownloadStatus.completed) {
          _model = _model!.copyWith(isDownloaded: true);
          notifyListeners();
          break;
        }

        if (progress.status == DownloadStatus.failed) {
          _error = 'Download failed';
          notifyListeners();
          break;
        }
      }
    } catch (e) {
      _error = 'Download error: $e';
      _progress = null;
      notifyListeners();
    }
  }

  Future<void> deleteModel() async {
    if (_model == null) return;

    try {
      await _repository.deleteModel(_model!);
      _model = _repository.getDefaultModel();
      _progress = null;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete model: $e';
      notifyListeners();
    }
  }

  void cancelDownload() {
    _repository.cancelDownload();
  }
}

class DownloadLlmScreen extends StatefulWidget {
  final VoidCallback? onDownloadComplete;

  const DownloadLlmScreen({
    super.key,
    this.onDownloadComplete,
  });

  @override
  State<DownloadLlmScreen> createState() => _DownloadLlmScreenState();
}

class _DownloadLlmScreenState extends State<DownloadLlmScreen> {
  late DownloadLlmNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DownloadLlmNotifier(LlmDownloadRepository());
    _notifier.addListener(_onNotifierChanged);
    _notifier.init();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onNotifierChanged);
    _notifier.dispose();
    super.dispose();
  }

  void _onNotifierChanged() {
    if (_notifier.progress?.status == DownloadStatus.completed) {
      widget.onDownloadComplete?.call();
      if (mounted) {
        // Navigate to glasses after model download completes
        Navigator.of(context).pushNamedAndRemoveUntil('/glasses', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-device Model')),
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          if (_notifier.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (_notifier.error != null && _notifier.progress == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _notifier.error ?? 'An error occurred',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _notifier.init,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final model = _notifier.model;
          final progress = _notifier.progress;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model: ${model?.displayName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'File: ${model?.fileName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Size: ~${((model?.approxSizeBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (model != null && model.isDownloaded)
                  Column(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 48,
                        color: Theme.of(context)
                            .extension<PhaseColors>()!
                            .speaking,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Model Downloaded',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _notifier.deleteModel,
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                              child: const Text('Delete model'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pushNamedAndRemoveUntil('/glasses', (route) => false);
                              },
                              child: const Text('Go to glasses'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (progress != null &&
                    progress.status != DownloadStatus.completed)
                  Column(
                    children: [
                      DownloadProgressWidget(
                        received: progress.received,
                        total: progress.total,
                        status: progress.status,
                      ),
                      const SizedBox(height: 32),
                      if (progress.status == DownloadStatus.downloading)
                        OutlinedButton(
                          onPressed: () {
                            _notifier.cancelDownload();
                            _notifier.init();
                          },
                          child: const Text('Cancel download'),
                        ),
                      if (progress.status == DownloadStatus.paused)
                        Column(
                          children: [
                            Text(
                              'Download paused',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _notifier.startDownload,
                              child: const Text('Resume download'),
                            ),
                          ],
                        ),
                      if (progress.status == DownloadStatus.failed)
                        Column(
                          children: [
                            Text(
                              'Download failed',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _notifier.startDownload,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Icon(
                        Icons.download,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ready to download',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloads once, then everything runs on-device.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _notifier.startDownload,
                          child: const Text('Download model'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
