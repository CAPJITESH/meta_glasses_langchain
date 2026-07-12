import 'package:flutter/material.dart';
import '../../../core/services/file_download_service.dart';

class DownloadProgressWidget extends StatelessWidget {
  final int received;
  final int total;
  final DownloadStatus status;

  const DownloadProgressWidget({
    super.key,
    required this.received,
    required this.total,
    required this.status,
  });

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 MB';
    const int mb = 1024 * 1024;
    return '${(bytes / mb).toStringAsFixed(2)} MB';
  }

  double get _progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '${_formatBytes(received)} / ${_formatBytes(total)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}
