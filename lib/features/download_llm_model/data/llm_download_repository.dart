import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/llm_model.dart';
import '../../../core/services/file_download_service.dart';
import '../../../core/services/storage_service.dart';

export '../../../core/services/file_download_service.dart';

const String _llmModelStorageKey = 'downloaded_llm_model';
const String _embeddingModelStorageKey = 'downloaded_embedding_model';
const String _selectedLlmModelIdKey = 'selected_llm_model_id';

class LlmDownloadRepository {
  final FileDownloadService _fileDownloadService;
  final StorageService _storageService;
  CancelToken? _cancelToken;

  late final List<LlmModel> _availableModels;
  LlmModel? _selectedLlmModel;

  LlmDownloadRepository({
    FileDownloadService? fileDownloadService,
    StorageService? storageService,
  })  : _fileDownloadService = fileDownloadService ?? FileDownloadService(),
        _storageService = storageService ?? StorageService();

  Future<void> init() async {
    _availableModels = [
      // LLM Models for intent classification
      LlmModel(
        id: 'qwen2.5-1.5b-instruct-q4_k_m',
        displayName: 'Qwen2.5 1.5B Instruct (Q4_K_M)',
        downloadUrl:
            'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
        fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
        approxSizeBytes: 1_000_000_000, // ~1GB
        type: ModelType.llm,
      ),
      LlmModel(
        id: 'qwen2.5-0.5b-instruct-q8_0',
        displayName: 'Qwen2.5 0.5B Instruct (Q8_0)',
        downloadUrl:
            'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf?download=true',
        fileName: 'qwen2.5-0.5b-instruct-q8_0.gguf',
        approxSizeBytes: 600_000_000, // ~600MB
        type: ModelType.llm,
      ),
      LlmModel(
        id: 'qwen2.5-0.5b-instruct-q5_k_m',
        displayName: 'Qwen2.5 0.5B Instruct (Q5_K_M)',
        downloadUrl:
            'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q5_k_m.gguf?download=true',
        fileName: 'qwen2.5-0.5b-instruct-q5_k_m.gguf',
        approxSizeBytes: 450_000_000, // ~450MB
        type: ModelType.llm,
      ),
      LlmModel(
        id: 'qwen3-0.6b-ud-q5_k_xl',
        displayName: 'Qwen3 0.6B (UD-Q5_K_XL)',
        downloadUrl:
            'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-UD-Q5_K_XL.gguf?download=true',
        fileName: 'Qwen3-0.6B-UD-Q5_K_XL.gguf',
        approxSizeBytes: 500_000_000, // ~500MB
        type: ModelType.llm,
      ),
      // Embedding model for semantic router
      LlmModel(
        id: 'bge-small-en-v1.5-q8_0',
        displayName: 'BGE Small EN v1.5 (Q8_0) - Embedding',
        downloadUrl:
            'https://huggingface.co/ggml-org/bge-small-en-v1.5-Q8_0-GGUF/resolve/main/bge-small-en-v1.5-q8_0.gguf?download=true',
        fileName: 'bge-small-en-v1.5-q8_0.gguf',
        approxSizeBytes: 150_000_000, // ~150MB
        type: ModelType.embedding,
      ),
    ];

    // Load previously selected LLM model ID
    final savedLlmModelId = await _storageService.getString(_selectedLlmModelIdKey);
    if (savedLlmModelId != null) {
      _selectedLlmModel = _availableModels.firstWhere(
        (m) => m.id == savedLlmModelId,
        orElse: () => _availableModels.firstWhere((m) => m.type == ModelType.llm),
      );
    } else {
      _selectedLlmModel = _availableModels.firstWhere((m) => m.type == ModelType.llm);
    }
  }

  List<LlmModel> getAvailableModels() => _availableModels;

  List<LlmModel> getAvailableModelsByType(ModelType type) =>
      _availableModels.where((m) => m.type == type).toList();

  LlmModel? getSelectedLlmModel() => _selectedLlmModel;

  LlmModel getDefaultEmbeddingModel() =>
      _availableModels.firstWhere((m) => m.type == ModelType.embedding);

  LlmModel getDefaultLlmModel() =>
      _availableModels.firstWhere((m) => m.type == ModelType.llm);

  Future<void> selectLlmModel(LlmModel model) async {
    // If selecting a different model, delete the currently downloaded one first
    if (_selectedLlmModel != null &&
        _selectedLlmModel!.id != model.id &&
        _selectedLlmModel!.isDownloaded &&
        _selectedLlmModel!.localPath != null) {
      await _deleteModelFile(_selectedLlmModel!);
    }

    _selectedLlmModel = model;
    await _storageService.setString(_selectedLlmModelIdKey, model.id);
  }

