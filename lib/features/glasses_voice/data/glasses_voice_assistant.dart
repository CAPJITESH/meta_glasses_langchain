/// lib/features/glasses_voice/data/glasses_voice_assistant.dart
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

import 'voice_providers.dart';

class GlassesVoiceAssistant {
  GlassesVoiceAssistant({
    MetaWearablesAudio? audio,
    SpeechToText? stt,
    AiResponder? ai,
    TextToSpeech? tts,
  }) : audio = audio ?? MetaWearablesAudio.instance,
       stt = stt ?? UnimplementedSpeechToText(),
       ai = ai ?? HomeIntentResponder(),
       tts = tts ?? FlutterTtsSpeech();

  final MetaWearablesAudio audio;
  final SpeechToText stt;
  final AiResponder ai;
  final TextToSpeech tts;

  static const _sampleRate = 8000;

  /// Wait this long for the user to begin speaking.
  static const _speechStartTimeout = Duration(seconds: 5);

  /// End conversation after this much silence.
  static const _silenceTimeout = Duration(milliseconds: 1200);

  /// Minimum RMS considered speech.
  static const double _speechThreshold = 350;

  final BytesBuilder _pcmBuffer = BytesBuilder();

  Future<void> startConversationTurn() async {
    if (!await audio.requestAudioPermissions()) {
      throw StateError('Microphone/Bluetooth permission denied');
    }

    _pcmBuffer.clear();

    final started = await audio.startListening();

    if (!started) {
      throw StateError('Unable to start microphone. Is the glasses connected?');
    }

    try {
      await _captureUntilSilence();
    } finally {
      await audio.stopListening();
    }

    final pcm = _pcmBuffer.toBytes();

    if (pcm.isEmpty) {
      throw StateError('No speech detected.');
    }

    final text = await stt.transcribe(pcm, _sampleRate);

    if (text.trim().isEmpty) {
      throw StateError('Speech could not be recognized.');
    }

    final reply = await ai.respond(text);

    final (ttsAudio, sampleRate) = await tts.synthesize(reply);

    await audio.speak(ttsAudio, sampleRateHz: sampleRate, isWav: true);
  }

  Future<void> _captureUntilSilence() async {
    final completer = Completer<void>();

    bool speechStarted = false;
    DateTime? lastSpeechTime;

    Timer? watchdog;

    final subscription = audio.micAudioStream.listen((chunk) {
      final rms = _calculateRms(chunk.pcm16);

      print(
        'RMS: ${rms.toStringAsFixed(1)}   '
        'Speech: $speechStarted',
      );

      if (rms > _speechThreshold) {
        speechStarted = true;
        lastSpeechTime = DateTime.now();

        _pcmBuffer.add(chunk.pcm16);
      } else {
        if (speechStarted) {
          _pcmBuffer.add(chunk.pcm16);
        }
      }
    });

    final start = DateTime.now();

    watchdog = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final now = DateTime.now();

      if (!speechStarted) {
        if (now.difference(start) > _speechStartTimeout) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          timer.cancel();
        }
        return;
      }

      if (lastSpeechTime != null &&
          now.difference(lastSpeechTime!) > _silenceTimeout) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        timer.cancel();
      }
    });

    try {
      await completer.future;
    } finally {
      watchdog.cancel();
      await subscription.cancel();
    }
  }

  double _calculateRms(Uint8List pcm) {
    if (pcm.isEmpty) return 0;

    final samples = pcm.buffer.asInt16List();

    double sum = 0;

    for (final sample in samples) {
      final value = sample.toDouble();
      sum += value * value;
    }

    return sqrt(sum / max(samples.length, 1));
  }

  Future<void> dispose() async {
    await audio.releaseAudioSession();
  }
}
