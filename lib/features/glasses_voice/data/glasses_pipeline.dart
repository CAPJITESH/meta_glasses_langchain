/// lib/features/glasses_voice/data/glasses_pipeline.dart
///
/// Section 2 — the end-to-end voice pipeline as a state machine over swappable
/// stages:
///
///   glasses mic -> STT -> intent extraction/response -> TTS -> glasses speaker
///
/// The connection layer ([MetaWearablesAudio]), [SpeechToText] and
/// [TextToSpeech] are all injected interfaces, so any one can be swapped
/// (different glasses, a whisper.cpp STT, a neural TTS) without touching the
/// others or this orchestrator.
///
/// The pipeline exposes its [phase] as a stream so the UI (and a glasses LED,
/// if available) can reflect listening -> thinking -> speaking -> idle. That
/// visibility is itself a real latency mitigation: showing progress makes the
/// same wait feel shorter than silence (see Section 1).
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

import 'voice_providers.dart';
import 'whisper_speech_to_text.dart';

/// Coarse phase of one conversation turn.
enum PipelinePhase { idle, listening, thinking, speaking, error }

/// A snapshot the UI can render. Carries the best-known transcript/reply so the
/// screen can show "heard: …" and "said: …" alongside the phase.
class PipelineState {
  final PipelinePhase phase;
  final String? transcript;
  final String? reply;
  final Object? error;

  const PipelineState(
    this.phase, {
    this.transcript,
    this.reply,
    this.error,
  });

  PipelineState copyWith({
    PipelinePhase? phase,
    String? transcript,
    String? reply,
    Object? error,
  }) =>
      PipelineState(
        phase ?? this.phase,
        transcript: transcript ?? this.transcript,
        reply: reply ?? this.reply,
        error: error,
      );

  @override
  String toString() => 'PipelineState($phase, transcript: $transcript, '
      'reply: $reply, error: $error)';
}

class GlassesAssistantPipeline {
  GlassesAssistantPipeline({
    MetaWearablesAudio? audio,
    SpeechToText? stt,
    AiResponder? ai,
    TextToSpeech? tts,
  })  : audio = audio ?? MetaWearablesAudio.instance,
        stt = stt ?? WhisperSpeechToText(),
        ai = ai ?? HomeIntentResponder(),
        tts = tts ?? FlutterTtsSpeech();

  final MetaWearablesAudio audio;
  final SpeechToText stt;
  final AiResponder ai;
  final TextToSpeech tts;

  // ---- audio capture tuning (HFP mic is fixed at 8kHz mono) ----
  static const _sampleRate = 8000;
  static const _speechStartTimeout = Duration(seconds: 5);
  static const _silenceTimeout = Duration(milliseconds: 1200);
  static const _maxListenDuration = Duration(seconds: 15);
  static const double _speechThreshold = 350;

  final _stateController = StreamController<PipelineState>.broadcast();
  final BytesBuilder _pcmBuffer = BytesBuilder();

  PipelineState _state = const PipelineState(PipelinePhase.idle);

  /// Latest state (synchronous access for a just-built widget).
  PipelineState get state => _state;

  /// Phase/transition stream for the UI and glasses LED.
  Stream<PipelineState> get states => _stateController.stream;

  bool get isBusy => _state.phase != PipelinePhase.idle &&
      _state.phase != PipelinePhase.error;

