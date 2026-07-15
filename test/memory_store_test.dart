import 'package:flutter_test/flutter_test.dart';
import 'package:qualcom_hacks/core/services/memory_store.dart';

void main() {
  group('MemoryStore — remember/recall showcase (Section 6)', () {
    late MemoryStore store;
    setUp(() => store = MemoryStore.instance..clear());

    test('exact topic round-trips with content intact', () {
      store.remember(
        topic: 'swimming checklist',
        content: 'goggles, cap, towel, sunscreen',
        tag: 'remember_topic_v1',
      );

      final entry = store.recall('swimming checklist');
      expect(entry, isNotNull);
      expect(entry!.content, 'goggles, cap, towel, sunscreen');
      expect(entry.tag, 'remember_topic_v1');
    });

    test('close phrasing resolves via fuzzy fallback', () {
      store.remember(
        topic: 'swimming checklist',
        content: 'goggles, cap, towel, sunscreen',
        tag: 'remember_topic_v1',
      );

      // "my swim list" shares no exact key but overlaps on "swim(ming)"/list.
      final entry = store.recall('my swimming list');
      expect(entry, isNotNull);
      expect(entry!.content, contains('goggles'));
    });

    test('normalized key + overwrite: re-remembering replaces, no dup', () {
      store.remember(topic: 'Swimming Checklist', content: 'old', tag: 't');
      store.remember(topic: 'swimming checklist', content: 'new', tag: 't');
      expect(store.topicNames().length, 1);
      expect(store.recall('swimming checklist')!.content, 'new');
    });

    test('unknown topic returns null (recall never fabricates)', () {
      expect(store.recall('nonexistent topic xyz'), isNull);
    });
  });

  group('MemoryStore — narrow retrieval (top-K + budget)', () {
    late MemoryStore store;
    setUp(() => store = MemoryStore.instance..clear());

    test('retrieveRelevant caps at topK, never top-all', () {
      for (var i = 0; i < 10; i++) {
        store.remember(topic: 'note $i about coffee', content: 'c$i', tag: 't');
      }
      final hits = store.retrieveRelevant('coffee', topK: 3);
      expect(hits.length, 3);
    });

    test('byte budget stops accumulation before topK when entries are long', () {
      final long = 'x' * 400;
      store.remember(topic: 'alpha coffee', content: long, tag: 't');
      store.remember(topic: 'beta coffee', content: long, tag: 't');
      store.remember(topic: 'gamma coffee', content: long, tag: 't');

      // 512-byte budget admits the first (allowed even alone), rejects the rest.
      final hits = store.retrieveRelevant('coffee', topK: 5, byteBudget: 512);
      expect(hits.length, 1);
    });

    test('tag scoping restricts the candidate set', () {
      store.remember(topic: 'a plan', content: '1', tag: 'lists');
      store.remember(topic: 'b plan', content: '2', tag: 'prefs');
      final hits = store.retrieveRelevant('plan', tag: 'lists');
      expect(hits.length, 1);
      expect(hits.single.tag, 'lists');
    });

    test('no token overlap yields no results (not everything)', () {
      store.remember(topic: 'swimming', content: 'goggles', tag: 't');
      expect(store.retrieveRelevant('quantum physics'), isEmpty);
    });
  });
}
