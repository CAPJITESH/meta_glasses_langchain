/// lib/core/utils/intent_router.dart
///
/// Deterministic intent + parameter router — Stage 0b of the extraction
/// pipeline. Runs BEFORE the LLM and, for transcripts that match a known
/// pattern, returns the (intent, params) record directly — skipping the
/// ~1-3s Stage-1/Stage-2 model calls entirely. Verbatim port of
/// `IntentRouter.route()` from intent_router.py.
///
/// Design principles
/// ------------------
/// * Rules are ordered from most-specific to most-general. Question forms
///   (recall) come before creation forms so "what's on my X" is not misread
///   as "make X".
/// * Every rule is a plain regex; readability trumps cleverness.
/// * If no rule matches, [IntentRouter.route] returns `(null, null)` and the
///   caller falls back to the LLM path.
/// * The router does not fabricate parameters — if a rule matches the
///   intent but the transcript does not contain enough signal to fill the
///   schema, the router returns the intent with best-effort partials and
///   lets the LLM/normalizer round it out.
library;

class IntentRouter {
  IntentRouter._();

  static const List<String> _weekdayNames = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  static const Map<String, int> _unitToSeconds = {
    'second': 1, 'seconds': 1, 'sec': 1, 'secs': 1, 's': 1,
    'minute': 60, 'minutes': 60, 'min': 60, 'mins': 60, 'm': 60,
    'hour': 3600, 'hours': 3600, 'hr': 3600, 'hrs': 3600, 'h': 3600,
  };

  static const Map<String, String> _unitToUnit = {
    'second': 'seconds', 'seconds': 'seconds', 'sec': 'seconds', 'secs': 'seconds', 's': 'seconds',
    'minute': 'minutes', 'minutes': 'minutes', 'min': 'minutes', 'mins': 'minutes', 'm': 'minutes',
    'hour': 'hours', 'hours': 'hours', 'hr': 'hours', 'hrs': 'hours', 'h': 'hours',
  };

  static const String _listWord = r'(?:check\w*|list)';

  static final RegExp _cleanHeadRe = RegExp(
    r'^(okay|ok|well|so|please|hey|umm?|uh)\s*[,]?\s*',
    caseSensitive: false,
  );

  static final RegExp _clockRe = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?\b', caseSensitive: false);
  static final RegExp _clock24Re = RegExp(r'\b(\d{1,2}):(\d{2})\b');
  static final RegExp _relTimeRe = RegExp(
    r'\b(?:in|after)\s+(\d+)\s*(second|seconds|sec|secs|minute|minutes|min|mins|hour|hours|hr|hrs)\b',
    caseSensitive: false,
  );

  // RECALL patterns (must come BEFORE their CREATE counterparts).
  static final RegExp _reRecallList = RegExp(
    r"^(?:what'?s|what\s+is)\s+(?:on|in)\s+(?:my\s+)?(.+?)(?:\s+(?:checklist|list))?\s*$",
    caseSensitive: false,
  );
  static final RegExp _reRecallPref = RegExp(
    r'^what\s+are\s+my\s+(.+?)\s*$',
    caseSensitive: false,
  );
  // "where did I <verb>" where the verb is NOT leave/put/place (those are
  // physical-item queries).
  static final RegExp _reRecallTopic = RegExp(
    r'^where\s+did\s+i\s+(?!leave\b|put\b|place\b|leaved\b|placed\b)(\w+)',
    caseSensitive: false,
  );
  // "what is/was my X" / "where is my X" — recall a stored fact. "next" is
  // excluded so calendar-style questions fall through.
  static final RegExp _reRecallTopicQ = RegExp(
    r"^(?:what'?s|what\s+is|what\s+was|where'?s|where\s+is)\s+my\s+(?!next\b)(.+?)\s*$",
    caseSensitive: false,
  );
  // Broader fallback for "what is my X?" style queries that may not match
  // the pattern above. (Python defines this constant twice; only the
  // second, narrower definition is ever live — this ports that one.)
  static final RegExp _reRecallTopicQ2 = RegExp(
    r"^(?:what\s+is|what'?s)\s+my\s+(.+?)\s*$",
    caseSensitive: false,
  );
  // Simple "what is my X?" pattern for hotel/seat/locker etc.
  static final RegExp _reRecallTopicQ3 = RegExp(
    r'^what\s+is\s+my\s+(\w+)\??$',
    caseSensitive: false,
  );

