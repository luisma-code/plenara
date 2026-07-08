/// Reference knowledge bases (Spec 13) — tiered food resolution + provenance.
import 'package:plenara/reference.dart';
import 'package:test/test.dart';

void main() {
  final store = ReferenceStore.fromEntries('nutrition', [
    {'key': 'banana', 'aliases': ['bananas'], 'kcal': 105, 'serving': '1 medium', 'category': 'fruit'},
    {'key': 'mac and cheese', 'aliases': ['mac n cheese'], 'kcal': 390, 'category': 'dish'},
  ]);

  test('tier-1: exact, alias, and article/punctuation normalization', () {
    expect(store.lookup('banana')!.kcal, 105);
    expect(store.lookup('a Banana!')!.kcal, 105); // normalized: article + punctuation stripped
    expect(store.lookup('bananas')!.kcal, 105); // alias
    expect(store.lookup('mac n cheese')!.kcal, 390); // alias
    expect(store.lookup('banana')!.provenance, 'reference');
  });

  test('a miss returns null — honest, never a guessed number', () {
    expect(store.lookup('unobtainium souffle'), isNull);
  });

  test('tier-2: embedding nearest-neighbor resolves a near-miss with fuzzy provenance', () async {
    Future<List<double>?> fake(String t) async {
      final l = t.toLowerCase();
      return [
        l.contains('banana') ? 1.0 : 0.0,
        (l.contains('mac') || l.contains('cheese')) ? 1.0 : 0.0,
      ];
    }

    final e = await store.resolve('mac cheese', embedder: fake, theta: 0.5); // tier-1 misses this phrasing
    expect(e, isNotNull);
    expect(e!.key, 'mac and cheese');
    expect(e.provenance, 'reference~'); // '~' marks a fuzzy match
  });

  test('tier-2 unavailable (embed server down) -> null, never a throw', () async {
    expect(await store.resolve('mystery food', embedder: (t) async => null), isNull);
  });

  test('a missing dataset file yields an empty store, not a crash', () {
    final empty = ReferenceStore.load('/nonexistent-dir', 'nutrition');
    expect(empty.isEmpty, isTrue);
    expect(empty.lookup('banana'), isNull);
  });
}
