/// lib/core/services/memory_store.dart
///
/// On-device personalization store for the remember/recall showcase
/// (Section 6). Core principle: **store broadly, retrieve narrowly.** The
/// stored set may grow without bound, but what is ever injected into a model
/// prompt is capped — by a top-K count AND a hard byte budget — so
/// personalization never means serializing the user's whole history into the
/// context window.
///
/// In-memory, matching [LocalDataStore]'s "stand-in for the on-device DB"
/// convention; swap the backing map for a real DB later without changing the
/// retrieval contract below.
library;

/// One remembered fact, keyed by its normalized topic.
class MemoryEntry {
  final String topic;
  final String content;

  /// The intent that created this entry (e.g. `remember_topic_v1`). Tagged at
  /// WRITE time so retrieval can scope by category instead of scanning
  /// everything (Section 6 scaling rule #1).
  final String tag;

  final DateTime createdAt;

  const MemoryEntry({
    required this.topic,
    required this.content,
    required this.tag,
    required this.createdAt,
  });

  /// Rough byte cost of injecting this entry into a prompt. Used by the
  /// context budgeter; "topic: content" mirrors how it is actually rendered.
  int get approxContextBytes => '$topic: $content'.length;
}

class MemoryStore {
  MemoryStore._internal();
  static final MemoryStore instance = MemoryStore._internal();

  final Map<String, MemoryEntry> _entries = {};

  /// Default ceilings for [retrieveRelevant]. Deliberately small: the model
  /// only ever sees what the relevance step selected, never the full dataset.
  static const int defaultTopK = 3;
  static const int defaultByteBudget = 512;

  String _normalizeTopic(String topic) => topic.trim().toLowerCase();

  Set<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toSet();

  /// Names-only index for the "Known local data" hint, so the model can ground
  /// "my swim list" against what actually exists. Never exposes values.
  List<String> topicNames() {
    final names = _entries.values.map((e) => e.topic).toList()..sort();
    return names;
  }

  bool get isEmpty => _entries.isEmpty;

  /// Full snapshot for the Memories screen, newest first. UI-only — nothing on
  /// the model-prompt side may use this (retrieval stays narrow via
  /// [retrieveRelevant]/[recall]).
  List<MemoryEntry> allEntries() {
    final list = _entries.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Remove one remembered topic. Returns true if it existed.
  bool forget(String topic) => _entries.remove(_normalizeTopic(topic)) != null;

  /// Write side. Re-remembering an existing topic overwrites it (a checklist
  /// edited later replaces the old one) rather than accumulating duplicates.
  void remember({
    required String topic,
    required String content,
    required String tag,
    DateTime? now,
  }) {
    final key = _normalizeTopic(topic);
    if (key.isEmpty) return;
    _entries[key] = MemoryEntry(
      topic: topic.trim(),
      content: content.trim(),
      tag: tag,
      createdAt: now ?? DateTime.now(),
    );
  }

  /// Exact, deterministic topic lookup. Returns null on miss.
  MemoryEntry? recallExact(String topic) => _entries[_normalizeTopic(topic)];

  /// Narrow retrieval for a topic: exact match first, then a substring
  /// fallback (ported from memory_store.py's recall — catches "swim" ~
  /// "swimming" prefix/substring cases word-overlap alone would miss), then
  /// a word-overlap fallback for close phrasings ("my swim list" vs
  /// "swimming checklist"). Returns the single best entry, or null if
  /// nothing clears the fuzzy floor.
  MemoryEntry? recall(String topic) {
    final exact = recallExact(topic);
    if (exact != null) return exact;
    final substringMatch = _recallSubstring(topic);
    if (substringMatch != null) return substringMatch;
    final ranked = retrieveRelevant(topic, topK: 1);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// First-match-wins substring fuzzy: query is a substring of a stored
  /// topic key or vice versa. Iterates in insertion order to mirror
  /// Python's un-scored linear dict scan.
  MemoryEntry? _recallSubstring(String topic) {
    final key = _normalizeTopic(topic);
    if (key.isEmpty) return null;
    for (final entry in _entries.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) return entry.value;
    }
    return null;
  }

  /// Top-K relevance retrieval, NEVER top-all (Section 6 scaling rule #2).
  ///
  /// Entries are scored by word-overlap between [query] and each entry's
  /// topic+content, then selected in score order subject to two independent
  /// caps: at most [topK] entries AND a cumulative [byteBudget] on injected
  /// content (scaling rule #3 — a few long entries can blow the context window
  /// as fast as many short ones). The word-overlap scorer is intentionally the
  /// same primitive used by [recall]'s fuzzy fallback, so it can later be
  /// swapped for embedding similarity (once the RAG feature exists) without
  /// touching callers.
  ///
  /// [tag], when given, scopes the search to one category (uses the write-time
  /// tag so this stays cheap as the store grows).
  List<MemoryEntry> retrieveRelevant(
    String query, {
    int topK = defaultTopK,
    int byteBudget = defaultByteBudget,
    String? tag,
  }) {
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return const [];

    final candidates = _entries.values.where((e) => tag == null || e.tag == tag);

    final scored = <({MemoryEntry entry, double score})>[];
    for (final entry in candidates) {
      final entryTokens = _tokens('${entry.topic} ${entry.content}');
      if (entryTokens.isEmpty) continue;
      final overlap = queryTokens.intersection(entryTokens).length;
      if (overlap == 0) continue;
      // Jaccard-ish: overlap normalized by the query size, so a short query
      // fully covered by an entry scores high regardless of entry length.
      final score = overlap / queryTokens.length;
      scored.add((entry: entry, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final selected = <MemoryEntry>[];
    var usedBytes = 0;
    for (final s in scored) {
      if (selected.length >= topK) break;
      final cost = s.entry.approxContextBytes;
      // Always allow the first entry through even if it alone exceeds the
      // budget (better a truncated single answer than nothing); stop adding
      // once the budget is reached.
      if (selected.isNotEmpty && usedBytes + cost > byteBudget) break;
      selected.add(s.entry);
      usedBytes += cost;
    }
    return selected;
  }

  void clear() => _entries.clear();
}
