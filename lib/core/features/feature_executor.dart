/// lib/core/features/feature_executor.dart
///
/// The extensibility seam (Section 5). A feature is added to the app as:
///   1. a new [AiManifests] entry + schema (extends intent classification and
///      parameter extraction automatically — no AiService.extract() change),
///   2. a small [FeatureExecutor] registered here keyed on its feature id,
///   3. (for RAG/OCR) one new data source behind that executor.
///
/// None of RAG / OCR / geolocation / remember / recall required any change to
/// `AiService.extract()`, `ParameterNormalizer`, or the model download/load
/// layer — that is the property this file demonstrates. Intents WITHOUT an
/// executor registered here fall through to the original
/// LocalDataStore + GlassesMessageBuilder path untouched.
library;

import '../services/ai_service.dart';
import '../services/memory_store.dart';

/// Produces the spoken glasses reply for one matched intent.
abstract class FeatureExecutor {
  String get featureId;

  /// [result] is the extraction for this turn; [transcript] is the raw user
  /// utterance. Returns the natural-language reply to speak back.
  Future<String> execute(ExtractionResult result, {required String transcript});
}

/// Intent -> executor lookup. Registration is the only wiring a new feature
/// needs on the consumption side.
class FeatureExecutors {
  FeatureExecutors._();

  static final Map<String, FeatureExecutor> _byId = {
    for (final e in <FeatureExecutor>[
      RememberTopicExecutor(),
      RecallTopicExecutor(),
      RagQueryExecutor(),
      OcrReadTextExecutor(),
      QueryLocationExecutor(),
    ])
      e.featureId: e,
  };

  static FeatureExecutor? forIntent(String intent) => _byId[intent];
}

// ---------------------------------------------------------------------------
// Section 6 — memory showcase executors (fully implemented).
// ---------------------------------------------------------------------------

class RememberTopicExecutor implements FeatureExecutor {
  RememberTopicExecutor({MemoryStore? store})
      : _store = store ?? MemoryStore.instance;

  final MemoryStore _store;

  @override
  String get featureId => 'remember_topic_v1';

  @override
  Future<String> execute(
    ExtractionResult result, {
    required String transcript,
  }) async {
    final topic = (result.parameters['topic'] as String?)?.trim();
    final content = (result.parameters['content'] as String?)?.trim();
    if (topic == null || topic.isEmpty || content == null || content.isEmpty) {
      return "I didn't catch what to remember — can you say that again?";
    }
    // Tagged at write time with the intent id (Section 6 scaling rule #1).
    _store.remember(topic: topic, content: content, tag: featureId);
    return "Okay, I'll remember your $topic.";
  }
}

class RecallTopicExecutor implements FeatureExecutor {
  RecallTopicExecutor({MemoryStore? store, AiService? ai})
      : _store = store ?? MemoryStore.instance,
        _ai = ai ?? AiService.instance;

  final MemoryStore _store;
  final AiService _ai;

  @override
  String get featureId => 'recall_topic_v1';

  @override
  Future<String> execute(
    ExtractionResult result, {
    required String transcript,
  }) async {
    final topic = (result.parameters['topic'] as String?)?.trim();
    if (topic == null || topic.isEmpty) {
      return 'What would you like me to recall?';
    }

    // Considered misses (Section 10): an empty store and a topic miss each get
    // a specific, helpful reply instead of handing null "stored data" to the
    // model and letting it improvise.
    if (_store.isEmpty) {
      return "I don't have any memories yet. Say something like "
          '"remember my parking spot is on level 3" and I\'ll keep it.';
    }

    // Narrow retrieval: exact topic, else fuzzy top-1. Only this single entry
    // is handed to the model — never the whole store. The model's job is to
    // phrase the retrieved content back, not to remember on its own.
    final entry = _store.recall(topic);
    if (entry == null) {
      return "I don't have anything saved about $topic yet.";
    }
    return _ai.groundedAnswer(transcript, entry.content);
  }
}

// ---------------------------------------------------------------------------
// Section 5 — RAG / OCR / geolocation stubs. Each proves the seam: a manifest
// entry + this executor is all that was needed. Replace the body with a real
// data source (vector store, ML Kit OCR, platform location) later.
// ---------------------------------------------------------------------------

class RagQueryExecutor implements FeatureExecutor {
  @override
  String get featureId => 'rag_query_v1';

  @override
  Future<String> execute(
    ExtractionResult result, {
    required String transcript,
  }) async {
    // Real version: embed `query`, retrieve top-K chunks from a local vector
    // store, feed them into AiService.groundedAnswer — same shape as recall,
    // just with semantic retrieval as the data source.
    return "I can't search your knowledge base yet — that's coming soon.";
  }
}

class OcrReadTextExecutor implements FeatureExecutor {
  @override
  String get featureId => 'ocr_read_text_v1';

  @override
  Future<String> execute(
    ExtractionResult result, {
    required String transcript,
  }) async {
    // Real version: run on-device OCR against the current camera frame, then
    // either return the text directly or re-feed it into extract() as if it
    // were a transcript.
    return "I can't read text from the camera yet — that's coming soon.";
  }
}

class QueryLocationExecutor implements FeatureExecutor {
  @override
  String get featureId => 'query_location_v1';

  @override
  Future<String> execute(
    ExtractionResult result, {
    required String transcript,
  }) async {
    // Real version: wrap platform location APIs, return structured params,
    // optionally combine with stored place data via groundedAnswer.
    return "I can't check your location yet — that's coming soon.";
  }
}
