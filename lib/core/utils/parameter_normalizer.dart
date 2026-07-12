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

  static Map<String, dynamic> normalize(
    Map<String, dynamic> parameters, {
    String? featureId,
    String? transcript,
  }) {
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
}
