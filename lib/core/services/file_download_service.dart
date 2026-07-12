import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';

enum DownloadStatus { downloading, completed, failed, paused }

class DownloadProgress {
  final int received;
  final int total;
  final double percentage;
  final DownloadStatus status;

  DownloadProgress({
    required this.received,
    required this.total,
    required this.percentage,
    required this.status,
  });
}

class FileDownloadService {
  final Dio _dio = Dio();

  Stream<DownloadProgress> download({
    required String url,
    required String savePath,
    CancelToken? cancelToken,
  }) {
    return _performDownload(url, savePath, cancelToken);
  }

  Stream<DownloadProgress> _performDownload(
    String url,
    String savePath,
    CancelToken? cancelToken,
  ) async* {
    try {
      final file = File(savePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Check for partial download
      int startByte = 0;
      if (await file.exists()) {
        startByte = await file.length();
      }

      // Get total file size
      final headResponse = await _dio.head(url);
      final totalSize = int.parse(headResponse.headers.value('content-length') ?? '0');

      if (totalSize == 0) {
        yield DownloadProgress(
          received: 0,
          total: 0,
          percentage: 0,
          status: DownloadStatus.failed,
        );
        return;
      }

      // Download with resume support
      final headers = startByte > 0 ? {'Range': 'bytes=$startByte-'} : null;

      final streamController = StreamController<DownloadProgress>();

      _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          final adjustedReceived = startByte + received;
          final percentage = adjustedReceived / totalSize;

          streamController.add(DownloadProgress(
            received: adjustedReceived,
            total: totalSize,
            percentage: percentage.clamp(0.0, 1.0),
            status: DownloadStatus.downloading,
          ));
        },
      ).then((_) {
        streamController.add(DownloadProgress(
          received: totalSize,
          total: totalSize,
          percentage: 1.0,
          status: DownloadStatus.completed,
        ));
        streamController.close();
      }).catchError((e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          streamController.add(DownloadProgress(
            received: 0,
            total: 0,
            percentage: 0,
            status: DownloadStatus.paused,
          ));
        } else {
          streamController.add(DownloadProgress(
            received: 0,
            total: 0,
            percentage: 0,
            status: DownloadStatus.failed,
          ));
        }
        streamController.close();
      });

      yield* streamController.stream;
    } catch (e) {
      yield DownloadProgress(
        received: 0,
        total: 0,
        percentage: 0,
        status: DownloadStatus.failed,
      );
    }
  }

  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  Future<bool> fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }
}