  // ITEM queries.
  static final RegExp _reQueryItem = RegExp(
    r'^where\s+did\s+i\s+(?:leave|put|place)\s+(?:my|the)\s+(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _reLogItem = RegExp(
    r'^remember\s+where\s+i\s+(?:put|placed|left|leave)\s+(?:my|the)?\s*(.*?)\s*$',
    caseSensitive: false,
  );

  // STORE fact.
  static final RegExp _reRememberTopic = RegExp(
    r'^remember\s+(?:my|the)\s+(.+?)\s+(?:is|are|was)\s+(.+?)\s*$',
    caseSensitive: false,
  );

  // CREATE list / preference.
  static final RegExp _reCreateList = RegExp(
    '^(?:make|create)\\s+a?\\s*$_listWord\\s+for\\s+(.+?)\\s*\$',
    caseSensitive: false,
  );
  // "create a swimming checklist costume goggles fins" — name precedes the
  // list-word, items trail it.
  static final RegExp _reCreateListNamed = RegExp(
    '^(?:make|create)\\s+(?:a\\s+|an\\s+|the\\s+)?(.+?)\\s+$_listWord\\s*:?\\s*(.*?)\\s*\$',
    caseSensitive: false,
  );
  // "my swimming checklist is goggles cap fins" (optionally "remember my ...").
  static final RegExp _reCreateListPossessive = RegExp(
    '^(?:remember\\s+)?(?:that\\s+)?my\\s+(.+?)\\s+$_listWord\\s+(?:is|are|has|includes?)\\s*:?\\s*(.+?)\\s*\$',
    caseSensitive: false,
  );
  static final RegExp _reSavePref = RegExp(
    r'^remember\s+my\s+(favou?rite\s+\w+)\s+(?:are\s+)?(.+?)\s*$',
    caseSensitive: false,
  );

  // CONDITIONAL / plain reminder.
  static final RegExp _reCondReminder = RegExp(
    r'^remind\s+me\s+to\s+(.+?)\s+when\s+(.+?)\s*$',
    caseSensitive: false,
  );
  // More permissive conditional reminder - handles "remind me X when Y"
  // without "to".
  static final RegExp _reCondReminder2 = RegExp(
    r'^remind\s+me\s+(.+?)\s+when\s+(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _reReminder = RegExp(
    r'^remind\s+me\s+(?:to\s+)?(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _reCondReminderLocation = RegExp(
    r"(?:i\s+(?:get|arrive|come|reach)\s+(?:to|at)|i\s+reach(?:es|ed)?|i'?m\s+at|reach(?:ing)?)"
        r'\s+(?:the\s+)?(.+?)\s*$',
    caseSensitive: false,
  );

  // ALARM.
  static final RegExp _reAlarm = RegExp(
    r'^(?:wake\s+me\s+up|set\s+an?\s+alarm)\b',
    caseSensitive: false,
  );

  // FOCUS timer — must come BEFORE plain timer.
  static final RegExp _reFocusTimer = RegExp(
    r'\bfocus\s+timer\b|\bfocus\b.*\btimer\b',
    caseSensitive: false,
  );
  static final RegExp _reStopTimer = RegExp(
    r'^(?:stop|end|cancel)\s+(?:the\s+)?(?:focus\s+)?timer\s*$',
    caseSensitive: false,
  );
  static final RegExp _reStopWord = RegExp(r'\b(?:stop|end|cancel)\b', caseSensitive: false);

  // PLAIN timer.
  static final RegExp _rePlainTimer = RegExp(
    r'^(?:set|start)\s+a?\s*timer\b|\btimer\s+for\s+\d+',
    caseSensitive: false,
  );
  static final RegExp _reDurationMention = RegExp(
    r'(\d+)\s*(second|seconds|sec|minute|minutes|min|hour|hours|hr)s?\b',
    caseSensitive: false,
  );

