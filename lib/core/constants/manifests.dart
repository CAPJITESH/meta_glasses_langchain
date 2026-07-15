/// lib/core/constants/manifests.dart
///
/// Verbatim port of manifests.py FEATURES. Central feature registry:
/// feature_id -> {description, schema}. Keep in sync with prompts.dart's
/// few-shot examples if either ever changes.
library;

import '../models/feature_manifest.dart';

class AiManifests {
  AiManifests._();

  static const Map<String, FeatureManifest> features = {
    'set_reminder_v1': FeatureManifest(
      description: 'Set a reminder at a specific time',
      schema: {'task': 'string', 'time': 'time object'},
    ),
    'set_alarm_v1': FeatureManifest(
      description: 'Set an alarm, optionally recurring',
      schema: {
        'time': 'time object',
        'recurring': 'boolean',
        'days': 'array of day name strings, optional',
      },
    ),
    'start_timer_v1': FeatureManifest(
      description: 'Start a countdown timer',
      schema: {'duration_seconds': 'integer'},
    ),
    'save_note_v1': FeatureManifest(
      description: 'Save a freeform note',
      schema: {'content': 'string'},
    ),
    'query_notes_v1': FeatureManifest(
      description: 'Query saved notes by keyword',
      schema: {
        'table': 'string',
        'filters': 'object with optional keyword field',
      },
    ),
    'query_time_remaining_v1': FeatureManifest(
      description: 'Time remaining until next calendar event or a named event',
      schema: {'event_hint': 'string or null'},
    ),
    'create_conditional_reminder_v1': FeatureManifest(
      description:
          "Reminder triggered by time or location ('remind me to X when Y')",
      schema: {
        'task': 'string',
        'trigger_type': "'time' or 'location'",
        'time': "time object when trigger_type='time', else null",
        'location': "string when trigger_type='location', else null",
      },
    ),
    'query_recent_activity_v1': FeatureManifest(
      description: "Summarize user's recent activity",
      schema: {},
    ),
    'log_item_location_v1': FeatureManifest(
      description:
          "Log where user placed an item ('remember where I put this')",
      schema: {'item': 'string or null'},
    ),
    'query_item_location_v1': FeatureManifest(
      description: "Recall last logged location of an item",
      schema: {'item': 'string'},
    ),
    'control_focus_timer_v1': FeatureManifest(
      description: 'Start or stop a focus/Pomodoro timer',
      schema: {
        'action': "'start' or 'stop'",
        'duration_seconds': 'integer or null',
      },
    ),
    'query_next_briefing_v1': FeatureManifest(
      description: "Brief the user on what's next on their calendar",
      schema: {},
    ),
    'create_list_v1': FeatureManifest(
      description: 'Create a named checklist from speech',
      schema: {'list_name': 'string', 'items': 'array of strings'},
    ),
    'save_preference_v1': FeatureManifest(
      description: 'Save preferences under a named category',
      schema: {'category': 'string', 'items': 'array of strings'},
    ),
    'recall_stored_info_v1': FeatureManifest(
      description: 'Retrieve a stored list or preference',
      schema: {
        'query_type': "'list' or 'preference'",
        'reference': 'string — the list name or category',
      },
    ),
    'start_meeting_v1': FeatureManifest(
      description: 'Start meeting transcript capture',
      schema: {'meeting_name': 'string or null'},
    ),
    'end_meeting_v1': FeatureManifest(
      description: 'End meeting transcript capture',
      schema: {},
    ),
    'summarize_meeting_v1': FeatureManifest(
      description: 'Summarize a meeting transcript',
      schema: {'meeting_name': 'string or null'},
    ),

    // -------------------------------------------------------------------------
    // Personalization showcase (Section 6): remember/recall arbitrary content
    // under a user-named topic. "store broadly, retrieve narrowly" — the write
    // side captures topic + content; the read side captures only the topic and
    // the executor injects just the single matched entry into groundedAnswer().
    // -------------------------------------------------------------------------
    'remember_topic_v1': FeatureManifest(
      description:
          "Remember/save freeform content under a named topic "
          "('remember my swimming checklist: goggles, cap, towel')",
      schema: {'topic': 'string', 'content': 'string'},
    ),
    'recall_topic_v1': FeatureManifest(
      description:
          "Recall previously-saved content by topic "
          "('what's on my swimming checklist?')",
      schema: {'topic': 'string'},
    ),

    // -------------------------------------------------------------------------
    // Section 5 extensibility proof — new capabilities added as manifest
    // entries + a schema only. None of these required any change to
    // AiService.extract(), ParameterNormalizer, or the model download/load
    // layer; each is handled by a small executor keyed on its feature id.
    // -------------------------------------------------------------------------
    'rag_query_v1': FeatureManifest(
      description:
          'Answer an open question from the on-device knowledge base '
          '(semantic retrieval over stored documents)',
      schema: {'query': 'string'},
    ),
    'ocr_read_text_v1': FeatureManifest(
      description:
          'Read text visible in the current camera frame '
          "('what does this sign say?')",
      schema: {'target': 'string or null'},
    ),
    'query_location_v1': FeatureManifest(
      description: "Answer where the user is now, or about a nearby place",
      schema: {'place_hint': 'string or null'},
    ),
  };
}
