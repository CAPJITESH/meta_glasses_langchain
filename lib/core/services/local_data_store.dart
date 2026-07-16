/// lib/core/services/local_data_store.dart
///
/// In-memory stand-in for the on-device DB, ported from main.py's
/// LOCAL_STORE / MEETING_STATE globals + their helper functions.
library;

class LocalDataStore {
  LocalDataStore._internal();
  static final LocalDataStore instance = LocalDataStore._internal();

  final Map<String, List<String>> _lists = {};
  final Map<String, List<String>> _preferences = {};
  final Map<String, String> _meetingSummaries = {};

  bool meetingActive = false;
  String? meetingName;
  List<String> meetingBuffer = [];

  String _key(String? name) => (name ?? '').trim().toLowerCase();

  /// Mirrors the "Known local data" hint shown in prompts.py's examples —
  /// a short, names-only index the model uses to ground phrases like "my
  /// swimming stuff" against what's actually saved. NEVER expose values,
  /// only names/keys, and never let the model treat this as an answer.
  String buildKnownLocalDataHint() {
    final listNames = _lists.keys.toList()..sort();
    final prefNames = _preferences.keys.toList()..sort();

    if (listNames.isEmpty && prefNames.isEmpty) return 'none';

    final parts = <String>[];
    if (listNames.isNotEmpty) parts.add('lists: ${listNames.join(', ')}');
    if (prefNames.isNotEmpty) parts.add('preferences: ${prefNames.join(', ')}');
    return parts.join(' | ');
  }

  void storeList(String listName, List<String> items) {
    _lists[_key(listName)] = items;
  }

  void storePreference(String category, List<String> items) {
    _preferences[_key(category)] = items;
  }

  /// Exact, deterministic key lookup — mirrors lookup_stored(). Returns null
  /// if nothing is stored under that key.
  List<String>? lookupStored({required String queryType, required String reference}) {
    final bucket = queryType == 'list' ? _lists : _preferences;
    return bucket[_key(reference)];
  }

  /// Exact match, or one token is a >=4-char prefix of the other ("swim" ~
  /// "swimming", "run" !~ "rung") — mirrors LocalDataStore._tokens_match.
  static bool _tokensMatch(String a, String b) {
    if (a == b) return true;
    final String shorter, longer;
    if (a.length <= b.length) {
      shorter = a;
      longer = b;
    } else {
      shorter = b;
      longer = a;
    }
    return shorter.length >= 4 && longer.startsWith(shorter);
  }

  /// Forgiving lookup across BOTH buckets: exact key first, then the best
  /// token-overlap match (with prefix tolerance), so "swim" still resolves
  /// the stored "swimming checklist". Returns null when nothing overlaps.
  ({String queryType, String name, List<String> items})? lookupFuzzy(
    String reference,
  ) {
    final key = _key(reference);
    if (_lists.containsKey(key)) {
      return (queryType: 'list', name: key, items: _lists[key]!);
    }
    if (_preferences.containsKey(key)) {
      return (queryType: 'preference', name: key, items: _preferences[key]!);
    }

    final queryTokens = key.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (queryTokens.isEmpty) return null;

    ({String queryType, String name, List<String> items})? best;
    var bestOverlap = 0;
    for (final (type, map) in [('list', _lists), ('preference', _preferences)]) {
      for (final entry in map.entries) {
        final nameTokens = entry.key.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        final overlap = queryTokens
            .where((qt) => nameTokens.any((nt) => _tokensMatch(qt, nt)))
            .length;
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          best = (queryType: type, name: entry.key, items: entry.value);
        }
      }
    }
    return best;
  }

  void startMeeting(String? name) {
    meetingActive = true;
    meetingName = name;
    meetingBuffer = [];
  }

  void endMeeting() {
    meetingActive = false;
    // Buffer intentionally NOT cleared here — summarize may still need it.
  }

  /// Called continuously by the app's ASR pipeline while a meeting is
  /// active. No-op if no meeting is active.
  void logMeetingText(String text) {
    if (meetingActive && text.isNotEmpty) {
      meetingBuffer.add(text);
    }
  }

  void storeMeetingSummary(String? name, String summary) {
    final key = name != null && name.isNotEmpty
        ? _key(name)
        : 'meeting_${DateTime.now().toIso8601String()}';
    _meetingSummaries[key] = summary;
  }

  String? getMeetingSummary(String name) => _meetingSummaries[_key(name)];

  void clearMeetingBuffer() {
    meetingBuffer = [];
  }

  /// Applies the create_list_v1 / save_preference_v1 / start_meeting_v1 /
  /// end_meeting_v1 side effects, mirroring apply_storage_side_effects().
  /// summarize_meeting_v1 is intentionally NOT handled here (needs a second
  /// model call) — call AiService.summarizeMeeting() explicitly instead.
  void applyStorageSideEffects(String intent, Map<String, dynamic> parameters) {
    switch (intent) {
      case 'create_list_v1':
        storeList(
          (parameters['list_name'] as String?) ?? '',
          ((parameters['items'] as List?) ?? []).cast<String>(),
        );
        break;
      case 'save_preference_v1':
        storePreference(
          (parameters['category'] as String?) ?? '',
          ((parameters['items'] as List?) ?? []).cast<String>(),
        );
        break;
      case 'start_meeting_v1':
        startMeeting(parameters['meeting_name'] as String?);
        break;
      case 'end_meeting_v1':
        endMeeting();
        break;
    }
  }
}
