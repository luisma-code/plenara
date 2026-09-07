import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/undo_feedback.dart';

void main() {
  testWidgets('an undoable change notification dismisses itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUndoableResult(
                context,
                message: 'Person added',
                onUndo: () async => 'Person removed again',
              ),
              child: const Text('Make change'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Make change'));
    await tester.pumpAndSettle();
    expect(find.text('Person added'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(
      find.text('Person added'),
      findsOneWidget,
      reason: 'Undo should remain available during the readable interval',
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.text('Person added'),
      findsNothing,
      reason: 'change notifications must not remain indefinitely',
    );
  });
}
