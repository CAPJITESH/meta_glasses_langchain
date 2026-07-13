import 'dart:typed_data';

/// Lifecycle state of the DAT device session + camera stream.
enum GlassesConnectionState { idle, connecting, connected, streaming, error }

/// Resolution preset for [MetaWearablesCamera.startStream], mirroring the
/// native `VideoQuality` enum (LOW = 360x640, MEDIUM = 504x896, HIGH =
/// 720x1280).
enum GlassesVideoQuality { low, medium, high }

/// A single video frame from the glasses camera stream.
class GlassesVideoFrame {
  /// Raw frame bytes: decoded YUV if the stream wasn't configured to
  /// compress, or an HEVC buffer if [isCompressed] is true.
  final Uint8List bytes;
  final int width;
  final int height;

  /// Presentation timestamp in microseconds.
  final int timestampUs;
  final bool isCompressed;

  const GlassesVideoFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.timestampUs,
    required this.isCompressed,
  });
}

/// A captured still photo from [MetaWearablesCamera.capturePhoto].
class GlassesPhoto {
  /// HEIC-encoded bytes if [isHeic] is true, otherwise a decoded bitmap
  /// (PNG-encoded on the native side for transport).
  final Uint8List bytes;
  final bool isHeic;

  const GlassesPhoto({required this.bytes, required this.isHeic});
}
