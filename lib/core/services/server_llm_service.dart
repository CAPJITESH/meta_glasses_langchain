/// lib/core/services/server_llm_service.dart
///
/// Confidence-based fallback target (Section 4). When on-device extraction is
/// not confident enough (see [ServerLlmGate]), the request is routed here
/// instead of to the local answer. Today this returns a fixed placeholder so
/// the whole fallback path can be built and tested before a real backend
/// exists; when a backend is ready, only [StubServerLlmService] is replaced —
/// nothing about how it is invoked changes.
library;

/// A request handed to the server fallback. Deliberately minimal: per the
/// privacy framing (Section 3), the fallback should carry the *minimum
/// necessary context*, not raw transcripts where avoidable. For now callers
/// pass the transcript because there is no real backend to be careful for;
/// tighten this to a redacted summary when wiring a live model.
class ServerLlmRequest {
  final String transcript;

  /// The local intent guess, if any — lets a future backend skip re-classifying.
  final String? localIntent;

  /// The local confidence that triggered the fallback (for telemetry/tuning).
  final double localConfidence;

  const ServerLlmRequest({
    required this.transcript,
    this.localIntent,
    required this.localConfidence,
  });
}

class ServerLlmResponse {
  final String text;

  /// True when this came from the stub, not a real model — lets the UI label
  /// it while the backend does not exist yet.
  final bool isPlaceholder;

  const ServerLlmResponse({required this.text, this.isPlaceholder = false});
}

abstract class ServerLlmService {
  Future<ServerLlmResponse> respond(ServerLlmRequest request);
}

/// Fixed-response stand-in. No network call — lets the fallback path be
/// exercised end-to-end with no backend. Swap this out (real HTTP client,
/// hosted model, etc.) without changing any call site.
class StubServerLlmService implements ServerLlmService {
  const StubServerLlmService();

  static const String placeholder = 'Server LLM coming soon.';

  @override
  Future<ServerLlmResponse> respond(ServerLlmRequest request) async {
    return const ServerLlmResponse(text: placeholder, isPlaceholder: true);
  }
}

/// The gate itself. Kept separate from the service so the threshold and the
/// backend can evolve independently.
///
/// IMPORTANT: [ExtractionResult.confidence] is a *completeness* signal (schema
/// fill-rate), not a *correctness* signal — it reads fully confident whenever
/// every field happens to be filled, even with a wrong value. So this
/// threshold is a placeholder to be tuned empirically against real transcripts
/// once a real backend exists to compare against; do not treat the default as
/// meaningful.
class ServerLlmGate {
  final ServerLlmService service;
  final double threshold;

  const ServerLlmGate({
    this.service = const StubServerLlmService(),
    this.threshold = 0.6,
  });

  bool shouldFallback(double confidence) => confidence < threshold;
}
