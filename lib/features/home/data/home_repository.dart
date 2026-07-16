/// lib/features/home/data/home_repository.dart
library;

import '../../../core/features/feature_executor.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/local_data_store.dart';
import '../../../core/services/memory_store.dart';
import '../../../core/services/server_llm_service.dart';
import '../../../core/utils/glasses_message_builder.dart';
import '../../../core/utils/semantic_router.dart';
import '../../../core/utils/time_resolver.dart';
import '../../download_llm_model/data/llm_download_repository.dart';
import '../models/extraction_result.dart';

/// "I am going for swimming" / "heading to the gym" — the tail is a
/// candidate for a known-data recall (see [HomeRepository._preemptKnownDataRecall]).
final RegExp _goingRe = RegExp(
  r"^i(?:'m|\s+am)?\s+(?:going|heading|leaving|off)\s+(?:out\s+)?(?:for|to|into)?\s*(?:the\s+|a\s+)?(.+?)\s*$",
  caseSensitive: false,
);

/// Imperative starts that must never be hijacked by the known-data preempt.
final RegExp _commandHeadRe = RegExp(
  r'^(?:stop|start|set|remind|make|create|wake|note|find|search|show|save|remember)\b',
  caseSensitive: false,
);

class HomeRepository {
  HomeRepository({ServerLlmGate? serverLlmGate, this.llmPhrasedReplies = true})
      : _serverLlmGate = serverLlmGate ?? const ServerLlmGate();

  final AiService _ai = AiService.instance;
  final LocalDataStore _store = LocalDataStore.instance;
  final MemoryStore _memory = MemoryStore.instance;
  final LlmDownloadRepository _downloadRepository = LlmDownloadRepository();
  final ServerLlmGate _serverLlmGate;
  final SemanticRouter _semanticRouter = SemanticRouter.instance;
  bool _semanticRouterReady = false;

  /// When true, template replies from GlassesMessageBuilder are reworded by
  /// the model into natural speech before being spoken (facts preserved,
  /// falls back to the template on any failure).
  final bool llmPhrasedReplies;

  Future<void> ensureModelLoaded() async {
    if (!_ai.isReady) {
      await _downloadRepository.init();
      final savedLlm = await _downloadRepository.getSavedLlmModel();
      final savedEmbedding = await _downloadRepository.getSavedEmbeddingModel();
      if (savedLlm == null || !savedLlm.isDownloaded || savedLlm.localPath == null) {
        throw StateError('No downloaded LLM model found — go back to the download screen.');
      }
      if (savedEmbedding == null || !savedEmbedding.isDownloaded || savedEmbedding.localPath == null) {
        throw StateError('No downloaded embedding model found — go back to the download screen.');
      }
      await _ai.init(savedLlm.localPath!);
    }
    // Pay the one-time weights/KV-cache load here (screens call this while
    // showing a loading state) instead of inside the first user request.
    await _ai.warmUp();
    if (!_semanticRouterReady) {
      // Never throws — an unusable/missing embedding backend just leaves
      // the router permanently inert (see SemanticRouter.warmUp).
      await _semanticRouter.warmUp();
      _semanticRouterReady = true;
    }
  }

