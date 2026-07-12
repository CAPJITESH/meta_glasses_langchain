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
