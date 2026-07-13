import 'package:flutter_test/flutter_test.dart';
import 'package:qualcom_hacks/core/constants/manifests.dart';
import 'package:qualcom_hacks/core/features/feature_executor.dart';
import 'package:qualcom_hacks/core/services/ai_service.dart';
import 'package:qualcom_hacks/core/services/memory_store.dart';
import 'package:qualcom_hacks/core/services/server_llm_service.dart';

void main() {
  group('Server fallback gate (Section 4)', () {
    test('shouldFallback fires below threshold, not at/above', () {
      const gate = ServerLlmGate(threshold: 0.6);
      expect(gate.shouldFallback(0.3), isTrue);
      expect(gate.shouldFallback(0.6), isFalse);
      expect(gate.shouldFallback(0.9), isFalse);
    });

    test('stub returns fixed placeholder without network', () async {
      const service = StubServerLlmService();
      final res = await service.respond(
        const ServerLlmRequest(transcript: 'anything', localConfidence: 0.1),
      );
      expect(res.text, StubServerLlmService.placeholder);
      expect(res.isPlaceholder, isTrue);
    });
  });

  group('Executor seam (Section 5/6)', () {
    test('new intents are registered; legacy intents are not', () {
      // New features plug in via the registry...
      for (final id in [
        'remember_topic_v1',
        'recall_topic_v1',
        'rag_query_v1',
        'ocr_read_text_v1',
        'query_location_v1',
      ]) {
        expect(FeatureExecutors.forIntent(id), isNotNull, reason: id);
      }
      // ...while original intents keep the legacy message-builder path.
      expect(FeatureExecutors.forIntent('set_reminder_v1'), isNull);
      expect(FeatureExecutors.forIntent('summarize_meeting_v1'), isNull);
    });

    test('every registered executor id exists as a manifest entry', () {
      for (final id in [
        'remember_topic_v1',
        'recall_topic_v1',
        'rag_query_v1',
        'ocr_read_text_v1',
        'query_location_v1',
      ]) {
        expect(AiManifests.features.containsKey(id), isTrue, reason: id);
      }
    });

    test('RememberTopicExecutor writes to the store (no model needed)', () async {
      final store = MemoryStore.instance..clear();
      final exec = RememberTopicExecutor(store: store);
      final msg = await exec.execute(
        const ExtractionResult(
          intent: 'remember_topic_v1',
          parameters: {'topic': 'swimming checklist', 'content': 'goggles, cap'},
          confidence: 1.0,
          raw: '{}',
        ),
        transcript: 'remember my swimming checklist: goggles, cap',
      );
      expect(msg, contains('swimming checklist'));
      expect(store.recall('swimming checklist')!.content, 'goggles, cap');
    });

    test('RememberTopicExecutor asks again when fields are missing', () async {
      final store = MemoryStore.instance..clear();
      final exec = RememberTopicExecutor(store: store);
      final msg = await exec.execute(
        const ExtractionResult(
          intent: 'remember_topic_v1',
          parameters: {'topic': null, 'content': null},
          confidence: 0.5,
          raw: '{}',
        ),
        transcript: 'remember something',
      );
      expect(msg.toLowerCase(), contains("didn't catch"));
      expect(store.isEmpty, isTrue);
    });
  });
}