  void _emit(PipelineState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// Runs one full turn, driving the state machine. Re-entrancy is guarded:
  /// calling while a turn is in flight is a no-op.
  Future<void> runTurn() async {
    if (isBusy) {
      dev.log('runTurn() skipped — pipeline is busy (${_state.phase})', name: 'Pipeline');
      return;
    }

    try {
      // ---- LISTENING ----
      _emit(const PipelineState(PipelinePhase.listening));
      dev.log('Phase: LISTENING', name: 'Pipeline');

      final permsOk = await audio.requestAudioPermissions();
      dev.log('Audio permissions: $permsOk', name: 'Pipeline');
      if (!permsOk) {
        throw StateError('Microphone/Bluetooth permission denied');
      }
      _pcmBuffer.clear();
      final micStarted = await audio.startListening();
      dev.log('startListening() returned: $micStarted', name: 'Pipeline');
      if (!micStarted) {
        throw StateError('Unable to start microphone. Is the glasses connected?');
      }

      try {
        await _captureUntilSilence();
      } finally {
        await audio.stopListening();
      }

      final pcm = _pcmBuffer.toBytes();
      dev.log('Captured ${pcm.length} bytes of PCM', name: 'Pipeline');
      if (pcm.isEmpty) throw StateError('No speech detected.');

      // ---- THINKING ----
      _emit(const PipelineState(PipelinePhase.thinking));
      dev.log('Phase: THINKING', name: 'Pipeline');

      final transcript = (await stt.transcribe(pcm, _sampleRate)).trim();
      dev.log('Transcript: "$transcript"', name: 'Pipeline');
      if (transcript.isEmpty) throw StateError('Speech could not be recognized.');
      _emit(_state.copyWith(transcript: transcript));

      final reply = await ai.respond(transcript);
      dev.log('AI reply (${reply.length} chars): "${reply.substring(0, min(80, reply.length))}"', name: 'Pipeline');
      _emit(_state.copyWith(reply: reply));

      // ---- SPEAKING ----
      _emit(_state.copyWith(phase: PipelinePhase.speaking));
      dev.log('Phase: SPEAKING', name: 'Pipeline');
      final (ttsAudio, sampleRateHz) = await tts.synthesize(reply);
      dev.log('TTS: ${ttsAudio.length} bytes @ ${sampleRateHz}Hz', name: 'Pipeline');
      if (ttsAudio.isEmpty) {
        throw StateError('Text-to-speech produced no audio.');
      }
      await audio.speak(ttsAudio, sampleRateHz: sampleRateHz, isWav: true);

      // ---- IDLE ----
      _emit(const PipelineState(PipelinePhase.idle));
      dev.log('Phase: IDLE (turn complete)', name: 'Pipeline');
    } catch (e) {
      dev.log('Pipeline ERROR: $e', name: 'Pipeline');
      _emit(PipelineState(PipelinePhase.error,
          transcript: _state.transcript, reply: _state.reply, error: e));
      rethrow;
    }
  }

  Future<void> _captureUntilSilence() async {
    final completer = Completer<void>();
    bool speechStarted = false;
    DateTime? lastSpeechTime;
    int chunkCount = 0;

    final subscription = audio.micAudioStream.listen((chunk) {
      chunkCount++;
      final rms = _calculateRms(chunk.pcm16);
      if (chunkCount <= 5 || chunkCount % 25 == 0) {
        dev.log('Mic chunk #$chunkCount: ${chunk.pcm16.length}B, rms=${rms.toStringAsFixed(1)}, '
            'speechStarted=$speechStarted', name: 'Pipeline');
      }
      if (rms > _speechThreshold) {
        if (!speechStarted) {
          dev.log('Speech DETECTED at chunk #$chunkCount (rms=$rms > $_speechThreshold)', name: 'Pipeline');
        }
        speechStarted = true;
        lastSpeechTime = DateTime.now();
        _pcmBuffer.add(chunk.pcm16);
      } else if (speechStarted) {
        _pcmBuffer.add(chunk.pcm16);
      }
    });

    final start = DateTime.now();
    final watchdog = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final now = DateTime.now();
      final elapsed = now.difference(start);

      // Hard cap: never listen longer than _maxListenDuration
      if (elapsed > _maxListenDuration) {
        dev.log('MAX LISTEN DURATION reached (${_maxListenDuration.inSeconds}s), '
            'chunks=$chunkCount, speechStarted=$speechStarted', name: 'Pipeline');
        if (!completer.isCompleted) completer.complete();
        timer.cancel();
        return;
      }

      if (!speechStarted) {
        if (elapsed > _speechStartTimeout) {
          dev.log('Speech start TIMEOUT (${_speechStartTimeout.inSeconds}s), '
              'chunks=$chunkCount — no speech detected', name: 'Pipeline');
          if (!completer.isCompleted) completer.complete();
          timer.cancel();
        }
        return;
      }
      if (lastSpeechTime != null &&
          now.difference(lastSpeechTime!) > _silenceTimeout) {
        dev.log('Silence detected (${_silenceTimeout.inMilliseconds}ms gap), '
            'chunks=$chunkCount, pcmBytes=${_pcmBuffer.length}', name: 'Pipeline');
        if (!completer.isCompleted) completer.complete();
        timer.cancel();
      }
    });

    try {
      await completer.future;
    } finally {
      dev.log('_captureUntilSilence done: chunks=$chunkCount, '
          'pcmBytes=${_pcmBuffer.length}, speechStarted=$speechStarted', name: 'Pipeline');
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
    await _stateController.close();
  }
}
