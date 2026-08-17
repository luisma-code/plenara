// Dev verifier, intentionally not named *_test.dart. Capture the real planner
// object transition at 11 frozen positions:
//   flutter test test/motion_strip.dart --dart-define=MOTION_OUT=/tmp/strip
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/motion.dart';
import 'package:plenara_app/plenara_theme.dart';

const _out = String.fromEnvironment('MOTION_OUT');
const _broken = bool.fromEnvironment('MOTION_BROKEN');

void main() {
  testWidgets('capture create continuity across its full range', (
    tester,
  ) async {
    if (_out.isEmpty) fail('MOTION_OUT is required');
    final boundary = GlobalKey();
    final items = ValueNotifier<List<String>>(['Call Mom']);
    addTearDown(items.dispose);
    await tester.binding.setSurfaceSize(const Size(420, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: PlenaraTheme.dark,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ValueListenableBuilder<List<String>>(
                valueListenable: items,
                builder: (context, values, _) => Card(
                  child: _broken
                      ? Column(children: values.map(_row).toList())
                      : ContinuityColumn<String>(
                          items: values,
                          keyOf: (item) => item,
                          itemBuilder: (_, item) => _row(item),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    items.value = ['Call Mom', 'Book dinner'];
    await tester.pump();
    await tester.pump();
    Directory(_out).createSync(recursive: true);
    for (var frame = 0; frame <= 10; frame++) {
      if (frame > 0) await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$_out/${frame.toString().padLeft(2, '0')}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}

Widget _row(String text) => SizedBox(
  height: 72,
  child: ListTile(
    leading: const Icon(Icons.circle_outlined),
    title: Text(text),
    subtitle: const Text('Visible planner object'),
  ),
);
