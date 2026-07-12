/// lib/features/home/data/home_repository.dart
library;

import '../../../core/services/ai_service.dart';
import '../../../core/services/local_data_store.dart';
import '../../../core/utils/glasses_message_builder.dart';
import '../../../core/utils/time_resolver.dart';
import '../../download_llm_model/data/llm_download_repository.dart';
import '../models/extraction_result.dart';

class HomeRepository {
  final AiService _ai = AiService.instance;
  final LocalDataStore _store = LocalDataStore.instance;
  final LlmDownloadRepository _downloadRepository = LlmDownloadRepository();

  Future<void> ensureModelLoaded() async {
    if (_ai.isReady) return;
    await _downloadRepository.init();
    final saved = await _downloadRepository.getSavedModel();
    if (saved == null || !saved.isDownloaded || saved.localPath == null) {
      throw StateError('No downloaded model found — go back to the download screen.');
    }
    await _ai.init(saved.localPath!);
  }

  /// The UI no longer picks a feature_id — the model decides intent itself
  /// from the transcript alone (plus the known-local-data name hint).
  Future<HomeExtractionView> runExtraction({required String transcript}) async {
    await ensureModelLoaded();

    final hint = _store.buildKnownLocalDataHint();
    final result = await _ai.extract(transcript: transcript, knownLocalDataHint: hint);

    _store.applyStorageSideEffects(result.intent, result.parameters);

    String? humanTime;
    final timeObj = result.parameters['time'];
    if (timeObj is Map<String, dynamic>) {
      humanTime = TimeResolver.resolve(timeObj).human;
    }

    final glassesMessage =
        GlassesMessageBuilder.build(result.intent, result.parameters, humanTime);

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
