/// lib/features/glasses_voice/data/whisper_speech_to_text.dart
///
/// Offline on-device speech-to-text (Section 2, stage 2) via whisper.cpp,
/// wrapped by the `whisper_ggml` package. Same integration shape as the fllama
/// binding: a native engine fronted by a small Dart API, no network at
/// inference time. The ggml model is fetched once on first use and cached, so
/// every subsequent transcription is fully offline.
///
/// The real work here is bridging the glasses mic to whisper. The HFP mic
/// delivers 8kHz mono PCM16 (a Bluetooth Classic limit), but whisper.cpp
/// operates at 16kHz mono. This class upsamples 8kHz -> 16kHz, wraps the
/// samples in a WAV container, and hands the file to the engine.
library;

import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'voice_providers.dart';

class WhisperSpeechToText implements SpeechToText {
  WhisperSpeechToText({
    WhisperController? controller,
    WhisperModel model = WhisperModel.baseEn,
    String language = 'en',
  })  : _controller = controller ?? WhisperController(),
        _model = model,
        _language = language;

  final WhisperController _controller;

  /// English-only `base` by default — the accuracy/speed sweet spot for a
  /// phone. Swap for [WhisperModel.smallEn] for more accuracy, or
  /// [WhisperModel.tinyEn] for lower latency, without touching callers.
  final WhisperModel _model;
  final String _language;

  /// whisper.cpp's fixed operating rate.
  static const int _whisperSampleRate = 16000;

  /// Guards against redundant/concurrent downloads of the same ggml model.
  Future<void>? _modelReady;

  /// The native whisper.cpp context is initialized straight from the model
  /// file path (see `WhisperController.transcribe`), with no existence
  /// check on the Dart side. Handing it a missing file crashes the whole
  /// process with a native SIGSEGV (null whisper_context deref) instead of
  /// throwing a catchable Dart exception, so the model must be fetched
  /// before every transcription attempt.
  Future<void> _ensureModelDownloaded() {
    return _modelReady ??= () async {
      dev.log('Ensuring model is downloaded: $_model', name: 'Whisper');
      final path = await _controller.downloadModel(_model);
      dev.log('Model ready at $path', name: 'Whisper');
    }().catchError((Object e, StackTrace st) {
      dev.log('Model download FAILED: $e', name: 'Whisper');
      _modelReady = null; // allow retry on the next call
      throw e;
    });
  }

