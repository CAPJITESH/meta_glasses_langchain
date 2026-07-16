import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../data/llm_download_repository.dart';
import '../models/llm_model.dart';
import '../widgets/download_progress_widget.dart';

class DownloadLlmNotifier extends ChangeNotifier {
  final LlmDownloadRepository _repository;

  List<LlmModel> _availableModels = [];
  LlmModel? _selectedLlmModel;
  LlmModel? _selectedEmbeddingModel;
  LlmModel? _downloadedLlmModel;
  LlmModel? _downloadedEmbeddingModel;
  DownloadProgress? _progress;
  bool _isLoading = true;
  String? _error;
  bool _showModelSelection = true;
  bool _isDownloadingBoth = false;

  DownloadLlmNotifier(this._repository);

  List<LlmModel> get availableModels => _availableModels;
  LlmModel? get selectedLlmModel => _selectedLlmModel;
  LlmModel? get selectedEmbeddingModel => _selectedEmbeddingModel;
  LlmModel? get downloadedLlmModel => _downloadedLlmModel;
  LlmModel? get downloadedEmbeddingModel => _downloadedEmbeddingModel;
  DownloadProgress? get progress => _progress;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get showModelSelection => _showModelSelection;
  bool get isDownloadingBoth => _isDownloadingBoth;
  bool get hasDownloadedModels =>
      (_downloadedLlmModel?.isDownloaded == true) &&
      (_downloadedEmbeddingModel?.isDownloaded == true);

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.init();
      _availableModels = _repository.getAvailableModels();
      _selectedLlmModel = _repository.getSelectedLlmModel();
      _selectedEmbeddingModel = _repository.getDefaultEmbeddingModel();

      _downloadedLlmModel = await _repository.getSavedLlmModel();
      _downloadedEmbeddingModel = await _repository.getSavedEmbeddingModel();

      // If both models downloaded, skip selection
      if (_downloadedLlmModel?.isDownloaded == true &&
          _downloadedEmbeddingModel?.isDownloaded == true) {
        _selectedLlmModel = _downloadedLlmModel;
        _selectedEmbeddingModel = _downloadedEmbeddingModel;
        _showModelSelection = false;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load models: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectLlmModel(LlmModel model) async {
    if (_downloadedLlmModel != null &&
        _downloadedLlmModel!.isDownloaded &&
        _downloadedLlmModel!.id != model.id) {
      _selectedLlmModel = model;
      await _repository.selectLlmModel(model);
      notifyListeners();
    } else {
      _selectedLlmModel = model;
      await _repository.selectLlmModel(model);
      notifyListeners();
    }
  }

  Future<void> confirmSelectionAndDownload() async {
    if (_selectedLlmModel == null) return;

    _showModelSelection = false;
    _isDownloadingBoth = true;
    _progress = null;
    _error = null;
    notifyListeners();

    try {
      // Download LLM model first
      await for (final progress in _repository.downloadModel(
        _selectedLlmModel!,
      )) {
        _progress = progress;
        notifyListeners();

        if (progress.status == DownloadStatus.completed) {
          _downloadedLlmModel = await _repository.getSavedLlmModel();
          _selectedLlmModel = _downloadedLlmModel;
          break;
        }

        if (progress.status == DownloadStatus.failed) {
          _error = 'LLM download failed';
          _isDownloadingBoth = false;
          notifyListeners();
          return;
        }
      }

      // Then download embedding model
      if (_selectedEmbeddingModel != null) {
        await for (final progress in _repository.downloadModel(
          _selectedEmbeddingModel!,
        )) {
          _progress = progress;
          notifyListeners();

          if (progress.status == DownloadStatus.completed) {
            _downloadedEmbeddingModel = await _repository
                .getSavedEmbeddingModel();
            _selectedEmbeddingModel = _downloadedEmbeddingModel;
            break;
          }

          if (progress.status == DownloadStatus.failed) {
            _error = 'Embedding download failed';
            _isDownloadingBoth = false;
            notifyListeners();
            return;
          }
        }
      }

      _isDownloadingBoth = false;
      notifyListeners();
    } catch (e) {
      _error = 'Download error: $e';
      _isDownloadingBoth = false;
      _progress = null;
      notifyListeners();
    }
  }

  Future<void> goBackToSelection() async {
    _showModelSelection = true;
    _isDownloadingBoth = false;
    _progress = null;
    _error = null;
    notifyListeners();
  }

  Future<void> deleteModels() async {
    if (_downloadedLlmModel != null) {
      await _repository.deleteModel(_downloadedLlmModel!);
    }
    if (_downloadedEmbeddingModel != null) {
      await _repository.deleteModel(_downloadedEmbeddingModel!);
    }
    _downloadedLlmModel = null;
    _downloadedEmbeddingModel = null;
    _selectedLlmModel =
        _repository.getSelectedLlmModel() ??
        _availableModels.firstWhere((m) => m.type == ModelType.llm);
    _selectedEmbeddingModel = _repository.getDefaultEmbeddingModel();
    _showModelSelection = true;
    _progress = null;
    _error = null;
    notifyListeners();
  }

  Future<void> switchModel() async {
    _showModelSelection = true;
    _selectedLlmModel =
        _repository.getSelectedLlmModel() ??
        _availableModels.firstWhere((m) => m.type == ModelType.llm);
    notifyListeners();
  }

  void cancelDownload() {
    _repository.cancelDownload();
  }
}

class DownloadLlmScreen extends StatefulWidget {
  final VoidCallback? onDownloadComplete;

