/// lib/core/utils/glasses_message_builder.dart
///
/// Verbatim port of build_glasses_message() from main.py.

class GlassesMessageBuilder {
  GlassesMessageBuilder._();

  static String build(
    String intent,
    Map<String, dynamic> parameters,
    String? humanTime,
  ) {
    switch (intent) {
      case 'set_reminder_v1':
        if (parameters['task'] == null || humanTime == null) {
          final missing = <String>[];
          if (parameters['task'] == null) missing.add('what to remind you about');
          if (humanTime == null) missing.add('what time');
          return "I didn't catch ${missing.join(' and ')} — can you say that again?";
        }
        return "Okay, I'll remind you to ${parameters['task']} at $humanTime.";

      case 'set_alarm_v1':
        if (humanTime == null) {
          return "I didn't catch what time to set the alarm for — can you repeat that?";
        }
        return 'Alarm set for $humanTime.';

      case 'start_timer_v1':
        return 'Timer started for '
            '${_formatDuration(parameters['duration_seconds'])}.';

      case 'save_note_v1':
        return 'Got it, note saved.';

      case 'query_notes_v1':
        return "Here's what I found in your notes.";

      case 'query_time_remaining_v1':
        return 'Checking your calendar for how much time you have.';

      case 'create_conditional_reminder_v1':
        final task = parameters['task'];
        final triggerType = parameters['trigger_type'];
        if (task == null || triggerType == null) {
          return "I didn't catch the full reminder — can you say that again?";
        }
        if (triggerType == 'time' && humanTime != null) {
          return "Okay, I'll remind you to $task at $humanTime.";
        }
        if (triggerType == 'location' && parameters['location'] != null) {
          return "Okay, I'll remind you to $task when you get to ${parameters['location']}.";
        }
        return "I didn't catch when or where to remind you — can you repeat that?";

      case 'query_recent_activity_v1':
        return "Here's a summary of what you were doing.";

      case 'log_item_location_v1':
        final item = parameters['item'] ?? 'that';
        return "Got it, I'll remember where you put $item.";

      case 'query_item_location_v1':
        final item = parameters['item'];
        if (item == null) return 'Which item are you looking for?';
        return 'Checking the last place I saw your $item.';

      case 'control_focus_timer_v1':
        final action = parameters['action'];
        if (action == 'start') {
          final duration = parameters['duration_seconds'];
          return duration != null
              ? 'Starting a focus timer for ${_formatDuration(duration)}.'
              : 'Starting your focus timer.';
        }
        if (action == 'stop') return 'Focus timer stopped.';
        return 'Should I start or stop the focus timer?';

      case 'query_next_briefing_v1':
        return "Here's what's coming up next.";

      case 'create_list_v1':
        final items = (parameters['items'] as List?) ?? [];
        final name = parameters['list_name'] ?? 'your';
        return 'Saved your $name checklist with ${items.length} item${items.length != 1 ? 's' : ''}.';

      case 'save_preference_v1':
        final cat = parameters['category'] ?? 'that';
        return "Got it, I've saved your $cat.";

      case 'recall_stored_info_v1':
        final queryType = parameters['query_type'];
        final reference = parameters['reference'];
        if (reference == null) return "What would you like me to recall?";
        return queryType == 'list'
            ? "Here's what's on your $reference list."
            : "Here's what I have saved for $reference.";

      case 'start_meeting_v1':
        final name = parameters['meeting_name'];
        return name != null
            ? "Okay, I'll keep track of your $name meeting."
            : "Okay, I'll keep track of this meeting.";

      case 'end_meeting_v1':
        return 'Meeting recording stopped.';

      case 'summarize_meeting_v1':
        return 'Meeting summarized and stored.';

      default:
        return "Sorry, I didn't quite catch that.";
    }
  }

  static String _formatDuration(dynamic seconds) {
    if (seconds == null) return 'an unspecified time';
    final int s = seconds is int ? seconds : (seconds as num).toInt();
    final minutes = (s ~/ 60) % 60;
    final hours = s ~/ 3600;
    final sec = s % 60;
    final parts = <String>[];
    if (hours > 0) parts.add('$hours hour${hours != 1 ? 's' : ''}');
    if (minutes > 0) parts.add('$minutes minute${minutes != 1 ? 's' : ''}');
    if (sec > 0 && hours == 0) parts.add('$sec second${sec != 1 ? 's' : ''}');
    return parts.isEmpty ? '0 seconds' : parts.join(' ');
  }
}
