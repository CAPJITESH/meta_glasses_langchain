/// lib/core/utils/semantic_router.dart
///
/// Stage 0c of the extraction pipeline — embedding-based intent match
/// against curated exemplars (verbatim port of `SemanticRouter` from
/// semantic_router.py), with no LLM call. Resolves intent ONLY; parameters
/// are always empty, so a match here should trigger a Stage-2-only
/// extraction (see [AiService.extractParamsOnly]).
///
/// IMPORTANT — this router is INERT until [AiService.embed] has a real
/// on-device embedding backend behind it (see the fllama_embed native patch
/// tracked separately). [match] degrades to `null` (fall through to the LLM
/// path) whenever embedding is unavailable or fails, by design — a broken or
/// missing embedder must never break the pipeline, only skip an
/// optimization.
///
/// The exemplar vectors are shipped as a precomputed asset
/// (`assets/semantic_router/semantic_exemplars.vectors.json`), NOT
/// regenerated on-device: unlike the Python original, this port does not
/// re-embed the exemplar bank at runtime on a cache-invalidation miss — a
/// hash mismatch between the shipped exemplar bank and the shipped vector
/// cache is treated as a build-time asset error (the router stays inert for
/// the session), never as a trigger to embed 93 exemplars on a phone.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/ai_service.dart';

class _ExemplarEntry {
  final String intent;
  final List<double> vector;
  const _ExemplarEntry({required this.intent, required this.vector});
}

class SemanticRouter {
  SemanticRouter._internal();
  static final SemanticRouter instance = SemanticRouter._internal();

  /// Cosine similarity floor for a match.
  static const double threshold = 0.75;

  /// Required gap between the best and second-best intent score, so
  /// near-tied intents (the "remember/create/log" cluster the exemplar
  /// bank's own `_disambiguation_notes` warns about) fall through to the LLM
  /// instead of guessing.
  static const double margin = 0.08;

  static const String _exemplarAssetPath =
      'assets/semantic_router/semantic_exemplars.json';
  static const String _vectorAssetPath =
      'assets/semantic_router/semantic_exemplars.vectors.json';

  List<_ExemplarEntry>? _entries;
  bool _warmedUp = false;

  /// True once [warmUp] has successfully loaded the exemplar vector asset
  /// AND verified its SHA-256 hash against the shipped exemplar bank. Exists
  /// purely so tests can assert the asset pairing is intact without
  /// exposing the vectors themselves.
  @visibleForTesting
  bool get hasLoadedExemplars => (_entries?.isNotEmpty) ?? false;

  /// Loads the exemplar bank + precomputed vector asset and verifies the
  /// shipped SHA-256 hash still matches the shipped exemplar bank. Never
  /// throws — any failure (missing asset, hash mismatch, malformed JSON)
  /// leaves the router inert ([match] always returns null) rather than
  /// blocking pipeline startup.
  Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;
    try {
      final exemplarRaw = await rootBundle.loadString(_exemplarAssetPath);
      final vectorRaw = await rootBundle.loadString(_vectorAssetPath);

      final exemplarJson = jsonDecode(exemplarRaw) as Map<String, dynamic>;
      final vectorJson = jsonDecode(vectorRaw) as Map<String, dynamic>;

      // Metadata keys prefixed with '_' (e.g. "_disambiguation_notes") are
      // ignored, matching Python's exemplar-bank filter.
      final bank = <String, List<String>>{
        for (final entry in exemplarJson.entries)
          if (!entry.key.startsWith('_'))
            entry.key: (entry.value as List).cast<String>(),
      };

      final expectedHash = _sha256Hex(_canonicalBankJson(bank));
      final storedHash = vectorJson['_source_hash'] as String?;
      if (storedHash == null || storedHash != expectedHash) {
        // Shipped vector cache doesn't match the shipped exemplar bank.
        // Treat as a build-time packaging error, not a signal to re-embed
        // the bank on-device.
        _entries = null;
        return;
      }

      final rawEntries = vectorJson['entries'] as List;
      _entries = [
        for (final e in rawEntries)
          _ExemplarEntry(
            intent: e['intent'] as String,
            vector: (e['vector'] as List).map((v) => (v as num).toDouble()).toList(),
          ),
      ];
    } catch (_) {
      _entries = null;
    }
  }

  /// Embeds [transcript] and matches it against the cached exemplar
  /// vectors. Returns an [ExtractionResult] with intent only (empty
  /// parameters) when a confident match is found, else `null` — the caller
  /// should fall through to the deterministic router / LLM path.
  Future<ExtractionResult?> match(String transcript) async {
    if (!_warmedUp) await warmUp();
    final entries = _entries;
    if (entries == null || entries.isEmpty) return null;

    List<double> queryVector;
    try {
      queryVector = await AiService.instance.embed(transcript);
    } catch (_) {
      // No (working) on-device embedding backend yet — inert, not broken.
      return null;
    }

    final bestPerIntent = <String, double>{};
    for (final entry in entries) {
      final score = _cosine(queryVector, entry.vector);
      final prev = bestPerIntent[entry.intent];
      if (prev == null || score > prev) bestPerIntent[entry.intent] = score;
    }
    if (bestPerIntent.isEmpty) return null;

    final ranked = bestPerIntent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bestIntent = ranked.first.key;
    final bestScore = ranked.first.value;
    final secondScore = ranked.length > 1 ? ranked[1].value : -1.0;

    if (bestScore >= threshold && (bestScore - secondScore) >= margin) {
      return ExtractionResult(
        intent: bestIntent,
        parameters: const {},
        confidence: 0.7 + 0.3 * bestScore,
        raw: 'semantic:$bestIntent:${bestScore.toStringAsFixed(2)}',
      );
    }
    return null;
  }

  static double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Reconstructs Python's `json.dumps(bank, sort_keys=True)` byte-for-byte
  /// for this data's exact shape (a flat `Dict[str, List[str]]`, ASCII-only
  /// content) so the SHA-256 hash comparison lines up with the hash computed
  /// on the Python side when the exemplar bank was built. Not a general JSON
  /// canonicalizer — relies on that shape holding.
  static String _canonicalBankJson(Map<String, List<String>> bank) {
    final keys = bank.keys.toList()..sort();
    final parts = keys.map((k) {
      final items = bank[k]!.map(jsonEncode).join(', ');
      return '${jsonEncode(k)}: [$items]';
    }).join(', ');
    return '{$parts}';
  }

  static String _sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();
}
