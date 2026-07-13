import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'glasses_audio_types.dart';

/// Glasses microphone (HFP) and speaker (A2DP) access via standard Android/iOS
/// Bluetooth audio profiles.
///
/// Mic and speaker do NOT go through the DAT camera streaming API — they're
/// reached through the system Bluetooth stack, and A2DP/HFP are mutually
/// exclusive. See the plugin README for the full explanation. Callers should
/// treat [startListening]/[speak] as sequential (listen -> think -> speak),
/// not simultaneous.
abstract class MetaWearablesAudio {
  static MetaWearablesAudio instance = MethodChannelMetaWearablesAudio();

  /// Fired continuously while [audioState].mode == listening. Raw 16-bit PCM,
  /// 8kHz mono (HFP).
  Stream<GlassesAudioChunk> get micAudioStream;

  /// Fired whenever the audio route/mode changes.
  Stream<GlassesAudioState> get audioState;

  /// Requests RECORD_AUDIO + BLUETOOTH_CONNECT runtime permissions if not
  /// already granted.
  Future<bool> requestAudioPermissions();

  /// Switches into HFP mode and starts capturing mic PCM. Call this and await
  /// [audioState] reaching `isRouteSettled == true` BEFORE starting a DAT
  /// camera stream if both are used concurrently — see the ordering
  /// constraint documented in the README.
  ///
  /// Returns false if no BLUETOOTH_SCO-capable device is available (glasses
  /// not connected / HFP unsupported at this moment).
  Future<bool> startListening();

  /// Stops mic capture and tears down the HFP route.
  Future<void> stopListening();

  /// Switches into A2DP mode and plays back the given PCM16/WAV bytes through
  /// the glasses speaker. Completes when playback finishes.
  Future<void> speak(
    Uint8List pcmOrWavBytes, {
    required int sampleRateHz,
    bool isWav = true,
  });

  /// Cancels any in-progress [speak] playback.
  Future<void> stopSpeaking();

  /// Releases audio focus / returns the audio session to its idle state.
  Future<void> releaseAudioSession();
}

class MethodChannelMetaWearablesAudio implements MetaWearablesAudio {
  MethodChannelMetaWearablesAudio({
    MethodChannel? methodChannel,
    EventChannel? micAudioChannel,
    EventChannel? audioStateChannel,
  }) : _methodChannel = methodChannel ??
            const MethodChannel('flutter_meta_wearables_dat/audio'),
       _micAudioChannel = micAudioChannel ??
           const EventChannel('flutter_meta_wearables_dat/mic_audio'),
       _audioStateChannel = audioStateChannel ??
           const EventChannel('flutter_meta_wearables_dat/audio_state');

  final MethodChannel _methodChannel;
  final EventChannel _micAudioChannel;
  final EventChannel _audioStateChannel;

  Stream<GlassesAudioChunk>? _micAudioStream;
  Stream<GlassesAudioState>? _audioState;

  @override
  Stream<GlassesAudioChunk> get micAudioStream {
    return _micAudioStream ??=
        _micAudioChannel.receiveBroadcastStream().map((event) {
          final map = Map<Object?, Object?>.from(event as Map);
          return GlassesAudioChunk(
            map['pcm'] as Uint8List,
            map['sampleRateHz'] as int,
            map['timestampMs'] as int,
          );
        });
  }

  @override
  Stream<GlassesAudioState> get audioState {
    return _audioState ??=
        _audioStateChannel.receiveBroadcastStream().map((event) {
          final map = Map<Object?, Object?>.from(event as Map);
          return GlassesAudioState(
            _modeFromWire(map['mode'] as String),
            _routeFromWire(map['route'] as String),
            map['settled'] as bool,
          );
        });
  }

  @override
  Future<bool> requestAudioPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((status) => status.isGranted)) {
      return false;
    }
    final confirmed = await _methodChannel.invokeMethod<bool>(
      'requestAudioPermissions',
    );
    return confirmed ?? false;
  }

  @override
  Future<bool> startListening() async {
    final started = await _methodChannel.invokeMethod<bool>('startListening');
    return started ?? false;
  }

  @override
  Future<void> stopListening() {
    return _methodChannel.invokeMethod('stopListening');
  }

  @override
  Future<void> speak(
    Uint8List pcmOrWavBytes, {
    required int sampleRateHz,
    bool isWav = true,
  }) {
    return _methodChannel.invokeMethod('speak', {
      'bytes': pcmOrWavBytes,
      'sampleRateHz': sampleRateHz,
      'isWav': isWav,
    });
  }

  @override
  Future<void> stopSpeaking() {
    return _methodChannel.invokeMethod('stopSpeaking');
  }

  @override
  Future<void> releaseAudioSession() {
    return _methodChannel.invokeMethod('releaseAudioSession');
  }

  GlassesAudioMode _modeFromWire(String value) {
    switch (value) {
      case 'LISTENING':
        return GlassesAudioMode.listening;
      case 'SPEAKING':
        return GlassesAudioMode.speaking;
      case 'IDLE':
      default:
        return GlassesAudioMode.idle;
    }
  }

  GlassesAudioRoute _routeFromWire(String value) {
    switch (value) {
      case 'A2DP_SPEAKER':
        return GlassesAudioRoute.a2dpSpeaker;
      case 'HFP_MIC_SPEAKER':
        return GlassesAudioRoute.hfpMicSpeaker;
      case 'NONE':
      default:
        return GlassesAudioRoute.none;
    }
  }
}
