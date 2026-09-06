import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/content_search.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/reply_view.dart';

void main() {
  testWidgets('search content stays visible in a ranked tappable card', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: searchResultsView(
            "Found it — Journal entry from July 6, 2026. It's on screen.",
            const [
              ContentSearchResult(
                recordId: 'journal-1',
                typeId: 'journal_entry',
                title: 'Journal entry',
                dateLabel: 'July 6, 2026',
                content: 'The private cabin trip note.',
              ),
            ],
            tuning: const PresenceTuning(),
            onOpen: (id) => opened = id,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('search-results-card')), findsOneWidget);
    expect(find.text('The private cabin trip note.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-result-journal-1')));
    expect(opened, 'journal-1');
  });
}
