/// lib/core/utils/parameter_normalizer.dart
///
/// Deterministic fix-up pass applied AFTER parsing the model's JSON,
/// independent of the prompt — verbatim port of normalize_parameters()
/// from main.py. Cheap insurance against prompt regressions or a future
/// model swap re-introducing bugs already fixed once.

class ParameterNormalizer {
  ParameterNormalizer._();

  static const List<String> weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  static const List<String> _weekdayOrder = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  /// Features where "time" is legitimately a bare null rather than the
  /// {"type": "unknown", ...} object — currently only the location-trigger
  /// branch of the conditional reminder.
  static const Set<String> featuresAllowingNullTime = {
    'create_conditional_reminder_v1',
  };

  static final RegExp _possessivePrefixRe = RegExp(
    r'^(my|your|his|her|our|their|the)\s+',
    caseSensitive: false,
  );

  static final RegExp _durationMentionRe = RegExp(
    r'(\d+)\s*(second|minute|hour)s?\b',
    caseSensitive: false,
  );

  static const Map<String, int> _unitToSeconds = {
    'second': 1,
    'minute': 60,
    'hour': 3600,
  };

  /// The model sometimes emits abbreviated units ("m", "min") while
  /// TimeResolver only accepts the full words — normalize before resolving.
  static const Map<String, String> _timeUnitAliases = {
    's': 'seconds', 'sec': 'seconds', 'secs': 'seconds',
    'second': 'seconds', 'seconds': 'seconds',
    'm': 'minutes', 'min': 'minutes', 'mins': 'minutes',
    'minute': 'minutes', 'minutes': 'minutes',
    'h': 'hours', 'hr': 'hours', 'hrs': 'hours',
    'hour': 'hours', 'hours': 'hours',
  };

  /// Accepts "17:00", "17:00:00", "5:30pm", "5 PM" — anything with either
  /// explicit minutes or an am/pm marker.
  static final RegExp _clockTimeRe = RegExp(
    r'^\s*(\d{1,2})(?::(\d{2}))?(?::\d{2})?\s*([ap])\.?m?\.?\s*$',
    caseSensitive: false,
  );
  static final RegExp _clockTime24Re = RegExp(r'^\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*$');

