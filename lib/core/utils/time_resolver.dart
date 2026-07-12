/// lib/core/utils/time_resolver.dart
///
/// Deterministic time resolution — never trust the model's arithmetic.
/// Verbatim port of resolve_time()/_human_readable_time()/_format_duration()
/// from main.py.

class ResolvedTime {
  final String? machineIso;
  final String? human;
  const ResolvedTime(this.machineIso, this.human);
}

class TimeResolver {
  TimeResolver._();

  static const List<String> _weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  static ResolvedTime resolve(Map<String, dynamic>? timeObj, {DateTime? now}) {
    final DateTime nowDt = now ?? DateTime.now();

    if (timeObj == null || timeObj['type'] == null || timeObj['type'] == 'unknown') {
      return const ResolvedTime(null, null);
    }

    DateTime resolved;

    if (timeObj['type'] == 'relative') {
      final amount = timeObj['amount'];
      final unit = timeObj['unit'];
      if (amount == null || !['seconds', 'minutes', 'hours'].contains(unit)) {
        return const ResolvedTime(null, null);
      }
      final int amt = amount is int ? amount : (amount as num).toInt();
      Duration delta;
      switch (unit) {
        case 'seconds':
          delta = Duration(seconds: amt);
          break;
        case 'minutes':
          delta = Duration(minutes: amt);
          break;
        default:
          delta = Duration(hours: amt);
      }
      resolved = nowDt.add(delta);
    } else if (timeObj['type'] == 'absolute') {
      final clockTime = timeObj['clock_time'] as String?;
      if (clockTime == null || !clockTime.contains(':')) {
        return const ResolvedTime(null, null);
      }
      final parts = clockTime.split(':');
      int hour, minute;
      try {
        hour = int.parse(parts[0]);
        minute = int.parse(parts[1]);
      } catch (_) {
        return const ResolvedTime(null, null);
      }

      final dateWord = ((timeObj['date'] as String?) ?? 'today').trim().toLowerCase();
      DateTime baseDate = DateTime(nowDt.year, nowDt.month, nowDt.day);
      DateTime targetDate;

      if (dateWord == 'today') {
        targetDate = baseDate;
      } else if (dateWord == 'tomorrow') {
        targetDate = baseDate.add(const Duration(days: 1));
      } else if (_weekdays.contains(dateWord)) {
        final targetWeekday = _weekdays.indexOf(dateWord); // 0=Mon..6=Sun
        final nowWeekday = nowDt.weekday - 1; // Dart: 1=Mon..7=Sun -> 0..6
        int daysAhead = (targetWeekday - nowWeekday) % 7;
        if (daysAhead < 0) daysAhead += 7;
        if (daysAhead == 0) {
          final candidate =
              DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
          targetDate = candidate.isAfter(nowDt)
              ? baseDate
              : baseDate.add(const Duration(days: 7));
        } else {
          targetDate = baseDate.add(Duration(days: daysAhead));
        }
      } else {
        // Try "yyyy-MM-dd", "MMMM d", "MMM d" — fall back to today on failure.
        targetDate = _tryParseExplicitDate(dateWord, baseDate.year) ?? baseDate;
      }

      resolved = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
      if (dateWord == 'today' && resolved.isBefore(nowDt)) {
        resolved = resolved.add(const Duration(days: 1));
      }
    } else {
      return const ResolvedTime(null, null);
    }

    final machineIso = _isoMinutes(resolved);
    final human = _humanReadable(resolved, nowDt);
    return ResolvedTime(machineIso, human);
  }

  static DateTime? _tryParseExplicitDate(String dateWord, int assumedYear) {
    // "%Y-%m-%d"
    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final ymdMatch = ymd.firstMatch(dateWord);
    if (ymdMatch != null) {
      return DateTime(
        int.parse(ymdMatch.group(1)!),
        int.parse(ymdMatch.group(2)!),
        int.parse(ymdMatch.group(3)!),
      );
    }
    // "%B %d" / "%b %d" (e.g. "july 10", "jul 10")
    const monthNames = {
      'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
      'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
      'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'october': 10, 'oct': 10,
      'november': 11, 'nov': 11, 'december': 12, 'dec': 12,
    };
    final md = RegExp(r'^([a-zA-Z]+)\s+(\d{1,2})$');
    final mdMatch = md.firstMatch(dateWord);
    if (mdMatch != null) {
      final month = monthNames[mdMatch.group(1)!.toLowerCase()];
      if (month != null) {
        return DateTime(assumedYear, month, int.parse(mdMatch.group(2)!));
      }
    }
    return null;
  }

  static String _isoMinutes(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}'
        'T${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _humanReadable(DateTime resolved, DateTime now) {
    int hour12 = resolved.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final ampm = resolved.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:${resolved.minute.toString().padLeft(2, '0')} $ampm';

    final today = DateTime(now.year, now.month, now.day);
    final resolvedDay = DateTime(resolved.year, resolved.month, resolved.day);
    String dayStr;
    if (resolvedDay == today) {
      dayStr = 'today';
    } else if (resolvedDay == today.add(const Duration(days: 1))) {
      dayStr = 'tomorrow';
    } else {
      const weekdayNames = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
      ];
      const monthNames = [
        'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
        'September', 'October', 'November', 'December',
      ];
      dayStr =
          '${weekdayNames[resolved.weekday - 1]}, ${monthNames[resolved.month - 1]} ${resolved.day}';
    }
    return '$timeStr $dayStr';
  }

  static String formatDuration(int? seconds) {
    if (seconds == null) return 'an unspecified time';
    final minutes = (seconds ~/ 60) % 60;
    final hours = seconds ~/ 3600;
    final sec = seconds % 60;
    final parts = <String>[];
    if (hours > 0) parts.add('$hours hour${hours != 1 ? 's' : ''}');
    if (minutes > 0) parts.add('$minutes minute${minutes != 1 ? 's' : ''}');
    if (sec > 0 && hours == 0) parts.add('$sec second${sec != 1 ? 's' : ''}');
    return parts.isEmpty ? '0 seconds' : parts.join(' ');
  }
}
