/// Content search (F-12) — semantic when an embedder is available, keyword fallback otherwise.
import 'package:plenara/content_search.dart';
import 'package:test/test.dart';

void main() {
  final recs = <Map<String, dynamic>>[
    {'id': '1', 'typeId': 'journal_entry', 'entry': 'The cabin trip to Tahoe was amazing — so peaceful by the lake'},
    {'id': '2', 'typeId': 'journal_entry', 'entry': 'Grocery run and laundry today'},
    {'id': '3', 'typeId': 'contact_fact', 'fact': 'Sarah loves hiking'},
    {'id': '4', 'typeId': 'workout', 'activity': 'run'}, // not searchable
  ];

  test('contentOf extracts the free-text field per type, null for others', () {
    expect(ContentSearchIndex.contentOf(recs[0]), contains('cabin'));
    expect(ContentSearchIndex.contentOf(recs[2]), 'Sarah loves hiking');
    expect(ContentSearchIndex.contentOf(recs[3]), isNull); // workout has no searchable text
  });

  test('keywordSearch ranks by term hits and ignores stopwords + non-searchable records', () {
    expect(ContentSearchIndex.keywordSearch('the cabin trip lake', recs).first, '1');
    expect(ContentSearchIndex.keywordSearch('quantum physics', recs), isEmpty);
    // "the" alone is a stopword -> no meaningful terms -> empty (doesn't match everything)
    expect(ContentSearchIndex.keywordSearch('the', recs), isEmpty);
  });

  test('semantic search ranks by cosine with an injected embedder', () async {
    Future<List<double>?> fake(String t) async {
      final l = t.toLowerCase();
      return [
        (l.contains('cabin') || l.contains('lake') || l.contains('tahoe')) ? 1.0 : 0.0,
        (l.contains('grocery') || l.contains('laundry')) ? 1.0 : 0.0,
      ];
    }

    final idx = ContentSearchIndex(embedder: fake);
    await idx.build(recs);
    final r = await idx.search('a lakeside cabin getaway');
    expect(r, isNotNull);
    expect(r!.first, '1');
  });

  test('a down embed server -> search returns null (caller keyword-falls-back), never throws', () async {
    final down = ContentSearchIndex(embedder: (t) async => null);
    await down.build(recs);
    expect(down.isEmpty, isTrue);
    expect(await down.search('anything'), isNull);
  });

  // A two-axis embedder keyed on distinctive words, so ranking is deterministic.
  Future<List<double>?> cabinKayak(String t) async {
    final l = t.toLowerCase();
    return [l.contains('cabin') ? 1.0 : 0.0, l.contains('kayak') ? 1.0 : 0.0];
  }

  test('an EDITED record re-embeds on rebuild — search follows the new wording', () async {
    var embeds = 0;
    final idx = ContentSearchIndex(embedder: (t) {
      embeds++;
      return cabinKayak(t);
    });
    final rec = {'id': 'e1', 'typeId': 'journal_entry', 'entry': 'the cabin weekend'};
    await idx.build([rec]);
    expect((await idx.search('cabin'))!, contains('e1'));
    final builds = embeds;
    await idx.build([rec]); // unchanged -> no re-embed (still cheap per build)
    expect(embeds, builds, reason: 'an unchanged record must not re-embed');
    rec['entry'] = 'the kayak trip'; // the user edits the journal entry
    await idx.build([rec]);
    // The old build() was idempotent per ID, so the record kept its original
    // vector forever and its edits were unsearchable.
    expect((await idx.search('kayak'))!, contains('e1'),
        reason: 'found under the NEW wording');
    expect((await idx.search('cabin'))!, isNot(contains('e1')),
        reason: 'the stale vector is gone');
  });

  test('a DELETED record is evicted on a full rebuild; incremental builds keep it', () async {
    final idx = ContentSearchIndex(embedder: cabinKayak);
    final a = {'id': 'a', 'typeId': 'journal_entry', 'entry': 'cabin weekend'};
    final b = {'id': 'b', 'typeId': 'journal_entry', 'entry': 'kayak trip'};
    await idx.build([a, b]);
    expect((await idx.search('cabin'))!, contains('a'));
    // An incremental build over a SUBSET must not evict (callers index new
    // records without passing the whole store).
    await idx.build([b]);
    expect((await idx.search('cabin'))!, contains('a'));
    // A full rebuild declares [b] the complete store: 'a' was deleted, and its
    // vector must go with it — a dead id must never surface as a search hit.
    await idx.build([b], full: true);
    expect((await idx.search('cabin'))!, isNot(contains('a')));
    expect((await idx.search('kayak'))!, contains('b'));
  });
}