  Future<void> _deleteModelFile(LlmModel model) async {
    try {
      if (model.localPath != null) {
        await _fileDownloadService.deleteFile(model.localPath!);
      }
    } catch (e) {
      // Ignore deletion errors
    }
  }

  Stream<DownloadProgress> downloadModel(LlmModel model) async* {
    _cancelToken = CancelToken();

    try {
      // Use Documents directory for iOS compatibility
      final saveDir = await getApplicationDocumentsDirectory();
      final modelsDir = '${saveDir.path}/models';

      // Ensure models directory exists
      final modelsDirFile = Directory(modelsDir);
      if (!await modelsDirFile.exists()) {
        await modelsDirFile.create(recursive: true);
      }

      final savePath = '$modelsDir/${model.fileName}';

      await for (final progress in _fileDownloadService.download(
        url: model.downloadUrl,
        savePath: savePath,
        cancelToken: _cancelToken,
      )) {
        yield progress;

        if (progress.status == DownloadStatus.completed) {
          // Verify file exists before saving
          await Future.delayed(const Duration(milliseconds: 500));
          final fileExists = await _fileDownloadService.fileExists(savePath);
          if (fileExists) {
            final file = File(savePath);
            final fileSize = await file.length();
            // Only save if file is reasonably sized (at least 10MB for a model)
            if (fileSize > 10 * 1024 * 1024) {
              final updatedModel = model.copyWith(
                localPath: savePath,
                isDownloaded: true,
              );
              // Update the model in our list
              final index = _availableModels.indexWhere((m) => m.id == model.id);
              if (index != -1) {
                _availableModels[index] = updatedModel;
              }
              if (_selectedLlmModel?.id == model.id) {
                _selectedLlmModel = updatedModel;
              }
              // Save to appropriate storage key based on model type
              final storageKey = model.type == ModelType.llm
                  ? _llmModelStorageKey
                  : _embeddingModelStorageKey;
              await _storageService.setString(storageKey, updatedModel.toJsonString());
            }
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<LlmModel?> getSavedLlmModel() async {
    return _getSavedModel(_llmModelStorageKey);
  }

  Future<LlmModel?> getSavedEmbeddingModel() async {
    return _getSavedModel(_embeddingModelStorageKey);
  }

  Future<LlmModel?> _getSavedModel(String storageKey) async {
    try {
      final jsonString = await _storageService.getString(storageKey);
      if (jsonString == null) {
        return _getModelFromDefaultLocation(storageKey);
      }

      final model = LlmModel.fromJsonString(jsonString);

      // Verify file still exists at stored path
      if (model.localPath != null) {
        final exists = await _fileDownloadService.fileExists(model.localPath!);
        if (exists) {
          // Update our model list
          final index = _availableModels.indexWhere((m) => m.id == model.id);
          if (index != -1) {
            _availableModels[index] = model;
          }
          return model;
        }
      }

      // Try to find model in default location as fallback
      final fallback = await _getModelFromDefaultLocation(storageKey);
      if (fallback != null) {
        // Update storage with new path
        await _storageService.setString(storageKey, fallback.toJsonString());
        return fallback;
      }

      // File was deleted or not found, reset the model
      await _storageService.remove(storageKey);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<LlmModel?> _getModelFromDefaultLocation(String storageKey) async {
    try {
      final saveDir = await getApplicationDocumentsDirectory();
      // Check for any downloaded model in the models directory
      final modelsDir = Directory('${saveDir.path}/models');
      if (await modelsDir.exists()) {
        final files = await modelsDir.list().toList();
        for (final file in files) {
          if (file is File && file.path.endsWith('.gguf')) {
            final fileName = file.path.split('/').last;
            final matchingModel = _availableModels.firstWhere(
              (m) => m.fileName == fileName,
              orElse: () => _availableModels.first,
            );
            // Only return if it matches the expected type for this storage key
            final isLlm = storageKey == _llmModelStorageKey;
            final isLlmModel = matchingModel.type == ModelType.llm;
            if (isLlmModel == isLlm) {
              return matchingModel.copyWith(
                localPath: file.path,
                isDownloaded: true,
              );
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteModel(LlmModel model) async {
    try {
      if (model.localPath != null) {
        await _fileDownloadService.deleteFile(model.localPath!);
      }
      final storageKey = model.type == ModelType.llm
          ? _llmModelStorageKey
          : _embeddingModelStorageKey;
      await _storageService.remove(storageKey);
      // Reset the model in our list
      final index = _availableModels.indexWhere((m) => m.id == model.id);
      if (index != -1) {
        _availableModels[index] = model.copyWith(
          localPath: null,
          isDownloaded: false,
        );
      }
      if (_selectedLlmModel?.id == model.id) {
        _selectedLlmModel = _selectedLlmModel!.copyWith(
          localPath: null,
          isDownloaded: false,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('Download cancelled by user');
  }
}