/// lib/core/services/ai_service.dart
///
/// Single entry point for on-device model calls anywhere in the app.
///
/// Uses a two-stage extract() pipeline so each LLM call fits comfortably
/// in a small context window (~512 tokens):
///   Stage 1 — intent classification (tiny prompt, ~150 tokens)
///   Stage 2 — parameter extraction   (feature-specific, ~200 tokens)
///
/// Usage:
///   await AiService.instance.init(modelPath);
///   final result = await AiService.instance.extract(
///     transcript: 'Remind me to call mom tomorrow at 5pm',
///   );
library;

import 'dart:async';
import 'dart:convert';

import 'package:fllama/fllama.dart';

import '../constants/manifests.dart';
import '../constants/prompts.dart';
import '../utils/parameter_normalizer.dart';

class ExtractionResult {
  final String intent;
  final Map<String, dynamic> parameters;
  final double confidence;
  final String raw;

  const ExtractionResult({
    required this.intent,
    required this.parameters,
    required this.confidence,
    required this.raw,
  });
}

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  String? _modelPath;
  bool get isReady => _modelPath != null;

  Future<void> init(String modelPath) async {
    _modelPath = modelPath;
  }

  void _ensureReady() {
    if (_modelPath == null) {
      throw StateError(
        'AiService.init(modelPath) must be called before using the model.',
      );
    }
  }

  /// Low-level chat call.
  Future<String> rawChat(
    String userMessage, {
    double temperature = 0.1,
    int maxTokens = 256,
    String? systemPrompt,
    int contextSize = 1024,
  }) async {
    _ensureReady();
    final completer = Completer<String>();
    final request = OpenAiRequest(
      maxTokens: maxTokens,
      messages: [
        Message(Role.system, systemPrompt ?? AiPrompts.systemPrompt),
        Message(Role.user, userMessage),
      ],
      numGpuLayers: 99,
      modelPath: _modelPath!,
      frequencyPenalty: 0.0,
      presencePenalty: 1.1,
      topP: 1.0,
      contextSize: contextSize,
      temperature: temperature,
    );

    fllamaChat(request, (response, chunk, done) {
      if (done && !completer.isCompleted) {
        completer.complete(response);
      }
    });

    return completer.future;
  }

  /// Two-stage intent + parameter extraction.
  ///
  /// Stage 1: classify the transcript into one of the known feature_ids
  ///          (~150-token system prompt, ~30-token generation).
  /// Stage 2: extract only the matched feature's parameters
  ///          (~200-token system prompt, ~150-token generation).
  ///
  /// Each call fits within a 512-token context window.
  Future<ExtractionResult> extract({
    required String transcript,
    String knownLocalDataHint = 'none',
  }) async {
    _ensureReady();

    // ---- Stage 1: intent classification ----
    final intentRaw = (await rawChat(
      transcript,
      maxTokens: 20,
      temperature: 0.0,
      systemPrompt: AiPrompts.intentClassificationPrompt,
      contextSize: 512,
    ))
        .trim();

    final matchedIntent = _matchIntent(intentRaw);

    final feature = AiManifests.features[matchedIntent];
    if (matchedIntent == 'unknown' || feature == null) {
      return ExtractionResult(
        intent: 'unknown',
        parameters: {},
        confidence: 0.0,
        raw: intentRaw,
      );
    }

    // Empty-schema features need no extraction call.
    if (feature.schema.isEmpty) {
      return ExtractionResult(
        intent: matchedIntent,
        parameters: {},
        confidence: 0.9,
        raw: intentRaw,
      );
    }

    // ---- Stage 2: parameter extraction ----
    final dt = DateTime.now();
    final currentDate = '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    final extractionUserMsg = 'Current date: $currentDate\n'
        'Known local data: $knownLocalDataHint\n'
        'User said: "$transcript"';

    final paramsRaw = (await rawChat(
      extractionUserMsg,
      maxTokens: 150,
      temperature: 0.1,
      systemPrompt: AiPrompts.parameterExtractionPrompt(
        matchedIntent,
        feature.schema,
      ),
      contextSize: 512,
    ))
        .trim();

    // Parse JSON from response.
    final start = paramsRaw.indexOf('{');
    final end = paramsRaw.lastIndexOf('}');
    if (start == -1 || end == -1) {
      return ExtractionResult(
        intent: matchedIntent,
        parameters: {for (final key in feature.schema.keys) key: null},
        confidence: 0.3,
        raw: paramsRaw,
      );
    }

    Map<String, dynamic> parsed;
    try {
      parsed =
          jsonDecode(paramsRaw.substring(start, end + 1))
              as Map<String, dynamic>;
    } catch (_) {
      return ExtractionResult(
        intent: matchedIntent,
        parameters: {for (final key in feature.schema.keys) key: null},
        confidence: 0.3,
        raw: paramsRaw,
      );
    }

    // Keep only declared schema keys, then normalize.
    Map<String, dynamic> parameters = {
      for (final key in feature.schema.keys) key: parsed[key],
    };
    parameters = ParameterNormalizer.normalize(
      parameters,
      featureId: matchedIntent,
      transcript: transcript,
    );

    // Derive confidence from parameter fill rate.
    final total = parameters.length;
    final filled = parameters.values.where((v) => v != null).length;
    final confidence = total == 0 ? 0.9 : (0.5 + 0.5 * filled / total);

    return ExtractionResult(
      intent: matchedIntent,
      parameters: parameters,
      confidence: confidence,
      raw: paramsRaw,
    );
  }

  /// Resolve the raw model output to a known feature_id or "unknown".
  String _matchIntent(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'["\s]+'), '').toLowerCase();

    // Exact match.
    if (AiManifests.features.containsKey(cleaned)) return cleaned;

    // Fuzzy: check if any feature id appears in the response.
    for (final id in AiManifests.features.keys) {
      if (raw.toLowerCase().contains(id)) return id;
    }

    return 'unknown';
  }

  /// Grounded Q&A against already-retrieved stored data.
  Future<String> groundedAnswer(String question, dynamic storedData) async {
    _ensureReady();
    final payload = jsonEncode({
      'question': question,
      'stored_data': storedData,
    });
    final result = await rawChat(
      payload,
      temperature: 0.0,
      maxTokens: 128,
      systemPrompt: AiPrompts.groundedAnswerPrompt,
    );
    return result.trim();
  }

  /// Summarize a meeting transcript.
  Future<String> summarizeMeetingTranscript(
    String? meetingName,
    List<String> transcriptLines,
  ) async {
    _ensureReady();
    final payload = jsonEncode({
      'meeting_name': meetingName,
      'transcript_lines': transcriptLines,
    });
    final result = await rawChat(
      payload,
      temperature: 0.1,
      maxTokens: 400,
      systemPrompt: AiPrompts.meetingSummaryPrompt,
      contextSize: 4096,
    );
    return result.trim();
  }
}
