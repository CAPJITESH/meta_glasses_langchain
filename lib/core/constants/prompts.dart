/// lib/core/constants/prompts.dart
///
/// Prompt constants for on-device LLM inference. Uses a two-stage design:
/// Stage 1 (intentClassificationPrompt) — classify intent with a compact list.
/// Stage 2 (parameterExtractionPrompt) — extract only the matched feature's
/// parameters with a tiny, feature-specific prompt.
library;

import 'dart:convert';

import 'manifests.dart';

class AiPrompts {
  AiPrompts._();

  // ---------------------------------------------------------------------------
  // Stage 1: Intent classification
  // ---------------------------------------------------------------------------

  // One-line trigger cue per feature_id, shown next to its id in the catalog
  // so the classifier has a concrete example shape to match against. Ids with
  // no cue here (e.g. Dart-only stub intents) just render bare in the catalog.
  static const Map<String, String> _triggerCues = {
    'set_reminder_v1': '"remind me to X" (task + optional time)',
    'set_alarm_v1': '"wake me up at ..." / "set an alarm"',
    'start_timer_v1':
        '"set a timer for N minutes/hours" (plain countdown)',
    'save_note_v1': '"note that ..." / "save a note"',
    'query_notes_v1': '"find/search my notes about ..."',
    'query_time_remaining_v1':
        '"how much time until my <event>" / "when is my next ..."',
    'create_conditional_reminder_v1':
        '"remind me to X when Y" — Y is a time OR place trigger',
    'query_recent_activity_v1': '"what was I doing"',
    'log_item_location_v1':
        '"remember where I put my X" (log NEW placement)',
    'query_item_location_v1':
        '"where did I leave my X" (retrieve a placed physical item)',
    'control_focus_timer_v1':
        '"start/stop focus timer" / "N minute focus timer" / "stop the timer"',
    'query_next_briefing_v1': '"what\'s next"',
    'create_list_v1': '"make a checklist for ..." (CREATE a list)',
    'save_preference_v1':
        '"remember my favourite ... are ..." (SAVE preferences)',
    'recall_stored_info_v1':
        '"what\'s on my X checklist" / "what are my favourite ..." '
            '(READ back saved list/preference)',
    'remember_topic_v1': '"remember my X is Y" (STORE a fact/topic)',
    'recall_topic_v1':
        '"where did I park?" / "what is my X" / "what was my X" '
            '(RECALL a previously-stored fact)',
  };