  const DownloadLlmScreen({super.key, this.onDownloadComplete});

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
    if (_notifier.hasDownloadedModels) {
      widget.onDownloadComplete?.call();
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/glasses', (route) => false);
      }
    }
  }

  void _showSwitchConfirmation(LlmModel model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Model?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You currently have "${_notifier.downloadedLlmModel?.displayName}" downloaded.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Only ONE LLM model can be stored on-device at a time to save storage space. '
              'Switching will DELETE the current LLM model and download the new one. '
              'The embedding model will be re-downloaded if needed.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text('New model: ${model.displayName}'),
            Text(
              'Size: ~${(_notifier.availableModels.firstWhere((m) => m.id == model.id).approxSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _notifier.selectLlmModel(model);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Switch & Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('On-device Model'),
        leading: _notifier.showModelSelection
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _notifier.goBackToSelection,
              ),
      ),
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          if (_notifier.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_notifier.error != null &&
              _notifier.progress == null &&
              !_notifier.isDownloadingBoth) {
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

          final downloadedLlm = _notifier.downloadedLlmModel;
          final downloadedEmbedding = _notifier.downloadedEmbeddingModel;
          final selectedLlm = _notifier.selectedLlmModel;
          final selectedEmbedding = _notifier.selectedEmbeddingModel;
          final progress = _notifier.progress;
          final showSelection = _notifier.showModelSelection;
          final isDownloadingBoth = _notifier.isDownloadingBoth;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                if (showSelection) ...[
                  // Model Selection Screen
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
                          'Select LLM Model',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Only ONE LLM model can be stored on-device at a time to save storage space. '
                          'The embedding model (BGE Small) will be automatically downloaded with your selected LLM.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        // LLM Models
                        Text(
                          'LLM Models (for intent classification)',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        ..._notifier.availableModels
                            .where((m) => m.type == ModelType.llm)
                            .map(
                              (model) => _ModelTile(
                                model: model,
                                isSelected: selectedLlm?.id == model.id,
                                isDownloaded:
                                    downloadedLlm?.id == model.id &&
                                    downloadedLlm?.isDownloaded == true,
                                onTap: () {
                                  if (downloadedLlm != null &&
                                      downloadedLlm.isDownloaded &&
                                      downloadedLlm.id != model.id) {
                                    _showSwitchConfirmation(model);
                                  } else {
                                    _notifier.selectLlmModel(model);
                                  }
                                },
                              ),
                            ),
                        const SizedBox(height: 16),
                        // Embedding Model Info (Auto-selected)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Embedding Model',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      selectedEmbedding?.displayName ??
                                          'BGE Small EN v1.5 (Q8_0)',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Size: ~${((selectedEmbedding?.approxSizeBytes ?? 150000000) / (1024 * 1024)).toStringAsFixed(0)} MB • Auto-downloaded with LLM',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: selectedLlm != null
                                ? () => _notifier.confirmSelectionAndDownload()
                                : null,
                            child: const Text('Confirm & Download Both'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Download Progress / Downloaded State
                  // LLM Model Info
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedLlm?.displayName ?? 'No model selected',
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (downloadedLlm?.isDownloaded == true)
                              Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedLlm?.fileName ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Size: ~${((selectedLlm?.approxSizeBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        // Embedding Model Info
                        if (selectedEmbedding != null) ...[
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Embedding: ${selectedEmbedding.displayName}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (downloadedEmbedding?.isDownloaded == true)
                                Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 16,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: ~${((selectedEmbedding.approxSizeBytes) / (1024 * 1024)).toStringAsFixed(0)} MB',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (downloadedLlm != null &&
                      downloadedLlm.isDownloaded &&
                      downloadedEmbedding != null &&
                      downloadedEmbedding.isDownloaded)
                    Column(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).extension<PhaseColors>()!.speaking,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Both Models Downloaded',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'LLM + Embedding models ready for on-device use',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _notifier.switchModel(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                                child: const Text('Switch LLM Model'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _notifier.deleteModels,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                                child: const Text('Delete All'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/glasses',
                                (route) => false,
                              );
                            },
                            child: const Text('Go to Glasses'),
                          ),
                        ),
                      ],
                    )
                  else if (progress != null &&
                      progress.status != DownloadStatus.completed)
                    Column(
                      children: [
                        if (isDownloadingBoth) ...[
                          Text(
                            downloadedLlm?.isDownloaded == true
                                ? 'Downloading Embedding Model...'
                                : 'Downloading LLM Model...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
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
                                onPressed:
                                    _notifier.confirmSelectionAndDownload,
                                child: const Text('Resume download'),
                              ),
                            ],
                          ),
                        if (progress.status == DownloadStatus.failed)
                          Column(
                            children: [
                              Text(
                                _notifier.error ?? 'Download failed',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed:
                                    _notifier.confirmSelectionAndDownload,
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
                            onPressed: _notifier.confirmSelectionAndDownload,
                            child: const Text('Download both models'),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final LlmModel model;
  final bool isSelected;
  final bool isDownloaded;
  final VoidCallback onTap;

  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.isDownloaded,
    required this.onTap,
  });

  String _formatSize(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: model.id,
              groupValue: isSelected ? model.id : null,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isDownloaded) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Downloaded',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Size: ~${_formatSize(model.approxSizeBytes)}  •  LLM',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
