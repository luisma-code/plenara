import 'dart:convert';
import 'dart:io';

import 'package:plenara/store.dart' show writeJsonAtomic;

/// The production register is deliberately much smaller than the 52-shape
/// sketchbook. These marks are reserved for consequential, recognizable
/// moments; routine writes use Plena's short whole-body acknowledgement.
const activeProductionGlyphs = <String>{
  'bell',
  'candle',
  'check',
  'double-check',
  'gift',
  'heart',
  'quill',
  'reach',
  'settle',
  'star',
  'target',
  'undo-loop',
};

class GlyphRarityGate {
  final String path;
  final DateTime Function() clock;
  final Duration separation;
  final int dailyBudget;

  GlyphRarityGate({
    required this.path,
    DateTime Function()? clock,
    this.separation = const Duration(seconds: 90),
    this.dailyBudget = 3,
  }) : clock = clock ?? DateTime.now;

  List<DateTime>? _read() {
    try {
      final file = File(path);
      if (!file.existsSync()) return [];
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (raw['version'] != 1 || raw['events'] is! List) return null;
      final events = <DateTime>[];
      for (final value in raw['events'] as List) {
        if (value is! String) return null;
        final event = DateTime.tryParse(value);
        if (event == null) return null;
        events.add(event);
      }
      return events;
    } catch (_) {
      return null;
    }
  }

  bool admit(String glyphId) {
    if (!activeProductionGlyphs.contains(glyphId)) return false;
    final now = clock();
    final start = DateTime(now.year, now.month, now.day);
    final stored = _read();
    if (stored == null) return false;
    final events =
        stored
            .where((event) => !event.isBefore(start) && !event.isAfter(now))
            .toList()
          ..sort();
    if (events.isNotEmpty && now.difference(events.last) < separation) {
      return false;
    }
    if (events.length >= dailyBudget) return false;
    events.add(now);
    try {
      writeJsonAtomic(File(path), {
        'version': 1,
        'events': events.map((event) => event.toIso8601String()).toList(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