  static String _renderTriggerCatalog() {
    final buffer = StringBuffer();
    final ids = AiManifests.features.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final cue = _triggerCues[id];
      buffer.write(cue == null ? '- $id' : '- $id: $cue');
      if (i != ids.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static final String _triggerCatalog = _renderTriggerCatalog();

  static final String intentClassificationPrompt =
      'You are an on-device intent classifier. Pick ONE feature_id from the '
      'catalog below (or "unknown"). Output ONLY the feature_id.\n'
      '\n'
      '--- FEATURES ---\n'
      '$_triggerCatalog\n'
      '\n'
      'Rules:\n'
      '- CREATE vs RECALL: "make/save/remember my favourite X" is CREATE '
      '(create_list_v1 / save_preference_v1 / remember_topic_v1). '
      '"what\'s on my X" / "what are my X" / "where did I X" is RECALL '
      '(recall_stored_info_v1 / recall_topic_v1).\n'
      '- Physical item you just placed -> query_item_location_v1 (wallet, '
      'keys, phone). Fact you told the assistant -> recall_topic_v1 (parking '
      'spot, gate code).\n'
      '- "when it\'s 6pm" / "when I get to X" attached to a reminder -> '
      'create_conditional_reminder_v1, NOT set_reminder_v1.\n'
      '- "focus timer" (any wording) -> control_focus_timer_v1. Plain '
      '"timer" without "focus" -> start_timer_v1.\n'
      '- "going for/to <activity>" WITHOUT the word "meeting" (swim, gym, '
      'store) -> unknown.\n'
      '- Weather, news, general questions -> unknown.\n'
      '\n'
      'Examples:\n'
      'User: "Remind me to call mom tomorrow at 5pm" -> set_reminder_v1\n'
      'User: "Remind me to take the chicken out when it\'s 6pm" -> '
      'create_conditional_reminder_v1\n'
      'User: "Remind me to buy milk when I get to the grocery store" -> '
      'create_conditional_reminder_v1\n'
      'User: "Wake me up at 6:30am every weekday" -> set_alarm_v1\n'
      'User: "Set a timer for 10 minutes" -> start_timer_v1\n'
      'User: "Start a 25 minute focus timer" -> control_focus_timer_v1\n'
      'User: "Stop the timer" -> control_focus_timer_v1\n'
      'User: "Make a checklist for swimming glasses swimming shorts fins '
      'goggles" -> create_list_v1\n'
      'User: "Remember my favourite meals dal chawal palak paneer" -> '
      'save_preference_v1\n'
      'User: "What\'s on my swimming checklist?" -> recall_stored_info_v1\n'
      'User: "What are my favourite desserts?" -> recall_stored_info_v1\n'
      'User: "My swimming checklist is goggles cap fins" -> create_list_v1\n'
      'User: "Remember my parking spot is level 3" -> remember_topic_v1\n'
      'User: "Where did I park?" -> recall_topic_v1\n'
      'User: "What is my hotel?" -> recall_topic_v1\n'
      'User: "Remind me to call dad when I reach the office" -> '
      'create_conditional_reminder_v1\n'
      'User: "I am going to the store" -> unknown\n'
      'User: "I am going for a swim" -> unknown\n'
      'User: "I am going for swimming" -> unknown\n'
      'User: "Where did I leave my wallet?" -> query_item_location_v1\n'
      'User: "Remember where I put my keys" -> log_item_location_v1\n'
      'User: "What was I doing?" -> query_recent_activity_v1\n'
      'User: "What\'s next?" -> query_next_briefing_v1\n'
      'User: "How much time do I have before my dentist appointment?" -> '
      'query_time_remaining_v1\n'
      'User: "What\'s the weather like tomorrow?" -> unknown\n';

  // ---------------------------------------------------------------------------
  // Stage 2: Parameter extraction (~150-250 tokens, varies by feature)
  // ---------------------------------------------------------------------------

  static final Map<String, String> _stage2PromptCache = {};

  static String parameterExtractionPrompt(
    String featureId,
    Map<String, dynamic> schema,
  ) {
    final cached = _stage2PromptCache[featureId];
    if (cached != null) return cached;

    final schemaStr = jsonEncode(schema);
    final extraRules = StringBuffer();

    if (schema.containsKey('time')) {
      extraRules.write('''

--- TIME FIELD ---
"time" MUST be an object with EXACTLY these 5 keys: type, clock_time, date, amount, unit.
- ABSOLUTE ("at 5pm", "at 6:30am"): {"type":"absolute","clock_time":"HH:MM in 24h","date":"today"|"tomorrow"|weekday|null,"amount":null,"unit":null}
- RELATIVE ("after 30 minutes", "in 2 hours"): {"type":"relative","clock_time":null,"date":null,"amount":<number>,"unit":"seconds"|"minutes"|"hours"}
- UNKNOWN (no time info like "remind me later"): {"type":"unknown","clock_time":null,"date":null,"amount":null,"unit":null}
- NEVER output the string "null" — use JSON null.
- NEVER output an ISO timestamp string.
- NEVER combine clock_time with amount/unit. If clock_time is set, amount/unit MUST be null. If amount/unit are set, clock_time MUST be null.
Examples:
"tomorrow at 5pm" -> {"type":"absolute","clock_time":"17:00","date":"tomorrow","amount":null,"unit":null}
"after 30 minutes" -> {"type":"relative","clock_time":null,"date":null,"amount":30,"unit":"minutes"}
"later" / no time -> {"type":"unknown","clock_time":null,"date":null,"amount":null,"unit":null}''');
      if (featureId == 'create_conditional_reminder_v1') {
        extraRules.write('\nlocation trigger->time=null.');
      }
    }

    if (schema.containsKey('recurring') || schema.containsKey('days')) {
      extraRules.write('''

--- RECURRING ---
If recurring=true or days is present, "date" MUST be null.''');
    }

    if (schema.containsKey('items') &&
        (featureId == 'create_list_v1' || featureId == 'save_preference_v1')) {
      extraRules.write('''

--- ITEM LIST ---
list_name is the TOPIC ONLY (1-2 words like "swimming", "packing", "favourite meals"). The word "checklist"/"list" is structural — NEVER include it in list_name or items.
Items are everything AFTER the topic and list-word. Split by context boundaries.
Include EVERY item the user said, even unfamiliar or odd words — NEVER drop, dedupe, or autocorrect.
Examples:
"create a swimming checklist costume goggles fins" -> list_name="swimming", items=["costume","goggles","fins"]
"make a checklist for swimming glasses swimming shorts fins goggles" -> list_name="swimming", items=["swimming glasses","swimming shorts","fins","goggles"]
"create a packing list socks shoes charger" -> list_name="packing", items=["socks","shoes","charger"]
"dal chawal palak paneer chicken 65" -> items=["dal chawal","palak paneer","chicken 65"]''');
    }

    if (schema.containsKey('meeting_name')) {
      extraRules.write('''

--- MEETING NAME ---
Only extract if the user explicitly says one.
"I'm going into a meeting" -> null
"...meeting with the design team" -> "design team"
Never use the whole transcript as the name.''');
    }

    if (schema.containsKey('topic')) {
      extraRules.write('''

--- TOPIC / CONTENT ---
Natural phrases with spaces: "parking spot", not "parking_spot"/"parkingSpot".
Strip possessives: "my keys" -> "keys".
NEVER use the full transcript as topic. Split "remember my X is Y" -> topic=X, content=Y.
Examples:
"Remember my parking spot is level 3" -> {"topic":"parking spot","content":"level 3"}
"Remember my gate code is 4471" -> {"topic":"gate code","content":"4471"}
"Where did I park?" -> {"topic":"parking spot"}''');
    }

    if (schema.containsKey('event_hint')) {
      extraRules.write('''

--- EVENT HINT ---
Natural phrases with spaces: "dentist appointment", not "dentist_appointment".''');
    }

    if (schema.containsKey('duration_seconds')) {
      extraRules.write('''

--- DURATION ---
Convert to seconds: minutes*60, hours*3600. (25 minutes = 1500)''');
    }

    if (schema.containsKey('item') &&
        (featureId == 'log_item_location_v1' ||
            featureId == 'query_item_location_v1')) {
      extraRules.write('''

--- ITEM ---
Strip possessives ("my wallet" -> "wallet"). Use null for pronouns ("this", "that", "it").
NEVER use the full transcript as item. Extract only the noun.
Examples:
"Remember where I put my keys" -> {"item":"keys"}
"Remember where I put this" -> {"item":null}
"Where did I leave my wallet?" -> {"item":"wallet"}''');
    }

    if (schema.containsKey('trigger_type')) {
      extraRules.write('''

--- TRIGGER_TYPE ---
"when it's <time>" / "when the clock hits X" -> trigger_type="time", fill "time", location=null.
"when I get to <place>" / "when I arrive at X" -> trigger_type="location", fill "location", time=null.
Examples:
"Remind me to take the chicken out when it's 6pm" -> {"task":"take the chicken out","trigger_type":"time","time":{"type":"absolute","clock_time":"18:00","date":null,"amount":null,"unit":null},"location":null}
"Remind me to buy milk when I get to the grocery store" -> {"task":"buy milk","trigger_type":"location","time":null,"location":"grocery store"}''');
    }

    if (schema.containsKey('action') && featureId == 'control_focus_timer_v1') {
      extraRules.write('''

--- FOCUS TIMER ACTION ---
"start ... focus timer" / "N minute focus timer" -> action="start" with duration_seconds if a duration is present.
"stop the timer" / "stop focus timer" / "end the timer" -> action="stop", duration_seconds=null.
Examples:
"Start a 25 minute focus timer" -> {"action":"start","duration_seconds":1500}
"Stop the timer" -> {"action":"stop","duration_seconds":null}''');
    }

    if (schema.containsKey('query_type') && schema.containsKey('reference')) {
      extraRules.write('''

--- RECALL QUERY ---
"what's on my X checklist" -> query_type="list", reference=X (list_name).
"what are my favourite Y" / "what are my Y" -> query_type="preference", reference=<the category>.
Reference is the natural-language topic/name, no possessive.
Examples:
"What's on my swimming checklist?" -> {"query_type":"list","reference":"swimming"}
"What are my favourite desserts?" -> {"query_type":"preference","reference":"favourite desserts"}''');
    }

    if (schema.containsKey('query') ||
        schema.containsKey('place_hint') ||
        schema.containsKey('target')) {
      extraRules.write('\nCopy the user\'s wording; null if not stated.');
    }

    final prompt = 'Extract parameters for feature: $featureId\n'
        'Schema: $schemaStr\n'
        'Output ONLY a JSON object with the parameters.\n'
        'Unknown values = null. Preserve types (strings, numbers, booleans, arrays, objects).'
        '$extraRules';
    _stage2PromptCache[featureId] = prompt;
    return prompt;
  }

  // ---------------------------------------------------------------------------
  // Legacy single-shot prompt (kept as rawChat default, no longer in hot path)
  // ---------------------------------------------------------------------------

  static String _renderCatalog() {
    final buffer = StringBuffer();
    final entries = AiManifests.features.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final id = entries[i].key;
      final meta = entries[i].value;
      final schemaStr = jsonEncode(meta.schema);
      buffer.write('- "$id": ${meta.description}\n  schema: $schemaStr');
      if (i != entries.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static final String featureCatalog = _renderCatalog();

  static final String systemPrompt =
      'You are an on-device intent classifier. Respond with JSON only.';

  // ---------------------------------------------------------------------------
  // Standalone prompts for grounded-answer and meeting-summary calls
  // ---------------------------------------------------------------------------

  static const String groundedAnswerPrompt = '''
You are a strict retrieval-grounded answering engine for smart glasses.

You will be given a JSON object with two fields: "question" (what the user
asked) and "stored_data" (the ONLY facts you are allowed to use to answer).

Rules:
- Answer using ONLY the facts in "stored_data". Never add, infer, guess, or
  complete any item, name, or detail that is not explicitly present in it.
- If "stored_data" is null, an empty list, or otherwise does not answer the
  question, respond with EXACTLY this text and nothing else: "I don't have that saved."
- Otherwise, respond with ONE short, natural spoken sentence that states the
  stored items or facts. No bullet points, no markdown, no lists with dashes.
- Never mention JSON, "the data", "storage", "stored_data", or how you
  retrieved this information -- speak as if you simply remember it.
- Do not add any items, caveats, or suggestions beyond what is in stored_data.
''';

  static const String glassesReplyPolishPrompt = '''
You rewrite assistant replies for a voice interface on smart glasses.

You will be given a JSON object with two fields: "user_said" (what the user
asked for) and "reply" (a correct but robotic draft reply).

Rules:
- Rewrite "reply" as ONE short, natural spoken sentence.
- Keep every fact in the draft (task names, times, item counts, list names)
  exactly as given. Never change a time or a number.
- Never add new information, questions, offers, or caveats.
- No emoji, no markdown, no quotes around the sentence.
- If the draft is already natural, return it unchanged.
- Output only the sentence.
''';

  static const String meetingSummaryPrompt = '''
You are a strict, grounded meeting-summarization engine for smart glasses.

You will be given a JSON object with two fields: "meeting_name" (may be null)
and "transcript_lines" (a list of strings -- everything captured during the
meeting, in order).

Rules:
- Summarize ONLY what is actually present in "transcript_lines". Never invent
  attendees, decisions, action items, or details that were not said.
- If "transcript_lines" is an empty list or null, respond with EXACTLY:
  "No meeting text was recorded, so there's nothing to summarize."
- Otherwise produce a short summary as plain spoken prose (2-5 sentences,
  no markdown, no bullet points): what was discussed, any decisions reached,
  and any action items mentioned -- only include a category if the transcript
  actually contains something for it.
- Do not pad the summary with generic meeting-summary boilerplate ("the team
  had a productive discussion") that isn't grounded in the actual lines.
- Never mention JSON, "the transcript", "transcript_lines", or how you
  received this information -- speak as if you simply attended the meeting.
''';
}
