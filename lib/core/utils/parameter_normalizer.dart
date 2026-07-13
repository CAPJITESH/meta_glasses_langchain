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

    return parameters;
  }

  /// Repairs the model's time object so TimeResolver can resolve it:
  /// unit aliases, am/pm and seconds-bearing clock strings, numeric strings,
  /// and a missing/unknown "type" when the other fields make it obvious.
  static Map<String, dynamic> _normalizeTimeObject(Map<String, dynamic> time) {
    final unit = time['unit'];
    if (unit is String) {
      time['unit'] = _timeUnitAliases[unit.trim().toLowerCase()] ?? unit;
    }

    final amount = time['amount'];
    if (amount is String) time['amount'] = num.tryParse(amount.trim());

    final clock = time['clock_time'];
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
      if (hour != null && minute != null && hour <= 23 && minute <= 59) {
        time['clock_time'] =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    }

    final type = time['type'];
    if (type == null || type == 'unknown') {
      if (time['clock_time'] != null) {
        time['type'] = 'absolute';
      } else if (time['amount'] != null && time['unit'] != null) {
        time['type'] = 'relative';
      }
    }
    return time;
  }
}
