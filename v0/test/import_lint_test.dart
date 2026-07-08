import 'package:test/test.dart';

import '../bin/import_lint.dart';

void main() {
  group('import-lint dependency rule (Spec 09 §8.4 / research §9)', () {
    test('an UPWARD import (storage L1 -> business-logic L2) is flagged', () {
      final v = lintGraph({'store': ['session']});
      expect(v, hasLength(1));
      expect(v.single, contains('UPWARD'));
    });
    test('a downward import (business-logic -> storage/intelligence) is allowed', () {
      expect(lintGraph({'session': ['store', 'claude', 'router']}), isEmpty);
    });
    test('same-layer imports are allowed', () {
      expect(lintGraph({'router': ['embed'], 'generative': ['people']}), isEmpty);
    });
    test('an unclassified file (treated as bottom) importing a higher layer is still caught', () {
      expect(lintGraph({'newfile': ['session']}), hasLength(1));
    });
    test('a snapshot of the real lib graph has no violations', () {
      expect(
          lintGraph({
            'session': ['automations', 'claude', 'generative', 'interpreter', 'people', 'reminders', 'router', 'storage_repository'],
            'generative': ['claude', 'people'],
            'automations': ['cron', 'interpreter'],
            'storage_repository': ['store'],
            'router': ['embed'],
            'replay_cloud': ['claude'],
            'interpreter': ['dates'],
            'people': ['dates'],
          }),
          isEmpty);
    });
  });
}
