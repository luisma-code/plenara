/// The routine player's UI (Spec 16). The card is deliberately dumb — it renders a value object —
/// so these tests pin the things that would actually break a workout: a step with no illustration
/// must still be fully usable, and the touch controls must exist because your hands are busy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/routine_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _timed = RoutineStepView(
  routineTitle: 'Low-back loosener',
  name: 'Cat-cow',
  instruction: 'On all fours, round your back up as you exhale, then let it dip as you inhale.',
  position: 2,
  total: 7,
  side: 'both',
  durationSeconds: 45,
);

void main() {
  testWidgets('a timed step shows where you are, what to do, and how long', (tester) async {
    await tester.pumpWidget(_wrap(RoutineStepCard(step: _timed, onNext: () {}, onStop: () {})));
    expect(find.text('STEP 2 OF 7 · LOW-BACK LOOSENER'), findsOneWidget);
    expect(find.text('Cat-cow'), findsOneWidget);
    expect(find.textContaining('round your back up'), findsOneWidget);
    expect(find.text('45s'), findsOneWidget);
  });

  testWidgets('a step with NO illustration is still complete — the words carry it', (tester) async {
    // ~2/3 of the catalogue has no picture, and a screen-off run has none by definition. A
    // pictureless step must never look broken or lose information.
    await tester.pumpWidget(_wrap(RoutineStepCard(step: _timed, onNext: () {}, onStop: () {})));
    expect(find.byType(Image), findsNothing);
    expect(find.text('Cat-cow'), findsOneWidget);
    expect(find.textContaining('round your back up'), findsOneWidget);
    expect(find.byKey(const Key('routine-next')), findsOneWidget);
  });

  testWidgets('a rep step shows reps and NO progress bar (it waits for you)', (tester) async {
    const reps = RoutineStepView(
      routineTitle: 'Chest day', name: 'Push-ups',
      instruction: 'Hands under your shoulders, lower under control, press back up.',
      position: 1, total: 4, side: 'both', reps: 12,
    );
    await tester.pumpWidget(_wrap(RoutineStepCard(step: reps, onNext: () {}, onStop: () {})));
    expect(find.text('12 reps'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'only the user knows when reps are done — never auto-advance them');
  });

  testWidgets('a timed step shows progress when the cadence is running', (tester) async {
    await tester.pumpWidget(_wrap(
        RoutineStepCard(step: _timed, progress: 0.4, onNext: () {}, onStop: () {})));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a one-sided step says which side, in the text you can HEAR', (tester) async {
    const left = RoutineStepView(
      routineTitle: 'Low-back loosener', name: 'Hip flexor stretch',
      instruction: 'Sink your hips forward and down.',
      position: 3, total: 7, side: 'left', durationSeconds: 30,
    );
    await tester.pumpWidget(_wrap(RoutineStepCard(step: left, onNext: () {}, onStop: () {})));
    expect(find.textContaining('(left side)'), findsOneWidget);
  });

  testWidgets('Next and Stop are real touch targets — hands are busy, voice may not be heard',
      (tester) async {
    var next = 0, stop = 0;
    await tester.pumpWidget(_wrap(
        RoutineStepCard(step: _timed, onNext: () => next++, onStop: () => stop++)));
    await tester.tap(find.byKey(const Key('routine-next')));
    await tester.tap(find.byKey(const Key('routine-stop')));
    expect(next, 1);
    expect(stop, 1);
  });

  testWidgets('a long duration reads as m:ss, not raw seconds', (tester) async {
    const long = RoutineStepView(
      routineTitle: 'X', name: 'Plank', instruction: 'Hold a straight line from head to heels.',
      position: 1, total: 2, side: 'both', durationSeconds: 90,
    );
    await tester.pumpWidget(_wrap(RoutineStepCard(step: long, onNext: () {}, onStop: () {})));
    expect(find.text('1:30'), findsOneWidget);
  });
}
