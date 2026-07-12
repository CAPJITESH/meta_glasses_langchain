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
  // Stage 1: Intent classification (~150 tokens)
  // ---------------------------------------------------------------------------

  static final String _intentIds =
      AiManifests.features.keys.join(', ');

  static final String intentClassificationPrompt =
      'Classify intent. Reply with ONLY the id, or "unknown".\n$_intentIds';

  // ---------------------------------------------------------------------------
  // Stage 2: Parameter extraction (~150-250 tokens, varies by feature)
  // ---------------------------------------------------------------------------

  static String parameterExtractionPrompt(
    String featureId,
    Map<String, dynamic> schema,
  ) {
    final schemaStr = jsonEncode(schema);
    final hasTime = schema.containsKey('time');

    final buf = StringBuffer();
    buf.writeln('Extract as JSON. All keys required, null if unknown.');
    buf.writeln(schemaStr);

    if (hasTime) {
      buf.writeln(
        'time={type:absolute|relative|unknown,clock_time:HH:MM 24h,date:yyyy-MM-dd,amount:num,unit:s/m/h} null if N/A',
      );
      buf.writeln(
        'today/tomorrow→yyyy-MM-dd via Current date. Relative→amount+unit only. 24h: 5pm→17:00.',
      );
      if (featureId == 'create_conditional_reminder_v1') {
        buf.write('location trigger→time=null. ');
      }
    }

    if (schema.containsKey('item')) buf.writeln('"my X"→"X".');
    if (schema.containsKey('duration_seconds')) buf.writeln('Duration in seconds.');
    if (schema.containsKey('days')) buf.writeln('Days capitalized.');

    buf.write('JSON only.');
    return buf.toString();
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