  /// The UI no longer picks a feature_id — the model decides intent itself
  /// from the transcript alone (plus the known-local-data name hint).
  ///
  /// Four-stage extraction pipeline, each stage tried in order and only
  /// falling through to the next when it returns nothing:
  ///   0a. Known-data preempt — deterministic "going for/to X" / short
  ///       fragment recall against stored data. Zero LLM calls.
  ///   0b. Deterministic regex router (IntentRouter). Zero LLM calls.
  ///   0c. Semantic router (embedding match against curated exemplars). Only
  ///       ever fires once AiService.embed() has a real on-device backend
  ///       behind it (see the fllama_embed native-patch tracker) — until
  ///       then SemanticRouter.match() always returns null and this stage is
  ///       a no-op, never a failure.
  ///   1+2. Full two-stage LLM (AiService.extract) — intent classification
  ///        then parameter extraction.
  Future<HomeExtractionView> runExtraction({required String transcript}) async {
    await ensureModelLoaded();

    final hint = _buildKnownLocalDataHint();

    ExtractionResult? result = _preemptKnownDataRecall(transcript);
    result ??= _ai.tryRouterMatch(transcript);
    if (result == null) {
      final semanticResult = await _semanticRouter.match(transcript);
      if (semanticResult != null) {
        result = semanticResult.parameters.isEmpty
            ? await _ai.extractParamsOnly(
                transcript: transcript,
                intent: semanticResult.intent,
                knownLocalDataHint: hint,
              )
            : semanticResult;
      }
    }
    result ??= await _ai.extract(transcript: transcript, knownLocalDataHint: hint);

    // --- Section 5/6: executor seam (checked BEFORE the server gate) ---------
    // Executors handle their own parameter misses gracefully (fuzzy lookup,
    // transcript fallback, specific "nothing saved" replies), so a matched
    // executor intent should never be diverted to the server stub just
    // because a schema field came back null.
    final executor = FeatureExecutors.forIntent(result.intent);

    // --- Section 4: confidence gate -> server fallback -----------------------
    // Below the threshold, route to the server LLM (a stub for now) instead of
    // trusting the local answer. When a real backend lands, only
    // ServerLlmService's internals change — this call site does not.
    if (executor == null && _serverLlmGate.shouldFallback(result.confidence)) {
      final fallback = await _serverLlmGate.service.respond(
        ServerLlmRequest(
          transcript: transcript,
          localIntent: result.intent,
          localConfidence: result.confidence,
        ),
      );
      return HomeExtractionView(
        transcript: transcript,
        intent: result.intent,
        parameters: result.parameters,
        confidence: result.confidence,
        raw: result.raw,
        humanTime: null,
        glassesMessage: fallback.text,
        usedServerFallback: true,
      );
    }

    String? humanTime;
    final timeObj = result.parameters['time'];
    if (timeObj is Map<String, dynamic>) {
      humanTime = TimeResolver.resolve(timeObj).human;
    }

    // New features (remember/recall, RAG, OCR, geolocation) are handled by a
    // registered executor keyed on intent; legacy intents fall through to
    // the side-effect + message-builder path.
    final String draft;
    if (executor != null) {
      draft = await executor.execute(result, transcript: transcript);
    } else {
      _store.applyStorageSideEffects(result.intent, result.parameters);
      draft = GlassesMessageBuilder.build(result.intent, result.parameters, humanTime);
    }

    // Polish rules, in order:
    //  1. An executor whose reply is already LLM-phrased (alreadyNatural,
    //     e.g. via groundedAnswer) never gets a second polish pass.
    //  2. Otherwise, polish ONLY when classification spent zero LLM calls
    //     (raw is "router:..." or "known-data:..."), so a turn that already
    //     paid for a full Stage 1+2 (or a semantic-router Stage-2-only) call
    //     isn't taxed with a third model call just for phrasing.
    final String glassesMessage;
    if (executor != null && executor.alreadyNatural) {
      glassesMessage = draft;
    } else if (llmPhrasedReplies && _isFastPath(result.raw)) {
      glassesMessage = await _ai.polishGlassesReply(transcript, draft);
    } else {
      glassesMessage = draft;
    }

    return HomeExtractionView(
      transcript: transcript,
      intent: result.intent,
      parameters: result.parameters,
      confidence: result.confidence,
      raw: result.raw,
      humanTime: humanTime,
      glassesMessage: glassesMessage,
    );
  }

  /// Stage 0a: deterministic recall short-circuit against stored data.
  ///
  /// Fires only when (a) the utterance is a "going for/to X" phrase or a
  /// short fragment (<= 3 words), and (b) X actually overlaps a stored
  /// list/preference name or memory topic. Everything else falls through to
  /// the normal router + LLM path. Bypasses ALL routers and the LLM.
  ExtractionResult? _preemptKnownDataRecall(String transcript) {
    final t = transcript.trim().replaceFirst(RegExp(r'[.?!]+$'), '').toLowerCase();
    if (t.isEmpty || _commandHeadRe.hasMatch(t)) return null;

    String candidate;
    final m = _goingRe.firstMatch(t);
    if (m != null) {
      candidate = m.group(1)!.trim();
    } else if (t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length <= 3) {
      candidate = t;
    } else {
      return null;
    }

    // Explicit meeting phrasing stays with the meeting lifecycle intents.
    if (candidate.isEmpty || candidate.contains('meeting')) return null;

    final stored = _store.lookupFuzzy(candidate);
    if (stored != null) {
      return ExtractionResult(
        intent: 'recall_stored_info_v1',
        parameters: {'query_type': 'list', 'reference': stored.name},
        confidence: 0.95,
        raw: 'known-data:${stored.name}',
      );
    }

    final entry = _memory.recall(candidate);
    if (entry != null) {
      return ExtractionResult(
        intent: 'recall_topic_v1',
        parameters: {'topic': entry.topic},
        confidence: 0.95,
        raw: 'known-data:${entry.topic}',
      );
    }
    return null;
  }

  /// True when classification spent zero LLM calls (Stage 0a preempt or
  /// Stage 0b regex router) — the only paths eligible for polish (see the
  /// polish-rules comment in [runExtraction]).
  bool _isFastPath(String raw) => raw.startsWith('router:') || raw.startsWith('known-data:');

  /// Names-only index the model uses to ground phrases like "my swimming
  /// checklist" — combines the legacy list/preference names with the new
  /// remember/recall topics. Values are never exposed, only names.
  String _buildKnownLocalDataHint() {
    final base = _store.buildKnownLocalDataHint();
    final topics = _memory.topicNames();
    if (topics.isEmpty) return base;
    final topicPart = 'topics: ${topics.join(', ')}';
    return base == 'none' ? topicPart : '$base | $topicPart';
  }

  Future<String> answerFromStoredData({
    required String question,
    required String queryType,
    required String reference,
  }) async {
    await ensureModelLoaded();
    final data = _store.lookupStored(queryType: queryType, reference: reference);
    return _ai.groundedAnswer(question, data);
  }

  Future<String> summarizeAndStoreMeeting({String? meetingName}) async {
    await ensureModelLoaded();
    final name = meetingName ?? _store.meetingName;
    final lines = List<String>.from(_store.meetingBuffer);
    final summary = await _ai.summarizeMeetingTranscript(name, lines);
    _store.storeMeetingSummary(name, summary);
    _store.clearMeetingBuffer();
    return summary;
  }
}
