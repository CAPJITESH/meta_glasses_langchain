/// lib/features/home/data/home_repository.dart
library;

import '../../../core/features/feature_executor.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/local_data_store.dart';
import '../../../core/services/memory_store.dart';
import '../../../core/services/server_llm_service.dart';
import '../../../core/utils/glasses_message_builder.dart';
import '../../../core/utils/time_resolver.dart';
import '../../download_llm_model/data/llm_download_repository.dart';
import '../models/extraction_result.dart';

class HomeRepository {
  HomeRepository({ServerLlmGate? serverLlmGate, this.llmPhrasedReplies = true})
      : _serverLlmGate = serverLlmGate ?? const ServerLlmGate();

  final AiService _ai = AiService.instance;
  final LocalDataStore _store = LocalDataStore.instance;
  final MemoryStore _memory = MemoryStore.instance;
  final LlmDownloadRepository _downloadRepository = LlmDownloadRepository();
  final ServerLlmGate _serverLlmGate;

  /// When true, template replies from GlassesMessageBuilder are reworded by
  /// the model into natural speech before being spoken (facts preserved,
  /// falls back to the template on any failure).
  final bool llmPhrasedReplies;

  Future<void> ensureModelLoaded() async {
    if (!_ai.isReady) {
      await _downloadRepository.init();
      final saved = await _downloadRepository.getSavedModel();
      if (saved == null || !saved.isDownloaded || saved.localPath == null) {
        throw StateError('No downloaded model found — go back to the download screen.');
      }
      await _ai.init(saved.localPath!);
    }
    // Pay the one-time weights/KV-cache load here (screens call this while
    // showing a loading state) instead of inside the first user request.
    await _ai.warmUp();
  }

  /// The UI no longer picks a feature_id — the model decides intent itself
  /// from the transcript alone (plus the known-local-data name hint).
  Future<HomeExtractionView> runExtraction({required String transcript}) async {
    await ensureModelLoaded();

    final hint = _buildKnownLocalDataHint();
    final result = await _ai.extract(transcript: transcript, knownLocalDataHint: hint);

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
    // registered executor keyed on intent (their replies already come from
    // groundedAnswer, i.e. the model); legacy intents fall through to the
    // side-effect + message-builder path, optionally reworded by the model.
    final String glassesMessage;
    if (executor != null) {
      glassesMessage = await executor.execute(result, transcript: transcript);
    } else {
      _store.applyStorageSideEffects(result.intent, result.parameters);
      final draft =
          GlassesMessageBuilder.build(result.intent, result.parameters, humanTime);
      glassesMessage = llmPhrasedReplies
          ? await _ai.polishGlassesReply(transcript, draft)
          : draft;
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
