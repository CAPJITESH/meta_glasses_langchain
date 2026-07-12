import 'dart:convert';

class LlmModel {
  final String id;
  final String displayName;
  final String downloadUrl;
  final String fileName;
  final int approxSizeBytes;
  final String? localPath;
  final bool isDownloaded;

  LlmModel({
    required this.id,
    required this.displayName,
    required this.downloadUrl,
    required this.fileName,
    required this.approxSizeBytes,
    this.localPath,
    this.isDownloaded = false,
  });

  LlmModel copyWith({
    String? id,
    String? displayName,
    String? downloadUrl,
    String? fileName,
    int? approxSizeBytes,
    String? localPath,
    bool? isDownloaded,
  }) {
    return LlmModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      fileName: fileName ?? this.fileName,
      approxSizeBytes: approxSizeBytes ?? this.approxSizeBytes,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'downloadUrl': downloadUrl,
      'fileName': fileName,
      'approxSizeBytes': approxSizeBytes,
      'localPath': localPath,
      'isDownloaded': isDownloaded,
    };
  }

  factory LlmModel.fromJson(Map<String, dynamic> json) {
    return LlmModel(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      downloadUrl: json['downloadUrl'] as String,
      fileName: json['fileName'] as String,
      approxSizeBytes: json['approxSizeBytes'] as int,
      localPath: json['localPath'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory LlmModel.fromJsonString(String jsonString) {
    return LlmModel.fromJson(jsonDecode(jsonString));
  }
}