  /// Matches spoken clock times in a transcript: "6pm", "6:30am", etc.
  static final RegExp _spokenClockRe = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?\b',
    caseSensitive: false,
  );

  /// "remember my parking spot is level 3" -> ("parking spot", "level 3")
  static final RegExp _rememberTopicRe = RegExp(
    r'remember\s+(?:my|the)\s+(.+?)\s+(?:is|are|was)\s+(.+?)\s*$',
    caseSensitive: false,
  );

  /// "put/leave/left my <item>" — capture the noun after the possessive.
  static final RegExp _itemSalvageRe = RegExp(
    r'\b(?:put|placed|left|leave|lost)\s+(?:my|the)\s+([a-z][a-z\s]*?)(?:\s+(?:on|in|at|under|behind|near|by)\b.*|\s*[?.!]?\s*$)',
    caseSensitive: false,
  );

  /// "Remind me to call mom tomorrow at 5pm" -> "call mom"
  /// "Remind me after 30 minutes to check the oven" -> "check the oven"
  static final RegExp _reminderTaskLeadRe = RegExp(
    r'remind\s+me\s+to\s+(.+?)(?=\s+(?:tomorrow|today|tonight|at\b|in\b|after\b|when\b|on\b|by\b|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\s*$)',
    caseSensitive: false,
  );
  static final RegExp _reminderTaskTailRe = RegExp(
    r'remind\s+me\s+(?:after|in)\s+\d+\s*\w+\s+to\s+(.+?)\s*$',
    caseSensitive: false,
  );

  /// Best-effort day-set recovery when the model emits a broken 'days'
  /// field. Handles named days and 'weekday'/'weekend' shorthand.
  static List<String>? _extractWeekdaysFromTranscript(String transcript) {
    final t = transcript.toLowerCase();
    if (t.contains('weekday') || t.contains('weekdays')) {
      return ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
    }
    if (t.contains('weekend') || t.contains('weekends')) {
      return ['Saturday', 'Sunday'];
    }
    final found = <String>[];
    for (final day in _weekdayOrder) {
      if (t.contains(day.toLowerCase())) found.add(day);
    }
    return found.isEmpty ? null : found;
  }

  static String? _salvageReminderTask(String transcript) {
    final t = transcript.trim().replaceFirst(RegExp(r'[.?!]+$'), '');
    final leadMatch = _reminderTaskLeadRe.firstMatch(t);
    if (leadMatch != null) {
      final task = leadMatch.group(1)!.trim().replaceFirst(RegExp(r'[,.]+$'), '');
      if (task.isNotEmpty &&
          !['later', 'sometime', 'eventually'].contains(task.toLowerCase())) {
        return task;
      }
    }
    final tailMatch = _reminderTaskTailRe.firstMatch(t);
    if (tailMatch != null) {
      final task = tailMatch.group(1)!.trim().replaceFirst(RegExp(r'[,.]+$'), '');
      if (task.isNotEmpty) return task;
    }
    return null;
  }

  static (String, String)? _salvageRememberTopic(String transcript) {
    final t = transcript.trim().replaceFirst(RegExp(r'[.?!]+$'), '');
    final m = _rememberTopicRe.firstMatch(t);
    if (m == null) return null;
    final topic = m.group(1)!.trim().toLowerCase();
    final content = m.group(2)!.trim().replaceFirst(RegExp(r'[.?!]+$'), '');
    return (topic.isNotEmpty && content.isNotEmpty) ? (topic, content) : null;
  }

  static String? _salvageItemFromTranscript(String transcript) {
    final t = transcript.trim().replaceFirst(RegExp(r'[.?!]+$'), '');
    final m = _itemSalvageRe.firstMatch(t);
    if (m == null) return null;
    var item = m.group(1)!.trim().toLowerCase();
    item = item.replaceAll(RegExp(r'\s+'), ' ');
    return item.isEmpty ? null : item;
  }

  static Map<String, dynamic> normalize(
    Map<String, dynamic> parameters, {
    String? featureId,
    String? transcript,
  }) {
    // Normalize the time object before anything below reads it.
    if (parameters['time'] is Map) {
      parameters['time'] = _normalizeTimeObject(
        Map<String, dynamic>.from(parameters['time'] as Map),
      );
    } else if (parameters['time'] is String) {
      // Fallback: if the model returned an ISO timestamp string, convert to
      // a time object.
      parameters['time'] = _parseIsoTimeString(parameters['time'] as String);
    }

    // P5: if the model emitted relative with no clock_time but the
    // transcript has a spoken clock time (e.g. "6pm"), override to absolute.
    final timeAfterParse = parameters['time'];
    if (timeAfterParse is Map &&
        timeAfterParse['type'] == 'relative' &&
        timeAfterParse['clock_time'] == null &&
        transcript != null &&
        transcript.isNotEmpty) {
      final m = _spokenClockRe.firstMatch(transcript);
      if (m != null) {
        var h = int.parse(m.group(1)!);
        final mi = m.group(2) != null ? int.parse(m.group(2)!) : 0;
        final ampm = m.group(3)!.toLowerCase();
        if (ampm == 'p' && h != 12) h += 12;
        if (ampm == 'a' && h == 12) h = 0;
        timeAfterParse['type'] = 'absolute';
        timeAfterParse['clock_time'] =
            '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
        timeAfterParse['amount'] = null;
        timeAfterParse['unit'] = null;
        timeAfterParse['date'] = null;
      }
    }

    // If "days" came back as a broken/truncated string (e.g. "["),
    // re-derive from the transcript when possible.
    if (parameters['days'] is String &&
        transcript != null &&
        transcript.isNotEmpty) {
      parameters['days'] = _extractWeekdaysFromTranscript(transcript);
    }

    // Backstop: "items" may come back as one comma/"and"-joined string
    // instead of an array — LocalDataStore expects a List<String>.
    if (parameters['items'] is String) {
      final items = (parameters['items'] as String)
          .split(RegExp(r',|\band\b', caseSensitive: false))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      parameters['items'] = items.isEmpty ? null : items;
    }
    // Weekday names always capitalized.
    if (parameters['days'] is List) {
      parameters['days'] = (parameters['days'] as List).map((d) {
        if (d is String) {
          return d.trim().isEmpty
              ? d
              : d.trim()[0].toUpperCase() + d.trim().substring(1).toLowerCase();
        }
        return d;
      }).toList();
    }

    final bool isRecurring = parameters['recurring'] == true ||
        (parameters['days'] is List && (parameters['days'] as List).isNotEmpty);
    final timeObj = parameters['time'];
    if (isRecurring && timeObj is Map) {
      timeObj['date'] = null;
    }

    // Backstop: "time" should never be bare null unless this specific
    // feature legitimately allows it.
    if (parameters.containsKey('time') &&
        parameters['time'] == null &&
        !(featureId != null && featuresAllowingNullTime.contains(featureId))) {
      parameters['time'] = {
        'type': 'unknown',
        'clock_time': null,
        'date': null,
        'amount': null,
        'unit': null,
      };
    }

    // Backstop: strip a leading possessive/article from "item".
    if (parameters['item'] is String) {
      final stripped =
          (parameters['item'] as String).replaceFirst(_possessivePrefixRe, '').trim();
      parameters['item'] = stripped.isEmpty ? null : stripped;
    }

    // Backstop: re-derive duration_seconds from an unambiguous "<N> <unit>"
    // mention in the transcript when exactly one such mention exists.
    if (parameters.containsKey('duration_seconds') &&
        transcript != null &&
        transcript.isNotEmpty) {
      final matches = _durationMentionRe.allMatches(transcript).toList();
      if (matches.length == 1) {
        final amount = int.parse(matches.first.group(1)!);
        final unit = matches.first.group(2)!.toLowerCase();
        final expected = amount * _unitToSeconds[unit]!;
        if (parameters['duration_seconds'] != expected) {
          parameters['duration_seconds'] = expected;
        }
      }
    }

    // Post-processing: common extraction issues.
    return _postProcessParameters(parameters, featureId, transcript);
  }

  /// Fix common extraction issues that require feature-specific context.
  static Map<String, dynamic> _postProcessParameters(
    Map<String, dynamic> parameters,
    String? featureId,
    String? transcript,
  ) {
    // Fix underscore -> space in topic/reference/event_hint fields, and
    // strip a leading "the " from references.
    for (final key in ['topic', 'reference', 'event_hint']) {
      final val = parameters[key];
      if (val is String) {
        if (val.contains('_') && !val.contains(' ')) {
          parameters[key] = val.replaceAll('_', ' ');
        } else if (val.startsWith('the ')) {
          parameters[key] = val.substring(4);
        }
      }
    }

    // Fix item: convert generic pronouns to null, drop transcript-echo,
    // strip possessives if the model didn't.
    if (parameters['item'] is String) {
      final item = parameters['item'] as String;
      final itemLower = item.toLowerCase().trim();
      final transcriptLower = (transcript ?? '').toLowerCase().trim();
      if (['this', 'that', 'it', 'something', 'anything'].contains(itemLower)) {
        parameters['item'] = null;
      } else if (transcript != null &&
          (itemLower == transcriptLower ||
              (transcriptLower.contains(itemLower) && item.length > 30))) {
        // Model echoed the whole transcript — try to salvage the noun
        // after "my"/"the"/"put"/"leave"/"left".
        parameters['item'] = _salvageItemFromTranscript(transcript);
      }
    }

    // Fix topic/content: reject transcript-echo and empty content.
    if (featureId == 'remember_topic_v1' &&
        transcript != null &&
        transcript.isNotEmpty) {
      final topic = parameters['topic'];
      final content = parameters['content'];
      final transcriptLower = transcript.toLowerCase().trim();
      if (topic is String && topic.toLowerCase().trim() == transcriptLower) {
        final salvaged = _salvageRememberTopic(transcript);
        if (salvaged != null) {
          parameters['topic'] = salvaged.$1;
          parameters['content'] = salvaged.$2;
        } else {
          parameters['topic'] = null;
        }
      } else if (topic is String && content is String && topic == content) {
        final salvaged = _salvageRememberTopic(transcript);
        if (salvaged != null) {
          parameters['topic'] = salvaged.$1;
          parameters['content'] = salvaged.$2;
        }
      }
    }

    if (featureId == 'recall_topic_v1' &&
        transcript != null &&
        transcript.isNotEmpty) {
      final topic = parameters['topic'];
      if (topic is String && topic.toLowerCase().trim() == transcript.toLowerCase().trim()) {
        parameters['topic'] = null;
      }
    }

    // Fix list_name: if it's a concatenation of items, try to extract the
    // actual name.
    if (featureId == 'create_list_v1' && parameters.containsKey('list_name')) {
      final name = parameters['list_name'];
      final items = parameters['items'];
      if (name is String && name.isNotEmpty && items is List && items.isNotEmpty) {
        final nameLower = name.toLowerCase().replaceAll('_', ' ');
        final itemsConcat = items.join(' ').toLowerCase();
        if (nameLower == itemsConcat || itemsConcat.contains(nameLower)) {
          final firstItem = items.first;
          if (firstItem is String) {
            final words = firstItem.split(RegExp(r'\s+'));
            if (words.length >= 2) {
              parameters['list_name'] = words.first;
            }
          }
        }
      }
    }

    // Salvage a reminder task from the transcript if the model dropped it.
    if ((featureId == 'set_reminder_v1' ||
            featureId == 'create_conditional_reminder_v1') &&
        transcript != null &&
        transcript.isNotEmpty) {
      if (parameters['task'] == null || parameters['task'] == featureId) {
        final salvagedTask = _salvageReminderTask(transcript);
        if (salvagedTask != null) parameters['task'] = salvagedTask;
      }
    }

    // Strip inferred date words when the transcript does NOT actually
    // contain them. Fixes model output like time.date="today" when the
    // user said "when it's 6pm" with no date reference.
    final timeObjNow = parameters['time'];
    if (timeObjNow is Map &&
        timeObjNow['date'] != null &&
        transcript != null &&
        transcript.isNotEmpty) {
      final dateVal = timeObjNow['date'].toString().toLowerCase();
      final tLower = transcript.toLowerCase();
      bool keep;
      if (['today', 'tomorrow', 'tonight'].contains(dateVal)) {
        keep = tLower.contains(dateVal);
      } else if (weekdays.contains(dateVal)) {
        keep = tLower.contains(dateVal);
      } else {
        // ISO date or explicit — always keep.
        keep = true;
      }
      if (!keep) timeObjNow['date'] = null;
    }

    // Fix set_reminder_v1: model hallucinates task as intent name and
    // invents a relative time for vague transcripts.
    if (featureId == 'set_reminder_v1' &&
        transcript != null &&
        transcript.isNotEmpty) {
      final transcriptLower = transcript.toLowerCase().trim();
      if (parameters['task'] == 'set_reminder_v1') {
        parameters['task'] = null;
      }
      const vagueTimePhrases = ['later', 'sometime', 'eventually', 'when i can', 'whenever'];
      if (vagueTimePhrases.any((phrase) => transcriptLower.contains(phrase))) {
        final timeObj = parameters['time'];
        if (timeObj is Map && timeObj['type'] == 'relative') {
          parameters['time'] = {
            'type': 'unknown',
            'clock_time': null,
            'date': null,
            'amount': null,
            'unit': null,
          };
        }
      }
    }

    return parameters;
  }

  /// Repairs the model's time object so TimeResolver can resolve it:
  /// unit aliases, am/pm and seconds-bearing clock strings, numeric strings,
  /// and a missing/unknown "type" when the other fields make it obvious.
  /// Also corrects explicit wrong types (e.g. model says "relative" but
  /// provides clock_time). Ensures all 5 time fields are present.
  static Map<String, dynamic> _normalizeTimeObject(Map<String, dynamic> time) {
    final unit = time['unit'];
    if (unit is String) {
      time['unit'] = _timeUnitAliases[unit.trim().toLowerCase()] ?? unit;
    }

    final amount = time['amount'];
    if (amount is String) {
      time['amount'] = num.tryParse(amount.trim()) ?? amount;
    }

    var clock = time['clock_time'];
    // Strip literal "null" / "None" strings the model sometimes emits.
    if (clock is String && ['null', 'none', ''].contains(clock.trim().toLowerCase())) {
      time['clock_time'] = null;
      clock = null;
    }
    if (clock is String) {
      final m24 = _clockTime24Re.firstMatch(clock);
      final mAmPm = m24 == null ? _clockTimeRe.firstMatch(clock) : null;
      int? hour, minute;
      if (m24 != null) {
        hour = int.parse(m24.group(1)!);
        minute = int.parse(m24.group(2)!);
      } else if (mAmPm != null && mAmPm.group(3) != null) {
        hour = int.parse(mAmPm.group(1)!);
        minute = mAmPm.group(2) != null ? int.parse(mAmPm.group(2)!) : 0;
        final isPm = mAmPm.group(3)!.toLowerCase() == 'p';
        if (isPm && hour != 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
      }
      if (hour != null && minute != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        time['clock_time'] =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    }

    final t = time['type'];
    final hasClock = time['clock_time'] != null;
    final hasAmtUnit = time['amount'] != null && time['unit'] != null;

    // If the model says relative AND provides amount+unit, trust that even
    // if it also filled clock_time (common failure: "30 minutes" ->
    // clock_time "0:30"). The amount/unit is the ground truth for a
    // relative time.
    if (t == 'relative' && hasAmtUnit) {
      time['type'] = 'relative';
      time['clock_time'] = null;
      time['date'] = null;
    } else if (hasClock) {
      // Otherwise, if clock_time is present, MUST be absolute — also null
      // out amount/unit, which are only meaningful for relative.
      time['type'] = 'absolute';
      time['amount'] = null;
      time['unit'] = null;
    } else if (hasAmtUnit) {
      // No clock_time but amount+unit -> relative.
      time['type'] = 'relative';
    } else {
      // No clock_time, no amount+unit -> nothing to resolve. Force unknown
      // regardless of what the model claimed (covers the "relative with
      // all-null slots" failure mode).
      time['type'] = 'unknown';
      time['date'] = null;
    }

    // Ensure all 5 time fields are present (required by schema and
    // downstream equality checks).
    time.putIfAbsent('type', () => 'unknown');
    time.putIfAbsent('clock_time', () => null);
    time.putIfAbsent('date', () => null);
    time.putIfAbsent('amount', () => null);
    time.putIfAbsent('unit', () => null);

    return time;
  }

  /// Converts an ISO timestamp string ("2026-07-15T17:00" or
  /// "2026-07-15T17:00:00") to the 5-key time object format.
  static Map<String, dynamic> _parseIsoTimeString(String timeStr) {
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::\d{2})?')
        .firstMatch(timeStr);
    if (isoMatch == null) {
      return {
        'type': 'unknown',
        'clock_time': null,
        'date': null,
        'amount': null,
        'unit': null,
      };
    }

    final year = int.parse(isoMatch.group(1)!);
    final month = int.parse(isoMatch.group(2)!);
    final day = int.parse(isoMatch.group(3)!);
    final hour = int.parse(isoMatch.group(4)!);
    final minute = int.parse(isoMatch.group(5)!);

    final now = DateTime.now();
    final targetDate = DateTime(year, month, day);
    final today = DateTime(now.year, now.month, now.day);

    String dateStr;
    if (targetDate == today) {
      dateStr = 'today';
    } else if (targetDate == today.add(const Duration(days: 1))) {
      dateStr = 'tomorrow';
    } else {
      dateStr =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }

    final clockTime =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    return {
      'type': 'absolute',
      'clock_time': clockTime,
      'date': dateStr,
      'amount': null,
      'unit': null,
    };
  }
}
