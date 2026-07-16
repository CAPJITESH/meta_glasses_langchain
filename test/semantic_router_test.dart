// Verifies the semantic-router asset pairing: the shipped exemplar bank
// (semantic_exemplars.json) and the shipped precomputed vector cache
// (semantic_exemplars.vectors.json) must hash-match, or the router is
// permanently inert for the session (see SemanticRouter.warmUp doc comment).
// This is the one part of the semantic-router port with real correctness
// risk that dart analyze can't catch — a canonical-JSON serialization bug
// would silently leave the router inert without throwing anywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:qualcom_hacks/core/utils/semantic_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SemanticRouter loads the exemplar vector asset and verifies its hash', () async {
    await SemanticRouter.instance.warmUp();
    expect(
      SemanticRouter.instance.hasLoadedExemplars,
      isTrue,
      reason: 'Either the assets are missing from pubspec.yaml, or the '
          'canonical-JSON hash computed in Dart does not match the '
          '_source_hash shipped in semantic_exemplars.vectors.json.',
    );
  });

  test('match() degrades to null while AiService.embed() is unimplemented', () async {
    final result = await SemanticRouter.instance.match('remind me to call mom tomorrow at 5pm');
    expect(result, isNull);
  });
}
