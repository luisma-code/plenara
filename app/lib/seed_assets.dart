/// First-run seed extraction. The built-in capability defs are bundled as Flutter assets under
/// `assets/seed/` (mirrored from `v0/data` by `tool/sync_seed.sh`), so a SHIPPED binary can seed
/// itself with no repo on disk. This writes those assets to a staging dir that mirrors the
/// `v0/data` layout, which `ensureSeeded()` then copies into the user's data folder unchanged —
/// keeping the v0 engine filesystem-pure (it never learns about `rootBundle`).
library;

import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;

const _prefix = 'assets/seed/';

/// Extract every `assets/seed/**` asset to a temp staging dir mirroring the v0/data tree, and
/// return that dir's path (to pass to `ensureSeeded` as the seed source). Overwrites any prior
/// staging so a rebuilt binary always seeds from its OWN bundled defs.
Future<String> extractSeedAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final keys = manifest.listAssets().where((k) => k.startsWith(_prefix));
  final root = Directory('${Directory.systemTemp.path}/plenara-seed');
  if (root.existsSync()) root.deleteSync(recursive: true);
  for (final key in keys) {
    final data = await rootBundle.load(key);
    final out = File('${root.path}/${key.substring(_prefix.length)}')
      ..createSync(recursive: true);
    out.writeAsBytesSync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
  return root.path;
}