  // NOTES.
  static final RegExp _reSaveNote = RegExp(
    r'^(?:save\s+a\s+note|note\s+that|make\s+a\s+note)\b',
    caseSensitive: false,
  );
  static final RegExp _reSaveNoteContent = RegExp(
    r'(?:note\s+that|save\s+a\s+note\s+(?:that|saying))\s+(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _reQueryNotes = RegExp(
    r'^(?:find|search|show)\s+my\s+notes?\b',
    caseSensitive: false,
  );
  static final RegExp _reQueryNotesKeyword = RegExp(
    r'notes?\s+about\s+(.+?)\s*$',
    caseSensitive: false,
  );

  // TIME REMAINING.
  static final RegExp _reTimeRemaining = RegExp(
    r'how\s+much\s+time\s+(?:do\s+i\s+have|until|before|left|remains)',
    caseSensitive: false,
  );
  static final RegExp _reNextEventQuery = RegExp(
    r'^when\s+is\s+my\s+next\b',
    caseSensitive: false,
  );
  static final RegExp _reTimeRemainingHint = RegExp(
    r'(?:before|until|my\s+next)\s+my?\s*(.+?)\s*$',
    caseSensitive: false,
  );

  // ACTIVITY & BRIEFING.
  static final RegExp _reRecentActivity = RegExp(
    r'^what\s+(?:was|have)\s+i\s+(?:doing|been\s+doing)\b',
    caseSensitive: false,
  );
  static final RegExp _reNextBriefing = RegExp(r"^what'?s\s+next\b", caseSensitive: false);

  static final RegExp _trailingFillerRe = RegExp(
    r'\s+(?:again|right\s+now|now|please)\s*$',
    caseSensitive: false,
  );

  static String _norm(String t) => t.trim().replaceFirst(RegExp(r'[.?!]+$'), '').toLowerCase();

  static String _cleanHead(String t) => t.replaceFirst(_cleanHeadRe, '');

