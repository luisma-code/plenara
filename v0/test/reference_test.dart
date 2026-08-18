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

  test('a canonical key that normalizes to nothing cannot crash tier-2 resolve',
      () async {
    // Regression: '!!!' normalizes to '' and so never lands in the alias map,
    // but it DID land in the tier-2 key list — resolving to it then hit a
    // null-assert (`_byKey[normalize(best)]!`) and threw.
    final store = ReferenceStore.fromEntries('weird', [
      {'key': '!!!', 'kcal': 1},
      {'key': 'banana', 'kcal': 105},
    ]);
    Future<List<double>?> fake(String t) async =>
        [t.contains('banana') ? 0.0 : 1.0, 0.0];
    final entry = await store.resolve('mystery', embedder: fake, theta: 0.5);
    expect(entry, isNull,
        reason: 'the unresolvable key is skipped deterministically — an '
            'honest miss, never a throw');
  });

  test(
      'canonical keys that collide after normalization resolve to ONE entry, '
      'first wins', () async {
    // Regression: the second colliding entry overwrote the alias map while
    // both keys stayed in the tier-2 list, so a fuzzy match on the first key
    // returned the second entry's data under the first entry's name.
    final store = ReferenceStore.fromEntries('collide', [
      {'key': 'The Banana', 'kcal': 100},
      {'key': 'banana!', 'kcal': 200}, // both normalize to 'banana'
    ]);
    expect(store.lookup('banana')!.kcal, 100,
        reason: 'first entry wins the normalized slot, deterministically');
    expect(store.size, 1,
        reason: 'the colliding later entry is skipped, not half-registered');
    final fuzzy = await store.resolve('banana-ish',
        embedder: (t) async => [1.0], theta: 0.1);
    expect(fuzzy!.kcal, 100,
        reason: 'tier-2 can never pair one entry\'s key with another\'s data');
  });

  test('a missing dataset file yields an empty store, not a crash', () {
    final empty = ReferenceStore.load('/nonexistent-dir', 'nutrition');
    expect(empty.isEmpty, isTrue);
    expect(empty.lookup('banana'), isNull);
  });
}
