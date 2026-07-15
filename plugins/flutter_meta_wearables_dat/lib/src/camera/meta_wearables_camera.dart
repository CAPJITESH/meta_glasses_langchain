import 'dart:async';

import 'package:flutter/services.dart';

import 'glasses_camera_types.dart';

/// Real-time camera streaming and photo capture for Meta smart glasses via
/// the Device Access Toolkit (`mwdat-core`/`mwdat-camera`).
///
/// Unlike the audio bridge (`MetaWearablesAudio`), this talks to the DAT SDK
/// directly rather than standard Bluetooth profiles — see the plugin README
/// for how the two relate, and the ordering constraint to follow when using
/// both together.
abstract class MetaWearablesCamera {
  static MetaWearablesCamera instance = MethodChannelMetaWearablesCamera();

  /// Connection/stream lifecycle state.
  Stream<GlassesConnectionState> get connectionState;

  /// Fired continuously while a stream is active.
  Stream<GlassesVideoFrame> get videoFrameStream;

  /// Initializes the DAT SDK and connects to the best available paired
  /// device (auto-selected). Devices are paired out-of-band via the Meta AI
  /// companion app, not by this plugin.
  Future<bool> connect();

  /// Tears down the device session.
  Future<void> disconnect();

  /// Adds and starts a camera stream on the current session.
  ///
  /// If a mic-listening session is being started around the same time,
  /// callers should wait for [MetaWearablesAudio.audioState] to report
  /// `isRouteSettled == true` before calling this — see the README.
  Future<bool> startStream({
    GlassesVideoQuality quality = GlassesVideoQuality.medium,
    int frameRate = 24,
    bool compressVideo = false,
  });

  /// Stops and removes the current camera stream.
  Future<void> stopStream();

  /// Captures a single still photo from the active stream.
  Future<GlassesPhoto> capturePhoto();
}

class MethodChannelMetaWearablesCamera implements MetaWearablesCamera {
  MethodChannelMetaWearablesCamera({
    MethodChannel? methodChannel,
    EventChannel? frameChannel,
    EventChannel? stateChannel,
  }) : _methodChannel = methodChannel ??
            const MethodChannel('flutter_meta_wearables_dat/camera'),
       _frameChannel = frameChannel ??
           const EventChannel('flutter_meta_wearables_dat/camera_frames'),
       _stateChannel = stateChannel ??
           const EventChannel('flutter_meta_wearables_dat/camera_state');

  final MethodChannel _methodChannel;
  final EventChannel _frameChannel;
  final EventChannel _stateChannel;

  Stream<GlassesVideoFrame>? _videoFrameStream;
  Stream<GlassesConnectionState>? _connectionState;

  @override
  Stream<GlassesVideoFrame> get videoFrameStream {
    return _videoFrameStream ??=
        _frameChannel.receiveBroadcastStream().map((event) {
          final map = Map<Object?, Object?>.from(event as Map);
          return GlassesVideoFrame(
            bytes: map['bytes'] as Uint8List,
            width: map['width'] as int,
            height: map['height'] as int,
            timestampUs: map['timestampUs'] as int,
            isCompressed: map['isCompressed'] as bool,
          );
        });
  }

  @override
  Stream<GlassesConnectionState> get connectionState {
    return _connectionState ??=
        _stateChannel.receiveBroadcastStream().map((event) {
          return _connectionStateFromWire(event as String);
        });
  }

  @override
  Future<bool> connect() async {
    final connected = await _methodChannel.invokeMethod<bool>('connect');
    return connected ?? false;
  }

  @override
  Future<void> disconnect() {
    return _methodChannel.invokeMethod('disconnect');
  }

  @override
  Future<bool> startStream({
    GlassesVideoQuality quality = GlassesVideoQuality.medium,
    int frameRate = 24,
    bool compressVideo = false,
  }) async {
    final started = await _methodChannel.invokeMethod<bool>('startStream', {
      'videoQuality': quality.name.toUpperCase(),
      'frameRate': frameRate,
      'compressVideo': compressVideo,
    });
    return started ?? false;
  }

  @override
  Future<void> stopStream() {
    return _methodChannel.invokeMethod('stopStream');
  }

  @override
  Future<GlassesPhoto> capturePhoto() async {
    final result = await _methodChannel.invokeMethod('capturePhoto');
    final map = Map<Object?, Object?>.from(result as Map);
    return GlassesPhoto(
      bytes: map['bytes'] as Uint8List,
      isHeic: map['isHeic'] as bool,
    );
  }

  GlassesConnectionState _connectionStateFromWire(String value) {
    switch (value) {
      case 'CONNECTING':
        return GlassesConnectionState.connecting;
      case 'CONNECTED':
        return GlassesConnectionState.connected;
      case 'STREAMING':
        return GlassesConnectionState.streaming;
      case 'ERROR':
        return GlassesConnectionState.error;
      case 'IDLE':
      default:
        return GlassesConnectionState.idle;
    }
  }
}