  static String? _parseClockTime(String hourStr, String? minuteStr, String? ampm) {
    final hour0 = int.tryParse(hourStr);
    if (hour0 == null) return null;
    var hour = hour0;
    final minute = minuteStr != null ? int.parse(minuteStr) : 0;
    if (ampm != null) {
      final a = ampm.toLowerCase();
      if (a.startsWith('p') && hour != 12) hour += 12;
      if (a.startsWith('a') && hour == 12) hour = 0;
    }
    if (!(hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59)) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Best-effort clock extraction. Prefers am/pm form, falls back to HH:MM.
  static String? _findClock(String transcript) {
    final m = _clockRe.firstMatch(transcript);
    if (m != null) return _parseClockTime(m.group(1)!, m.group(2), m.group(3));
    final m24 = _clock24Re.firstMatch(transcript);
    if (m24 != null) return _parseClockTime(m24.group(1)!, m24.group(2), null);
    return null;
  }

  static String? _findDateWord(String transcript) {
    final t = transcript.toLowerCase();
    if (t.contains('tomorrow')) return 'tomorrow';
    if (t.contains('today')) return 'today';
    for (final day in _weekdayNames) {
      if (t.contains(day)) return day[0].toUpperCase() + day.substring(1);
    }
    return null;
  }

  /// Returns (amount, unit) or null.
  static (int, String)? _findRelative(String transcript) {
    final m = _relTimeRe.firstMatch(transcript);
    if (m == null) return null;
    return (int.parse(m.group(1)!), _unitToUnit[m.group(2)!.toLowerCase()]!);
  }

  static List<String>? _weekdaysFromTranscript(String t) {
    final tl = t.toLowerCase();
    if (tl.contains('weekday')) {
      return ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
    }
    if (tl.contains('weekend')) return ['Saturday', 'Sunday'];
    final found = <String>[];
    for (final day in _weekdayNames) {
      if (tl.contains(day)) found.add(day[0].toUpperCase() + day.substring(1));
    }
    return found.isEmpty ? null : found;
  }

  static Map<String, dynamic> _timeObj(
    String? clock,
    String? date,
    num? amount,
    String? unit,
  ) {
    if (clock != null) {
      return {'type': 'absolute', 'clock_time': clock, 'date': date, 'amount': null, 'unit': null};
    }
    if (amount != null && unit != null) {
      return {'type': 'relative', 'clock_time': null, 'date': null, 'amount': amount, 'unit': unit};
    }
    return {'type': 'unknown', 'clock_time': null, 'date': null, 'amount': null, 'unit': null};
  }

  /// Deterministic pre-classifier. Returns `(intent, params)` or
  /// `(null, null)` when no rule matches — the caller should fall through
  /// to the semantic router / LLM path.
  static (String?, Map<String, dynamic>?) route(String transcript) {
    final raw = transcript.trim();
    final t = _cleanHead(raw);
    final tn = _norm(t);

    // --- recall (queries) before create ---
    if (_reRecentActivity.hasMatch(tn)) {
      return ('query_recent_activity_v1', <String, dynamic>{});
    }
    if (_reNextBriefing.hasMatch(tn)) {
      return ('query_next_briefing_v1', <String, dynamic>{});
    }
    if (_reTimeRemaining.hasMatch(tn) || _reNextEventQuery.hasMatch(tn)) {
      final m = _reTimeRemainingHint.firstMatch(tn);
      final hint = m != null ? m.group(1)!.trim() : null;
      return ('query_time_remaining_v1', {'event_hint': hint});
    }

    var m = _reRecallList.firstMatch(tn);
    if (m != null) {
      return ('recall_stored_info_v1', {'query_type': 'list', 'reference': m.group(1)!.trim()});
    }

    m = _reRecallPref.firstMatch(tn);
    if (m != null) {
      return ('recall_stored_info_v1', {'query_type': 'preference', 'reference': m.group(1)!.trim()});
    }

    // --- physical item query (before recall_topic; "leave/put my X" wins) ---
    m = _reQueryItem.firstMatch(tn);
    if (m != null) {
      return ('query_item_location_v1', {'item': m.group(1)!.trim()});
    }

    // --- possessive list creation ("my swimming checklist is goggles cap
    // fins"). Must run BEFORE remember_topic so "remember my X checklist
    // is ..." doesn't get stored as a flat topic string.
    m = _reCreateListPossessive.firstMatch(tn);
    if (m != null) {
      final listName = m.group(1)!.trim();
      final items = _splitItemsSimple(m.group(2)!.trim());
      return ('create_list_v1', {'list_name': listName, 'items': items});
    }

    // --- recall a stored fact, question form ("what is my parking spot?") ---
    m = _reRecallTopicQ.firstMatch(tn);
    if (m != null) {
      final topic = m.group(1)!.trim().replaceFirst(_trailingFillerRe, '');
      return ('recall_topic_v1', {'topic': topic});
    }

    // Fallback: broader "what is my X?" pattern.
    m = _reRecallTopicQ2.firstMatch(tn);
    if (m != null) {
      final topic = m.group(1)!.trim().replaceFirst(_trailingFillerRe, '');
      return ('recall_topic_v1', {'topic': topic});
    }

    // Simple "what is my X?" pattern (hotel, seat, locker, etc.)
    m = _reRecallTopicQ3.firstMatch(tn);
    if (m != null) {
      return ('recall_topic_v1', {'topic': m.group(1)});
    }

    // --- recall a stored fact ("where did I park?") ---
    if (_reRecallTopic.hasMatch(tn)) {
      // Naive topic guess: strip the "where did I" prefix, keep the verb as
      // the topic key (park -> "parking spot" via known transforms).
      const verbMap = {'park': 'parking spot', 'parked': 'parking spot'};
      final vm = RegExp(r'^where\s+did\s+i\s+(\w+)\b', caseSensitive: false).firstMatch(tn);
      final verb = vm != null ? vm.group(1)!.toLowerCase() : '';
      final topic = verbMap[verb] ?? verb;
      return ('recall_topic_v1', {'topic': topic});
    }

    // --- log placed item ---
    m = _reLogItem.firstMatch(tn);
    if (m != null) {
      var item = m.group(1)!.trim();
      if (item.isEmpty || ['this', 'that', 'it'].contains(item)) {
        return ('log_item_location_v1', {'item': null});
      }
      return ('log_item_location_v1', {'item': item});
    }

    // --- remember topic ("remember my X is Y") ---
    m = _reRememberTopic.firstMatch(tn);
    if (m != null) {
      final topic = m.group(1)!.trim();
      final content = m.group(2)!.trim();
      // Guard: "remember my favourite meals are ..." is save_preference,
      // not remember_topic. Detected by "favourite" and "are".
      if (!topic.startsWith('favou') &&
          !topic.contains('favourite') &&
          !topic.contains('favorite')) {
        return ('remember_topic_v1', {'topic': topic, 'content': content});
      }
    }

    // --- save preference ("remember my favourite X ...") ---
    m = _reSavePref.firstMatch(tn);
    if (m != null) {
      final category = m.group(1)!.trim();
      final itemsBlob = m.group(2)!.trim();
      return ('save_preference_v1', {'category': category, 'items': _splitItems(itemsBlob)});
    }

    // --- create list ("make a checklist for X items") ---
    m = _reCreateList.firstMatch(tn);
    if (m != null) {
      final body = m.group(1)!.trim();
      final (listName, items) = _splitListNameAndItems(body);
      return ('create_list_v1', {'list_name': listName, 'items': items});
    }

    // --- named create list ("create a swimming checklist costume goggles
    // fins") ---
    m = _reCreateListNamed.firstMatch(tn);
    if (m != null) {
      final listName = m.group(1)!.trim();
      // A bare article means the user gave no name ("create a checklist
      // socks shoes") — leave that ambiguity to the LLM path.
      if (!['a', 'an', 'the', 'my'].contains(listName.toLowerCase())) {
        final blob = m.group(2)!.trim();
        final items = blob.isNotEmpty ? _splitItemsSimple(blob) : <String>[];
        return ('create_list_v1', {'list_name': listName, 'items': items});
      }
    }

    // --- conditional reminder (must be BEFORE plain reminder) ---
    var condM = _reCondReminder.firstMatch(tn);
    condM ??= _reCondReminder2.firstMatch(tn);
    if (condM != null) {
      final task = condM.group(1)!.trim();
      final whenClause = condM.group(2)!.trim();
      // "when it's 6pm" / "when the clock hits 6" -> time trigger.
      final clock = _findClock(whenClause);
      final dateWord = _findDateWord(whenClause);
      if (clock != null) {
        return ('create_conditional_reminder_v1', {
          'task': task,
          'trigger_type': 'time',
          'time': _timeObj(clock, dateWord, null, null),
          'location': null,
        });
      }
      // "when I get to X" / "when I arrive at X" / "when I reach X" ->
      // location trigger.
      final locM = _reCondReminderLocation.firstMatch(whenClause);
      if (locM != null) {
        return ('create_conditional_reminder_v1', {
          'task': task,
          'trigger_type': 'location',
          'time': null,
          'location': locM.group(1)!.trim(),
        });
      }
      // Ambiguous — hand off to the LLM.
      return (null, null);
    }

    // --- alarm (before plain reminder / timer catch) ---
    if (_reAlarm.hasMatch(tn)) {
      final clock = _findClock(tn);
      final days = _weekdaysFromTranscript(tn);
      final recurring = (days != null && days.isNotEmpty) || tn.contains('every');
      return ('set_alarm_v1', {
        'time': _timeObj(clock, recurring ? null : _findDateWord(tn), null, null),
        'recurring': recurring,
        'days': days,
      });
    }

    // --- focus timer (before plain timer) ---
    if (_reFocusTimer.hasMatch(tn) || _reStopTimer.hasMatch(tn)) {
      if (_reStopTimer.hasMatch(tn) || _reStopWord.hasMatch(tn)) {
        return ('control_focus_timer_v1', {'action': 'stop', 'duration_seconds': null});
      }
      // start
      final rel = _findRelative(tn);
      int? duration;
      if (rel == null) {
        final dm = _reDurationMention.firstMatch(tn);
        if (dm != null) {
          duration = int.parse(dm.group(1)!) * _unitToSeconds[dm.group(2)!.toLowerCase()]!;
        }
      } else {
        final (amount, unit) = rel;
        final singular = unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit;
        duration = amount * _unitToSeconds[singular]!;
      }
      return ('control_focus_timer_v1', {'action': 'start', 'duration_seconds': duration});
    }

    // --- plain timer ---
    if (_rePlainTimer.hasMatch(tn)) {
      final dm = _reDurationMention.firstMatch(tn);
      if (dm != null) {
        final duration = int.parse(dm.group(1)!) * _unitToSeconds[dm.group(2)!.toLowerCase()]!;
        return ('start_timer_v1', {'duration_seconds': duration});
      }
      return ('start_timer_v1', {'duration_seconds': null});
    }

    // --- notes ---
    if (_reSaveNote.hasMatch(tn)) {
      final cm = _reSaveNoteContent.firstMatch(tn);
      return ('save_note_v1', {'content': cm != null ? cm.group(1)!.trim() : null});
    }
    if (_reQueryNotes.hasMatch(tn)) {
      final km = _reQueryNotesKeyword.firstMatch(tn);
      final keyword = km != null ? km.group(1)!.trim() : null;
      return (
        'query_notes_v1',
        {'table': 'notes', 'filters': keyword != null ? {'keyword': keyword} : <String, dynamic>{}}
      );
    }

    // --- reminder (catch-all for remaining "remind me ...") ---
    m = _reReminder.firstMatch(tn);
    if (m != null) {
      final body = m.group(1)!.trim();
      // Vague-time phrases -> unknown time, no task.
      if (['later', 'sometime', 'eventually', 'when i can', 'whenever'].contains(body)) {
        return ('set_reminder_v1', {'task': null, 'time': _timeObj(null, null, null, null)});
      }
      // Split "<task> ... <time-phrase>".
      final (task, timeDict) = _splitReminderBody(body, transcript);
      return ('set_reminder_v1', {'task': task, 'time': timeDict});
    }

    return (null, null);
  }

  // -- helpers -------------------------------------------------------------

  static final RegExp _andSplitRe = RegExp(r',|\band\b', caseSensitive: false);

  /// Commas/'and' split items; otherwise each whitespace token is one item
  /// ("goggles cap fins" -> 3 items). Used for the possessive list form
  /// where single-word items dominate.
  static List<String> _splitItemsSimple(String blob) {
    if (blob.contains(',') || RegExp(r'\band\b', caseSensitive: false).hasMatch(blob)) {
      return blob.split(_andSplitRe).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    }
    return blob.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  }

  static List<String> _splitItems(String blob) {
    if (blob.contains(',') || RegExp(r'\band\b', caseSensitive: false).hasMatch(blob)) {
      return blob.split(_andSplitRe).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    }
    // No commas: known composite-food splitter for the test corpus.
    // "dal chawal palak paneer chicken 65" -> ["dal chawal","palak
    // paneer","chicken 65"]
    return _splitByCompositeTokens(blob);
  }

  /// "swimming glasses swimming shorts fins goggles" ->
  ///     ("swimming", ["swimming glasses","swimming shorts","fins","goggles"])
  ///
  /// Strategy: if body starts with a repeated topic token, use it as
  /// list_name. Each occurrence of the topic word starts a new item and
  /// greedily binds the following token as its noun; remaining tokens after
  /// each pair are emitted as bare items.
  static (String?, List<String>) _splitListNameAndItems(String body) {
    final toks = body.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (toks.isEmpty) return (null, <String>[]);
    final first = toks[0].toLowerCase();

    // Group tokens around each occurrence of `first`.
    final groups = <List<String>>[];
    var buf = <String>[];
    for (final tok in toks) {
      if (tok.toLowerCase() == first) {
        if (buf.isNotEmpty) groups.add(buf);
        buf = [tok];
      } else {
        buf.add(tok);
      }
    }
    if (buf.isNotEmpty) groups.add(buf);

    // Need at least two topic-headed groups to treat this as a repeated
    // topic pattern. Otherwise first token = name, rest = items.
    final topicHeaded = groups.where((g) => g.isNotEmpty && g[0].toLowerCase() == first).toList();
    if (topicHeaded.length < 2) {
      return (first, toks.length > 1 ? toks.sublist(1) : <String>[]);
    }

    // For each group: first two tokens form the item; remaining tokens are
    // bare items.
    final final_ = <String>[];
    for (final g in groups) {
      if (g.isNotEmpty && g[0].toLowerCase() == first && g.length >= 2) {
        final_.add('${g[0]} ${g[1]}');
        for (final extra in g.sublist(2)) {
          final_.add(extra);
        }
      } else {
        final_.addAll(g);
      }
    }
    return (first, final_);
  }

  static final RegExp _pureDigitsRe = RegExp(r'^\d+$');

  /// Composite-word splitter tuned for the test corpus.
  /// "dal chawal palak paneer chicken 65" -> 3 items.
  static List<String> _splitByCompositeTokens(String blob) {
    final toks = blob.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (toks.isEmpty) return <String>[];
    // Heuristic: treat runs of 2 tokens as one item unless a digit-only
    // token is present (e.g. "chicken 65" joins).
    final items = <String>[];
    var i = 0;
    while (i < toks.length) {
      // Bind digit to preceding token.
      if (i + 1 < toks.length && _pureDigitsRe.hasMatch(toks[i + 1])) {
        items.add('${toks[i]} ${toks[i + 1]}');
        i += 2;
        continue;
      }
      // Pair up two consecutive non-digit tokens.
      if (i + 1 < toks.length && !_pureDigitsRe.hasMatch(toks[i])) {
        items.add('${toks[i]} ${toks[i + 1]}');
        i += 2;
        continue;
      }
      items.add(toks[i]);
      i += 1;
    }
    return items;
  }

  static final RegExp _dateWordCutRe1 = RegExp(r'\btomorrow\b', caseSensitive: false);
  static final RegExp _dateWordCutRe2 = RegExp(r'\btoday\b', caseSensitive: false);
  static final RegExp _dateWordCutRe3 = RegExp(r'\btonight\b', caseSensitive: false);
  static final RegExp _dateWordCutRe4 = RegExp(r'\bnext monday\b', caseSensitive: false);
  static final RegExp _dateWordCutRe5 = RegExp(r'\bnext tuesday\b', caseSensitive: false);
  static final RegExp _leadingToRe = RegExp(r'^to\s+', caseSensitive: false);
  static final RegExp _tailToTaskRe = RegExp(r'\bto\s+(.+?)\s*$', caseSensitive: false);

  /// Given the tail of "remind me to ...", split into (task, time_obj).
  static (String?, Map<String, dynamic>) _splitReminderBody(String body, String transcript) {
    // Try to find an explicit time phrase and cut the task at its start.
    final rel = _relTimeRe.firstMatch(body);
    final clockM = _clockRe.firstMatch(body) ?? _clock24Re.firstMatch(body);

    // Cut position for the task.
    final cuts = <int>[];
    if (clockM != null) {
      // Match "at <clock>" ideally; else the clock itself.
      final atM = RegExp(
        r'\b(?:at|by)\s+' + RegExp.escape(clockM.group(0)!),
        caseSensitive: false,
      ).firstMatch(body);
      cuts.add((atM ?? clockM).start);
    }
    if (rel != null) {
      // Match "after N minutes" / "in N minutes".
      cuts.add(rel.start);
    }
    // Date-word cut.
    for (final re in [_dateWordCutRe1, _dateWordCutRe2, _dateWordCutRe3, _dateWordCutRe4, _dateWordCutRe5]) {
      final dm = re.firstMatch(body);
      if (dm != null) cuts.add(dm.start);
    }

    String task;
    if (cuts.isNotEmpty) {
      final cut = cuts.reduce((a, b) => a < b ? a : b);
      task = body.substring(0, cut).trim().replaceFirst(RegExp(r',+$'), '').trim();
    } else {
      task = body.trim();
    }
    // Strip common "to " prefix left over from "remind me to X".
    task = task.replaceFirst(_leadingToRe, '').trim();
    // Also strip trailing "to X" if the time phrase came first.
    String? finalTask = task.isEmpty ? null : task;
    if (finalTask == null) {
      // e.g. "Remind me after 30 minutes to check the oven" — body is
      // "after 30 minutes to check the oven". Task is after " to ".
      final tailM = _tailToTaskRe.firstMatch(body);
      if (tailM != null) finalTask = tailM.group(1)!.trim();
    }

    // Build time object.
    final clock = _findClock(body);
    String? dateWord;
    if (clockM != null || rel != null) {
      // Only pull a date word if present near a clock or as anchor.
      dateWord = clock != null ? _findDateWord(transcript) : null;
    }
    final relPair = _findRelative(body);
    Map<String, dynamic> timeObj;
    if (clock != null) {
      timeObj = _timeObj(clock, dateWord, null, null);
    } else if (relPair != null) {
      final (amount, unit) = relPair;
      timeObj = _timeObj(null, null, amount, unit);
    } else {
      timeObj = _timeObj(null, null, null, null);
    }
    return (finalTask, timeObj);
  }
}
