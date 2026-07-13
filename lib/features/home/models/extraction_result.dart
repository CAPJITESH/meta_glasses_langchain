/// lib/features/home/models/extraction_result.dart
library;

class HomeExtractionView {
  final String transcript;
  final String intent;
  final Map<String, dynamic> parameters;
  final double confidence;
  final String raw;
  final String? humanTime;
  final String glassesMessage;

  /// True when the confidence gate routed this turn to the server fallback
  /// instead of the local answer (Section 4). [glassesMessage] then holds the
  /// server (currently stub) response.
  final bool usedServerFallback;

  const HomeExtractionView({
    required this.transcript,
    required this.intent,
    required this.parameters,
    required this.confidence,
    required this.raw,
    required this.humanTime,
    required this.glassesMessage,
    this.usedServerFallback = false,
  });
}