  @override
  Future<String> transcribe(Uint8List pcm16, int sampleRateHz) async {
    dev.log('transcribe() called: ${pcm16.length} bytes @ ${sampleRateHz}Hz', name: 'Whisper');
    if (pcm16.isEmpty) {
      dev.log('Empty PCM buffer, returning empty transcript', name: 'Whisper');
      return '';
    }

    try {
      await _ensureModelDownloaded();

      dev.log('Resampling to ${_whisperSampleRate}Hz...', name: 'Whisper');
      final samples16k = sampleRateHz == _whisperSampleRate
          ? pcm16
          : _resamplePcm16(pcm16, sampleRateHz, _whisperSampleRate);
      dev.log('Resampled: ${samples16k.length} bytes', name: 'Whisper');

      dev.log('Wrapping as WAV...', name: 'Whisper');
      final wavBytes = _wrapPcm16AsWav(samples16k, _whisperSampleRate);
      dev.log('WAV wrapped: ${wavBytes.length} bytes', name: 'Whisper');

      // Validate WAV header
      if (wavBytes.length < 44) {
        dev.log('ERROR: WAV too small (${wavBytes.length}B)', name: 'Whisper');
        return '';
      }
      final riffMagic = String.fromCharCodes(wavBytes.sublist(0, 4));
      final waveMagic = String.fromCharCodes(wavBytes.sublist(8, 12));
      dev.log('WAV magic: RIFF=$riffMagic, WAVE=$waveMagic', name: 'Whisper');
      if (riffMagic != 'RIFF' || waveMagic != 'WAVE') {
        dev.log('ERROR: Invalid WAV header', name: 'Whisper');
        return '';
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/glasses_stt_${DateTime.now().microsecondsSinceEpoch}.wav';
      final file = File(path);
      await file.writeAsBytes(wavBytes, flush: true);
      final actualSize = await file.length();
      dev.log('WAV written to $path (${actualSize}B)', name: 'Whisper');

      if (actualSize != wavBytes.length) {
        dev.log('ERROR: File size mismatch: wrote ${wavBytes.length}B, read ${actualSize}B',
            name: 'Whisper');
      }

      dev.log('Starting Whisper transcription: model=$_model, lang=$_language', name: 'Whisper');
      final result = await _controller.transcribe(
        model: _model,
        audioPath: path,
        lang: _language,
      );
      final text = (result?.transcription.text ?? '').trim();
      dev.log('Transcription complete: "${text.substring(0, min(100, text.length))}"', name: 'Whisper');
      return text;
    } catch (e, st) {
      dev.log('TRANSCRIPTION ERROR: $e', name: 'Whisper');
      dev.log('Stack: $st', name: 'Whisper');
      rethrow;
    } finally {
      try {
        final dir = await getTemporaryDirectory();
        final files = dir.listSync();
        for (final f in files) {
          if (f is File && f.path.contains('glasses_stt_')) {
            await f.delete();
          }
        }
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  }

  /// Linear-interpolation resampler for mono PCM16 little-endian audio.
  /// Adequate for speech ASR; a polyphase filter would be marginally cleaner
  /// but is unnecessary for a 1.5B-class transcription target.
  static Uint8List _resamplePcm16(Uint8List pcm, int inRate, int outRate) {
    dev.log('Resampling: $inRate Hz -> $outRate Hz', name: 'Whisper');
    if (inRate == outRate) {
      dev.log('No resampling needed', name: 'Whisper');
      return pcm;
    }
    if (inRate <= 0 || outRate <= 0) {
      dev.log('ERROR: Invalid sample rates ($inRate, $outRate)', name: 'Whisper');
      return pcm;
    }

    final inData = ByteData.sublistView(pcm);
    final inSamples = pcm.length ~/ 2;
    dev.log('Input: $inSamples samples (${pcm.length} bytes)', name: 'Whisper');
    if (inSamples == 0) return pcm;

    final outSamples = (inSamples * outRate / inRate).floor();
    dev.log('Output: $outSamples samples', name: 'Whisper');
    if (outSamples <= 0) return Uint8List(0);

    try {
      final out = ByteData(outSamples * 2);
      final ratio = inRate / outRate;
      for (var j = 0; j < outSamples; j++) {
        final srcPos = j * ratio;
        final i0 = srcPos.floor();
        if (i0 < 0 || i0 >= inSamples) {
          dev.log('ERROR: Out of bounds at sample $j: i0=$i0 (inSamples=$inSamples)',
              name: 'Whisper');
          continue;
        }
        final i1 = (i0 + 1 < inSamples) ? i0 + 1 : i0;
        final frac = srcPos - i0;
        final s0 = inData.getInt16(i0 * 2, Endian.little);
        final s1 = inData.getInt16(i1 * 2, Endian.little);
        final v = (s0 + (s1 - s0) * frac).round().clamp(-32768, 32767);
        out.setInt16(j * 2, v, Endian.little);
      }
      final result = out.buffer.asUint8List();
      dev.log('Resampling complete: ${result.length} bytes', name: 'Whisper');
      return result;
    } catch (e) {
      dev.log('ERROR in resampling: $e', name: 'Whisper');
      return pcm;
    }
  }

  /// Prepend a 44-byte canonical PCM WAV header (mono, 16-bit).
  static Uint8List _wrapPcm16AsWav(Uint8List pcm, int sampleRate) {
    dev.log('Wrapping WAV: ${pcm.length} bytes @ ${sampleRate}Hz', name: 'Whisper');
    if (sampleRate <= 0) {
      dev.log('ERROR: Invalid sample rate $sampleRate', name: 'Whisper');
      throw ArgumentError('Sample rate must be > 0');
    }
    if (pcm.length > 500 * 1024 * 1024) {
      dev.log('ERROR: Audio too large (${pcm.length} bytes)', name: 'Whisper');
      throw ArgumentError('Audio exceeds 500MB');
    }

    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataLen = pcm.length;

    dev.log('WAV params: rate=$byteRate, align=$blockAlign, dataLen=$dataLen',
        name: 'Whisper');

    final header = ByteData(44);
    void writeAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLen, Endian.little); // chunk size
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // subchunk1 size (PCM)
    header.setUint16(20, 1, Endian.little); // audio format = PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLen, Endian.little);

    final out = Uint8List(44 + dataLen);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataLen, pcm);
    dev.log('WAV wrapped successfully: ${out.length} bytes total', name: 'Whisper');
    return out;
  }
}
