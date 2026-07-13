import 'dart:typed_data';

/// Which side of the listen/speak cycle the glasses' Bluetooth audio link is in.
///
/// A2DP (speaker) and HFP (mic) are mutually exclusive on the underlying
/// Bluetooth Classic link, so the plugin models this as one mode at a time
/// rather than independent mic/speaker states.
enum GlassesAudioMode { idle, listening, speaking }

/// Which Bluetooth profile currently owns the audio link.
enum GlassesAudioRoute { none, a2dpSpeaker, hfpMicSpeaker }

/// Snapshot of the glasses' audio mode/route, as reported by the native side.
class GlassesAudioState {
  final GlassesAudioMode mode;
  final GlassesAudioRoute route;

  /// True once the Bluetooth route has been confirmed active by the OS.
  ///
  /// HFP takes ~1.5-2s to settle after being requested; this is what call
  /// sites should await before assuming mic capture is actually flowing.
  final bool isRouteSettled;

  const GlassesAudioState(this.mode, this.route, this.isRouteSettled);

  @override
  String toString() =>
      'GlassesAudioState(mode: $mode, route: $route, isRouteSettled: $isRouteSettled)';
}

/// A chunk of raw microphone audio captured from the glasses over HFP.
class GlassesAudioChunk {
  /// 16-bit PCM, mono.
  final Uint8List pcm16;

  /// Fixed at 8000 for HFP — a Bluetooth Classic profile limitation, not
  /// something this plugin can improve.
  final int sampleRateHz;

  final int timestampMs;

  const GlassesAudioChunk(this.pcm16, this.sampleRateHz, this.timestampMs);
}
