import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/llm_model.dart';
import '../../../core/services/file_download_service.dart';
import '../../../core/services/storage_service.dart';

export '../../../core/services/file_download_service.dart';

const String _modelStorageKey = 'downloaded_llm_model';

class LlmDownloadRepository {
  final FileDownloadService _fileDownloadService;
  final StorageService _storageService;
  CancelToken? _cancelToken;

  late LlmModel _defaultModel;

  LlmDownloadRepository({
    FileDownloadService? fileDownloadService,
    StorageService? storageService,
  })  : _fileDownloadService = fileDownloadService ?? FileDownloadService(),
        _storageService = storageService ?? StorageService();

  Future<void> init() async {
    _defaultModel = LlmModel(
      id: 'qwen2.5-1.5b-instruct-q4_k_m',
      displayName: 'Qwen2.5 1.5B Instruct (Q4_K_M)',
      downloadUrl:
          'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      approxSizeBytes: 1_000_000_000, // ~1GB estimate
    );
  }

  LlmModel getDefaultModel() => _defaultModel;

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
              await _storageService.setString(
                _modelStorageKey,
                updatedModel.toJsonString(),
              );
            }
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<LlmModel?> getSavedModel() async {
    try {
      final jsonString = await _storageService.getString(_modelStorageKey);
      if (jsonString == null) {
        // Check if model exists in default location (for iOS path compatibility)
        return _getModelFromDefaultLocation();
      }

      final model = LlmModel.fromJsonString(jsonString);

      // Verify file still exists at stored path
      if (model.localPath != null) {
        final exists = await _fileDownloadService.fileExists(model.localPath!);
        if (exists) {
          return model;
        }
      }

      // Try to find model in default location as fallback
      final fallback = await _getModelFromDefaultLocation();
      if (fallback != null) {
        // Update storage with new path
        await _storageService.setString(
          _modelStorageKey,
          fallback.toJsonString(),
        );
        return fallback;
      }

      // File was deleted or not found, reset the model
      await _storageService.remove(_modelStorageKey);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<LlmModel?> _getModelFromDefaultLocation() async {
    try {
      final saveDir = await getApplicationDocumentsDirectory();
      final defaultFileName = 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';
      final modelPath = '${saveDir.path}/models/$defaultFileName';
      final exists = await _fileDownloadService.fileExists(modelPath);
      if (exists) {
        return _defaultModel.copyWith(
          localPath: modelPath,
          isDownloaded: true,
        );
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
      await _storageService.remove(_modelStorageKey);
    } catch (e) {
      rethrow;
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('Download cancelled by user');
  }
}
