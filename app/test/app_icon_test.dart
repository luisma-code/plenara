import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'the shipped icon is Plena-dark, warm, opaque, and legible at 16 px',
    () {
      final master = image.decodePng(
        File('assets/brand/plena-app-icon.png').readAsBytesSync(),
      )!;
      final tiny = image.decodePng(
        File(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png',
        ).readAsBytesSync(),
      )!;

      expect(master.width, 1024);
      expect(master.height, 1024);
      expect(
        master.getPixel(0, 0).a,
        255,
        reason: 'iOS icons cannot be transparent',
      );
      final corner = master.getPixel(0, 0);
      expect(corner.r, lessThan(20));
      expect(corner.g, lessThan(20));
      expect(corner.b, lessThan(20));

      var warmPixels = 0;
      for (final pixel in tiny) {
        if (pixel.r > pixel.b * 1.5 && pixel.r > 70) warmPixels++;
      }
      expect(
        warmPixels,
        greaterThan(12),
        reason: 'Plena must remain visibly warm at Spotlight/Settings size',
      );
      final center = tiny.getPixel(8, 8);
      expect(center.r, greaterThan(center.b * 1.6));
    },
  );
}
