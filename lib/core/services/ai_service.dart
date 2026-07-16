/// lib/core/services/ai_service.dart
///
/// Single entry point for on-device model calls anywhere in the app.
///
/// Uses a two-stage extract() pipeline:
///   Stage 1 — intent classification (grammar-constrained; catalog + rules +
///             20 disambiguation examples, ~950 tokens)
///   Stage 2 — parameter extraction   (feature-specific, ~200-550 tokens)
///
/// Both stages plus the user turn and generation budget fit within
/// [interactiveContextSize] (2048 — matches the token budget measured for the
/// ported Stage-1 prompt; do not shrink this without re-measuring).
///
/// Usage:
///   await AiService.instance.init(modelPath);
///   final result = await AiService.instance.extract(
///     transcript: 'Remind me to call mom tomorrow at 5pm',
///   );
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fllama/fllama.dart';

import '../constants/manifests.dart';
import '../constants/prompts.dart';
import '../utils/intent_router.dart';
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

  /// Single context size for the interactive path. Measured against the
  /// ported Stage-1 prompt (catalog + disambiguation rules + 20 examples,
  /// ~950 tokens) plus the worst-case Stage-2 prompt (~550 tokens) plus the
  /// user turn and generation budget — 512 is no longer enough once those
  /// were ported from Python (which uses n_ctx=2048 for the same content).
  /// fllama caches a native `server_context` per (modelPath + params) and
  /// n_ctx is part of the match key, so keeping one size avoids context
  /// thrashing. Only [summarizeMeetingTranscript] opts into 4096.
  static const int interactiveContextSize = 2048;

  /// GPU offload requested on every call. NOTE (Android): fllama's CMake only
  /// compiles a GPU backend for Apple (Metal) and Windows (Vulkan); the
  /// Android build is CPU-only, so this value is silently ignored there and
  /// inference runs on CPU. Left at a high value so it is honored the moment a
  /// GPU-enabled Android build of fllama is available — see the Section 0 audit.
  static const int _numGpuLayers = 99;

  /// CPU inference threads. fllama's OpenAiRequest defaults numThreads to 2,
  /// which leaves most of a modern phone's performance cores idle — on
  /// Android (where inference is currently CPU-only, see [_numGpuLayers])
  /// that default is the single largest throughput limiter. llama.cpp scales
  /// well up to the physical performance-core count and then degrades once
  /// threads spill onto efficiency cores, so cap below the total core count
  /// rather than using all of them.
  ///
  /// NOTE: the Python replica additionally tunes n_batch, a separate
  /// n_threads_batch, flash_attn, and use_mmap/use_mlock. fllama's Dart
  /// binding (OpenAiRequest / FllamaInferenceRequest, checked against the
  /// vendored package) exposes none of those knobs today — only
  /// numGpuLayers, numThreads, and grammar are settable. Flagging rather
  /// than faking: those four Python config values have no Dart equivalent
  /// until fllama's binding grows them.
  static final int _numThreads = Platform.numberOfProcessors <= 4
      ? 2
      : (Platform.numberOfProcessors - 2).clamp(2, 8);

  String? _modelPath;
  bool get isReady => _modelPath != null;

  Future<void> init(String modelPath) async {
    _modelPath = modelPath;
  }

  /// Separate from [init]: the embedding model (e.g. bge-small-en-v1.5,
  /// ~35MB) is a distinct GGUF file from the chat model, loaded by
  /// [SemanticRouter] independently of the main chat init/warmup lifecycle.
  /// Optional — [embed] throws if this was never called.
  String? _embedModelPath;
  bool get hasEmbedder => _embedModelPath != null;

  Future<void> initEmbedder(String modelPath) async {
    _embedModelPath = modelPath;
  }

  Future<void>? _warmUpFuture;

  /// Runs one inference per call SHAPE so fllama loads the weights and
  /// allocates the KV cache NOW rather than on the first real user request
  /// (which otherwise pays the full ~30s model load) — and so the *shape* of
  /// context growth (short classify, JSON-constrained extract, short polish)
  /// is already warm, not just the raw weights. Idempotent — concurrent
  /// callers share one warm-up, and a failed warm-up resets so it can be
  /// retried.
  Future<void> warmUp() {
    _ensureReady();
    return _warmUpFuture ??= _runWarmUpShapes().catchError((Object e) {
      _warmUpFuture = null;
      throw e;
    });
  }

  Future<void> _runWarmUpShapes() async {
    // Shape 1 — Stage-1 style: slim system prompt + tiny generation.
    await rawChat(
      'Wake me up at 7am',
      maxTokens: 8,
      temperature: 0.0,
      systemPrompt: AiPrompts.intentClassificationPrompt,
      contextSize: interactiveContextSize,
      grammar: _getStage1Grammar(),
    );

    // Shape 2 — Stage-2 style: real feature-specific prompt + JSON generation.
    final feature = AiManifests.features['set_reminder_v1'];
    if (feature != null) {
      final dt = DateTime.now();
      final currentDate =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
      await rawChat(
        'Current date: $currentDate\nKnown local data: none\n'
        'User said: "Remind me to call mom"',
        maxTokens: 128,
        temperature: 0.1,
        systemPrompt: AiPrompts.parameterExtractionPrompt(
          'set_reminder_v1',
          feature.schema,
        ),
        contextSize: interactiveContextSize,
      );
    }

    // Shape 3 — polish style: small prompt + short natural-language reply.
    await rawChat(
      jsonEncode({
        'user_said': 'Remind me to call mom',
        'reply': 'Reminder set for 5pm',
      }),
      maxTokens: 60,
      temperature: 0.2,
      systemPrompt: AiPrompts.glassesReplyPolishPrompt,
      contextSize: interactiveContextSize,
    );
  }

  void _ensureReady() {
    if (_modelPath == null) {
      throw StateError(
        'AiService.init(modelPath) must be called before using the model.',
      );
    }
  }

  /// Low-level chat call.
  ///
  /// [onDelta], when supplied, is invoked with the freshly-generated text on
  /// each token callback (the incremental slice since the previous callback,
  /// not the cumulative buffer) so callers can stream output to the UI or a
  /// streaming TTS as it is produced. The returned future still completes with
  /// the full final response, so non-streaming callers are unaffected.
  Future<String> rawChat(
    String userMessage, {
    double temperature = 0.1,
    int maxTokens = 256,
    String? systemPrompt,
    int contextSize = interactiveContextSize,
    void Function(String delta)? onDelta,
    String? grammar,
  }) async {
    _ensureReady();
    final completer = Completer<String>();
    final request = OpenAiRequest(
      maxTokens: maxTokens,
      messages: [
        Message(Role.system, systemPrompt ?? AiPrompts.systemPrompt),
        Message(Role.user, userMessage),
      ],
      numGpuLayers: _numGpuLayers,
      modelPath: _modelPath!,
      frequencyPenalty: 0.0,
      presencePenalty: 1.1,
      topP: 1.0,
      contextSize: contextSize,
      temperature: temperature,
    );

    // Built by hand instead of going through fllamaChat() because that
    // wrapper drops the thread count on the floor: OpenAiRequest has no
    // numThreads field, and fllamaChat leaves FllamaInferenceRequest at its
    // default of 2 threads. This mirrors fllamaChat's construction exactly
    // (empty input/eosToken; the chat itself travels in
    // openAiRequestJsonString via llama.cpp's OpenAI server path) with
    // [_numThreads] applied. Keep numThreads identical across calls — like
    // n_ctx, changing per-call params can invalidate fllama's cached context.
    final inferenceRequest = FllamaInferenceRequest(
      contextSize: contextSize,
      input: '',
      maxTokens: maxTokens,
      modelPath: _modelPath!,
      numGpuLayers: _numGpuLayers,
      numThreads: _numThreads,
      penaltyFrequency: 0.0,
      penaltyRepeat: 1.1,
      temperature: temperature,
      topP: 1.0,
      grammar: grammar ?? '',
      eosToken: '',
      openAiRequestJsonString: request.toJsonString(),
    );

    // fllama's callback delivers `response` as the CUMULATIVE text so far on
    // every token (not just the newest slice), so diff against what we have
    // already emitted to hand the caller only the new text.
    var emitted = 0;
    fllamaInference(inferenceRequest, (response, _, done) {
      if (onDelta != null && response.length > emitted) {
        onDelta(response.substring(emitted));
        emitted = response.length;
      }
      if (done && !completer.isCompleted) {
        completer.complete(response);
      }
    });

    return completer.future;
  }

  /// GBNF grammar constraining Stage 1 to emit exactly one known feature_id
  /// or "unknown" — eliminates hallucinated intent names like
  /// "create_focus_timer_v1". Built lazily on first use and cached; a failed
  /// build is not retried (mirrors AiService._get_stage1_grammar in Python).
  String? _stage1Grammar;
  bool _stage1GrammarAttempted = false;

  String? _getStage1Grammar() {
    if (_stage1Grammar != null || _stage1GrammarAttempted) {
      return _stage1Grammar;
    }
    _stage1GrammarAttempted = true;
    try {
      final alts = AiManifests.features.keys.map((id) => '"$id"').join(' | ');
      _stage1Grammar = 'root ::= $alts | "unknown"\n';
    } catch (_) {
      _stage1Grammar = null;
    }
    return _stage1Grammar;
  }

  /// Two-stage intent + parameter extraction.
  ///
  /// Stage 1: classify the transcript into one of the known feature_ids,
  ///          grammar-constrained so only a known id or "unknown" can come
  ///          out.
  /// Stage 2: extract only the matched feature's parameters (JSON, with
  ///          repair + wrong-key rescue + normalization).
  Future<ExtractionResult> extract({
    required String transcript,
    String knownLocalDataHint = 'none',
  }) async {
    _ensureReady();

    // ---- Stage 1: intent classification ----
    final intentRaw = (await rawChat(
      transcript,
      maxTokens: 16,
      temperature: 0.0,
      systemPrompt: AiPrompts.intentClassificationPrompt,
      contextSize: interactiveContextSize,
      grammar: _getStage1Grammar(),
    )).trim();

    var matchedIntent = _matchIntent(intentRaw);

    // Keyword fallback: the grammar can still legitimately emit "unknown"
    // for transcripts it can't classify — catch the most common miss.
    if (matchedIntent == 'unknown' &&
        transcript.toLowerCase().contains('remind')) {
      matchedIntent = 'set_reminder_v1';
    }

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

    final (parameters, paramsRaw, parseOk) = await _extractParameters(
      transcript: transcript,
      featureId: matchedIntent,
      schema: feature.schema,
      knownLocalDataHint: knownLocalDataHint,
    );

    if (!parseOk) {
      return ExtractionResult(
        intent: matchedIntent,
        parameters: parameters,
        confidence: 0.3,
        raw: paramsRaw,
      );
    }

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

  /// Stage-2-only entry point for callers that already know the intent
  /// (e.g. a semantic-router match that resolved intent but not parameters)
  /// and want to skip Stage 1 entirely. Shares the same JSON
  /// repair/wrong-key-rescue/normalization pipeline as [extract].
  Future<ExtractionResult> extractParamsOnly({
    required String transcript,
    required String intent,
    String knownLocalDataHint = 'none',
  }) async {
    _ensureReady();
    final feature = AiManifests.features[intent];
    if (feature == null) {
      return ExtractionResult(
        intent: 'unknown',
        parameters: {},
        confidence: 0.0,
        raw: 'semantic+stage2:unknown-intent:$intent',
      );
    }
    if (feature.schema.isEmpty) {
      return ExtractionResult(
        intent: intent,
        parameters: {},
        confidence: 0.9,
        raw: 'semantic+stage2:$intent',
      );
    }

    final (parameters, paramsRaw, parseOk) = await _extractParameters(
      transcript: transcript,
      featureId: intent,
      schema: feature.schema,
      knownLocalDataHint: knownLocalDataHint,
    );

    if (!parseOk) {
      return ExtractionResult(
        intent: intent,
        parameters: parameters,
        confidence: 0.3,
        raw: paramsRaw,
      );
    }

    final total = parameters.length;
    final filled = parameters.values.where((v) => v != null).length;
    final confidence = total == 0 ? 0.9 : (0.5 + 0.5 * filled / total);

    return ExtractionResult(
      intent: intent,
      parameters: parameters,
      confidence: confidence,
      raw: paramsRaw,
    );
  }

  /// Shared Stage-2 implementation: builds the dated user message, calls the
  /// model, parses JSON (with bracket-extraction fallback), repairs a bare
  /// time-object into the expected `{"time": {...}}` shape, rescues a single
  /// stray scalar into a single empty schema slot, then normalizes. Returns
  /// `(parameters, rawModelOutput, parseSucceeded)` — on parse failure,
  /// `parameters` is the schema shape with every value null.
  Future<(Map<String, dynamic>, String, bool)> _extractParameters({
    required String transcript,
    required String featureId,
    required Map<String, dynamic> schema,
    required String knownLocalDataHint,
  }) async {
    final dt = DateTime.now();
    final currentDate =
        '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    final extractionUserMsg =
        'Current date: $currentDate\n'
        'Known local data: $knownLocalDataHint\n'
        'User said: "$transcript"';

    final paramsRaw = (await rawChat(
      extractionUserMsg,
      maxTokens: 128,
      temperature: 0.1,
      systemPrompt: AiPrompts.parameterExtractionPrompt(featureId, schema),
      contextSize: interactiveContextSize,
    )).trim();

    // Parse JSON from response (bracket-extraction fallback).
    final start = paramsRaw.indexOf('{');
    final end = paramsRaw.lastIndexOf('}');
    final emptyParams = {for (final key in schema.keys) key: null};
    if (start == -1 || end == -1) {
      return (emptyParams, paramsRaw, false);
    }

    Map<String, dynamic> parsed;
    try {
      parsed =
          jsonDecode(paramsRaw.substring(start, end + 1))
              as Map<String, dynamic>;
    } catch (_) {
      return (emptyParams, paramsRaw, false);
    }

    // JSON repair: the model sometimes emits a bare time object at the top
    // level instead of nesting it under "time".
    if (schema.containsKey('time') &&
        !parsed.containsKey('time') &&
        parsed.containsKey('type') &&
        parsed.containsKey('clock_time')) {
      parsed = {'time': parsed};
    }

    // Project onto declared schema keys only.
    Map<String, dynamic> parameters = {
      for (final key in schema.keys) key: parsed[key],
    };

    // Wrong-key rescue: model occasionally emits a schema value under a
    // stray key, e.g. {"query_item_location_v1": "wallet"} instead of
    // {"item": "wallet"}. Promote it only when the mapping is unambiguous —
    // exactly one unmapped scalar and exactly one empty schema slot.
    final unmapped = <String, dynamic>{
      for (final entry in parsed.entries)
        if (!schema.containsKey(entry.key) &&
            (entry.value is String ||
                entry.value is num ||
                entry.value is bool) &&
            entry.value != null &&
            entry.value != '')
          entry.key: entry.value,
    };
    final emptySlots = [
      for (final entry in parameters.entries)
        if (entry.value == null) entry.key,
    ];
    if (unmapped.length == 1 && emptySlots.length == 1) {
      parameters[emptySlots.first] = unmapped.values.first;
    }

    parameters = ParameterNormalizer.normalize(
      parameters,
      featureId: featureId,
      transcript: transcript,
    );

    return (parameters, paramsRaw, true);
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

  /// Stage 0c support: embeds [text] into a vector for [SemanticRouter] to
  /// match against curated exemplars. Backed by a native `fllama_embed`
  /// export (added in a local fllama patch — see the fllama_embed native
  /// patch tracker — not yet in the pinned upstream `Telosnex/fllama`).
  ///
  /// Throws if [initEmbedder] was never called, or if the native call fails
  /// for any reason. Deliberately does NOT return a fake/zero vector on
  /// failure: callers (see [SemanticRouter.match]) must treat any exception
  /// here as "no embedding backend available" and fall through to the LLM
  /// path, not silently match against garbage vectors.
  Future<List<double>> embed(String text) {
    final modelPath = _embedModelPath;
    if (modelPath == null) {
      throw StateError(
        'AiService.initEmbedder(modelPath) must be called before embed().',
      );
    }
    return fllamaEmbed(
      modelPath,
      text,
      numGpuLayers: _numGpuLayers,
      numThreads: _numThreads,
    );
  }

  /// Stage 0b: deterministic regex router ([IntentRouter]). Synchronous, no
  /// LLM call. Exposed standalone (not inlined in [extract]) so a caller can
  /// try it before other preempts — e.g. HomeRepository runs this before the
  /// semantic router, so exact-pattern transcripts still get IntentRouter's
  /// precise, zero-cost parameter extraction (times, durations, item
  /// splits) instead of falling through to noisier LLM Stage 2.
  ExtractionResult? tryRouterMatch(String transcript) {
    final (routedIntent, routedParams) = IntentRouter.route(transcript);
    if (routedIntent == null) return null;

    final feature = AiManifests.features[routedIntent];
    if (feature == null || feature.schema.isEmpty) {
      return ExtractionResult(
        intent: routedIntent,
        parameters: {},
        confidence: 0.95,
        raw: 'router:$routedIntent',
      );
    }

    // Project router output onto the feature's declared schema and
    // normalize (same normalizer path as the LLM branch — keeps downstream
    // behavior identical).
    var params = {
      for (final key in feature.schema.keys)
        key: (routedParams ?? const {})[key],
    };
    params = ParameterNormalizer.normalize(
      params,
      featureId: routedIntent,
      transcript: transcript,
    );
    final total = params.length;
    final filled = params.values.where((v) => v != null).length;
    final confidence = total == 0 ? 0.95 : (0.6 + 0.4 * filled / total);
    return ExtractionResult(
      intent: routedIntent,
      parameters: params,
      confidence: confidence,
      raw: 'router:$routedIntent',
    );
  }

  /// Grounded Q&A against already-retrieved stored data.
  ///
  /// [onDelta] streams the answer incrementally as it is generated (see
  /// [rawChat]); the returned future still resolves with the full answer.
  /// Uses [interactiveContextSize] so it shares fllama's cached context with
  /// [extract] instead of forcing a reload.
  Future<String> groundedAnswer(
    String question,
    dynamic storedData, {
    void Function(String delta)? onDelta,
  }) async {
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
      contextSize: interactiveContextSize,
      onDelta: onDelta,
    );
    return result.trim();
  }

  /// Rephrases a deterministic template reply into one natural spoken
  /// sentence for the glasses. The template stays the source of truth for
  /// facts; the model only rewords it. Falls back to [draft] verbatim on any
  /// error, empty output, or a suspiciously long rewrite, so this can never
  /// make a turn fail — only sound better.
  Future<String> polishGlassesReply(String transcript, String draft) async {
    _ensureReady();
    try {
      final result = await rawChat(
        jsonEncode({'user_said': transcript, 'reply': draft}),
        temperature: 0.2,
        maxTokens: 60,
        systemPrompt: AiPrompts.glassesReplyPolishPrompt,
        contextSize: interactiveContextSize,
      );
      var cleaned = result.trim();
      if (cleaned.startsWith('"') &&
          cleaned.endsWith('"') &&
          cleaned.length > 1) {
        cleaned = cleaned.substring(1, cleaned.length - 1).trim();
      }
      if (cleaned.isEmpty || cleaned.length > draft.length * 3 + 40) {
        return draft;
      }
      return cleaned;
    } catch (_) {
      return draft;
    }
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
