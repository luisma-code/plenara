import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/motion.dart';

void main() {
  testWidgets('planner objects remain visible through create and complete', (
    tester,
  ) async {
    final items = ValueNotifier<List<String>>(['one']);
    addTearDown(items.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<String>>(
          valueListenable: items,
          builder: (context, values, _) => ContinuityColumn<String>(
            items: values,
            keyOf: (item) => item,
            itemBuilder: (_, item) =>
                SizedBox(height: 48, child: Text(item, key: Key('item-$item'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    items.value = ['one', 'two'];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byKey(const Key('item-one')), findsOneWidget);
    expect(find.byKey(const Key('item-two')), findsOneWidget);

    items.value = ['two'];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      find.byKey(const Key('item-one')),
      findsOneWidget,
      reason: 'the completed object should have a visible terminal transition',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-one')), findsNothing);
    expect(find.byKey(const Key('item-two')), findsOneWidget);
  });

  testWidgets('Reduce Motion uses opacity without an explicit size tween', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ContinuityColumn<String>(
            items: ['one'],
            keyOf: _identity,
            itemBuilder: _textItem,
          ),
        ),
      ),
    );
    final scope = find.byType(ContinuityColumn<String>);
    expect(
      find.descendant(of: scope, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scope, matching: find.byType(SizeTransition)),
      findsNothing,
    );
  });
}

String _identity(String value) => value;
Widget _textItem(BuildContext context, String value) => Text(value);
