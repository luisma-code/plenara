import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as image;

const _ground = (10, 9, 8);
const _amber = (217, 154, 84);

void main() {
  final master = _plenaMark(1024);
  final masterPath = 'assets/brand/plena-app-icon.png';
  Directory('assets/brand').createSync(recursive: true);
  File(masterPath).writeAsBytesSync(image.encodePng(master));

  const ios = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  const macos = <String, int>{
    'app_icon_16.png': 16,
    'app_icon_32.png': 32,
    'app_icon_64.png': 64,
    'app_icon_128.png': 128,
    'app_icon_256.png': 256,
    'app_icon_512.png': 512,
    'app_icon_1024.png': 1024,
  };
  _writeSet(master, 'ios/Runner/Assets.xcassets/AppIcon.appiconset', ios);
  _writeSet(master, 'macos/Runner/Assets.xcassets/AppIcon.appiconset', macos);

  final windows = image.copyResize(
    master,
    width: 256,
    height: 256,
    interpolation: image.Interpolation.average,
  );
  File(
    'windows/runner/resources/app_icon.ico',
  ).writeAsBytesSync(image.encodeIco(windows));
}

void _writeSet(image.Image master, String directory, Map<String, int> files) {
  for (final entry in files.entries) {
    final output = entry.value == master.width
        ? master
        : image.copyResize(
            master,
            width: entry.value,
            height: entry.value,
            interpolation: image.Interpolation.average,
          );
    File('$directory/${entry.key}').writeAsBytesSync(image.encodePng(output));
  }
}

image.Image _plenaMark(int size) {
  final canvas = image.Image(width: size, height: size, numChannels: 4);
  image.fill(
    canvas,
    color: image.ColorRgba8(_ground.$1, _ground.$2, _ground.$3, 255),
  );

  final scale = size / 1024;
  void mote(double x, double y, double radius, int alpha) => image.fillCircle(
    canvas,
    x: (x * scale).round(),
    y: (y * scale).round(),
    radius: max(1, (radius * scale).round()),
    color: image.ColorRgba8(_amber.$1, _amber.$2, _amber.$3, alpha),
    antialias: true,
  );

  // A calm, asymmetric core remains readable at 16 px; the swarm around it
  // echoes the living presence without turning the icon into a screenshot.
  for (var radius = 260; radius >= 52; radius -= 10) {
    final t = (260 - radius) / 208;
    mote(510, 508, radius.toDouble(), (2 + 5 * t).round());
  }

  final random = Random(0x504C454E41);
  for (var index = 0; index < 720; index++) {
    final angle = random.nextDouble() * pi * 2;
    final radial = sqrt(random.nextDouble());
    final taper = .62 + .38 * cos(angle - .35);
    final x = 510 + cos(angle) * radial * 292 * taper;
    final y = 510 + sin(angle) * radial * 216;
    final central = 1 - radial;
    final radius = 2.0 + central * 5.8 + random.nextDouble() * 2.2;
    final alpha = (45 + central * 165 + random.nextDouble() * 35).round();
    mote(x, y, radius, min(255, alpha));
  }

  const anchors = <(double, double, double)>[
    (330, 398, 12),
    (396, 328, 8),
    (492, 306, 11),
    (602, 338, 7),
    (683, 406, 10),
    (710, 520, 7),
    (646, 616, 10),
    (526, 666, 7),
    (406, 635, 9),
    (324, 548, 7),
  ];
  for (final (x, y, radius) in anchors) {
    mote(x, y, radius * 3.2, 52);
    mote(x, y, radius, 245);
  }
  mote(510, 506, 126, 68);
  mote(510, 506, 72, 176);
  mote(510, 506, 26, 250);
  mote(496, 493, 6, 255);
  return canvas;
}
