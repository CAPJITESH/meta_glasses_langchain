/// lib/features/glasses_voice/data/voice_providers.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../../home/data/home_repository.dart';

abstract class SpeechToText {
  Future<String> transcribe(Uint8List pcm16, int sampleRateHz);
}

abstract class AiResponder {
  Future<String> respond(String userText);
}

abstract class TextToSpeech {
  /// Returns WAV bytes and the sample rate used.
  Future<(Uint8List bytes, int sampleRateHz)> synthesize(String text);
}

/// There's no zero-setup on-device way to transcribe an arbitrary captured
/// PCM buffer — Android's built-in SpeechRecognizer only listens through its
/// own audio session, it can't accept an external buffer. Wire up a real
/// backend (cloud API, Vosk, whisper.cpp, etc.) before using this in
/// [GlassesVoiceAssistant].
class UnimplementedSpeechToText implements SpeechToText {
  @override
  Future<String> transcribe(Uint8List pcm16, int sampleRateHz) {
    throw UnimplementedError(
      'Wire up a real SpeechToText implementation (cloud API, Vosk, '
      'whisper.cpp, etc.) before using GlassesVoiceAssistant.',
    );
  }
}

/// Reuses the app's existing intent-extraction pipeline (HomeRepository ->
/// AiService.extract -> GlassesMessageBuilder) as the assistant's text
/// responder, rather than a generic freeform chat reply — this is the same
/// "transcript in, spoken glasses reply out" path the rest of the app is
/// built around (reminders, alarms, timers, notes, meetings, etc.).
class HomeIntentResponder implements AiResponder {
  HomeIntentResponder() : _repository = HomeRepository();

  final HomeRepository _repository;

  @override
  Future<String> respond(String userText) async {
    final result = await _repository.runExtraction(transcript: userText);
    return result.glassesMessage;
  }
}

/// Real, on-device text-to-speech via flutter_tts's synthesizeToFile — no
/// API key or network access required.
class FlutterTtsSpeech implements TextToSpeech {
  FlutterTtsSpeech() : _tts = FlutterTts();

  final FlutterTts _tts;
  int _fileCounter = 0;

  @override
  Future<(Uint8List, int)> synthesize(String text) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/glasses_tts_${_fileCounter++}.wav';
    await _tts.synthesizeToFile(text, filePath, true);
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    await file.delete();
    return (bytes, 22050);
  }
}
