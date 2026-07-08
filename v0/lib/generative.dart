/// Plenara v0 — GenerativeService (Spec 04 §3.10).
///
/// The paid, grounded generative path: gathers ONLY the user's own records as
/// context, asks the cloud for a synthesis (gift ideas, a daily briefing), and
/// returns the text — or an honest degrade when the cloud isn't reachable. The
/// grounding (assembling real facts, never inventing) is the deterministic part
/// and is unit-tested; the model call is behind the [CloudClient] seam.
library;

import 'claude.dart';
import 'people.dart' show upcomingBirthdayNudges;

typedef _Record = Map<String, dynamic>;

class GenerativeService {
  final CloudClient cloud;
  GenerativeService(this.cloud);

  /// Gift ideas for [personName], grounded in what we actually know about them.
  Future<String> giftIdeas(String personName, Map<String, _Record> store, DateTime now) async {
    final person = _resolveContact(personName, store);
    if (person == null) {
      return "I don't have $personName as a contact yet — tell me a bit about them first "
          "(\"remember that $personName loves hiking\") and I can suggest something.";
    }
    final name = person['displayName'];
    final facts = store.values
        .where((r) => r['typeId'] == 'contact_fact' && r['subject'] == person['id'])
        .map((r) => r['fact'].toString())
        .toList();
    final ctx = StringBuffer('Person: $name\n');
    if (facts.isEmpty) {
      ctx.write('Known facts: none recorded yet.\n');
    } else {
      ctx.write('Known facts about them:\n');
      for (final f in facts) {
        ctx.write('  - $f\n');
      }
    }
    if (person['birthday'] != null) ctx.write('Birthday: ${person['birthday']}\n');
    ctx.write('\nSuggest gift ideas for $name, grounded only in the facts above.');

    switch (await cloud.generate('gift_ideas', ctx.toString())) {
      case CloudOk(:final value):
        return value;
      case CloudError(:final kind):
        return _degrade('gift ideas', kind);
    }
  }

  /// Warm, specific coaching to reconnect with someone — grounded in what we know about
  /// them and how long it's been. Directly serves the app's purpose (be a better friend).
  Future<String> reconnect(String personName, Map<String, _Record> store, DateTime now) async {
    final person = _resolveContact(personName, store);
    if (person == null) {
      return "I don't have $personName as a contact yet — tell me about them and I can help "
          "you reconnect.";
    }
    final name = person['displayName'];
    final facts = store.values
        .where((r) => r['typeId'] == 'contact_fact' && r['subject'] == person['id'])
        .map((r) => r['fact'].toString())
        .toList();
    // most recent logged interaction with them (subject-linked, like last-interaction)
    final dates = store.values
        .where((r) => r['typeId'] == 'interaction' && r['subject'] == person['id'])
        .map((r) => r['at']?.toString())
        .whereType<String>()
        .toList()
      ..sort();
    final ctx = StringBuffer('Person: $name\n');
    if (facts.isEmpty) {
      ctx.write('Known facts: none recorded yet.\n');
    } else {
      ctx.write('Known facts about them:\n');
      for (final f in facts) {
        ctx.write('  - $f\n');
      }
    }
    ctx.write('Last time you logged talking: ${dates.isEmpty ? 'no record' : dates.last}\n');
    ctx.write("Today: ${now.toIso8601String().substring(0, 10)}\n");
    ctx.write('\nSuggest warm, specific ways to reconnect with $name, grounded only in the above.');

    switch (await cloud.generate('reconnect', ctx.toString())) {
      case CloudOk(:final value):
        return value;
      case CloudError(:final kind):
        return _degrade('reconnect ideas', kind);
    }
  }

  /// A short, warm daily briefing grounded in what's actually on the user's plate today.
  Future<String> briefing(Map<String, _Record> store, DateTime now, {String Function()? agenda}) async {
    final ctx = StringBuffer('Date: ${now.toIso8601String().substring(0, 10)}\n\n');
    final tasks = store.values.where((r) => r['typeId'] == 'task' && r['completed'] != true).toList();
    final reminders = store.values.where((r) => r['typeId'] == 'reminder' && r['done'] != true).toList();
    ctx.write('Open tasks: ${tasks.isEmpty ? 'none' : tasks.map((t) => t['description'] ?? t['title']).join('; ')}\n');
    ctx.write('Active reminders: ${reminders.isEmpty ? 'none' : reminders.map((r) => r['text']).join('; ')}\n');
    final bdays = upcomingBirthdayNudges(store, now);
    ctx.write('Upcoming birthdays: ${bdays.isEmpty ? 'none' : bdays.join('; ')}\n');
    ctx.write('\nWrite a brief, warm morning briefing from the above — only what is there.');

    switch (await cloud.generate('briefing', ctx.toString())) {
      case CloudOk(:final value):
        return value;
      case CloudError(:final kind):
        return _degrade('a briefing', kind);
    }
  }

  // Honest, tier/connectivity-aware degrade (Spec 05 §13) — never a vague failure.
  String _degrade(String what, CloudErrorKind kind) => switch (kind) {
        CloudErrorKind.noKey =>
          "$what need a connected Claude account — that's a cloud feature. Add a key and I can help.",
        CloudErrorKind.offline =>
          "I can't put together $what while offline — try again when you're back online.",
        CloudErrorKind.rateLimited => "I'm being rate-limited right now — try $what again in a moment.",
        _ => "I couldn't put together $what right now (${kind.name}).",
      };

  // Mirror read_one's contact resolution (exact -> substring -> alias) without a full
  // interpreter run, so grounding and resolution stay consistent with the skills.
  _Record? _resolveContact(String name, Map<String, _Record> store) {
    final want = name.toLowerCase().trim();
    final contacts = store.values.where((r) => r['typeId'] == 'contact').toList();
    for (final c in contacts) {
      if ((c['displayName'] as String?)?.toLowerCase() == want) return c;
    }
    for (final c in contacts) {
      if ((c['displayName'] as String?)?.toLowerCase().contains(want) == true) return c;
    }
    for (final c in contacts) {
      final a = c['aliases'];
      if (a is String && a.toLowerCase().split(',').map((s) => s.trim()).contains(want)) return c;
    }
    return null;
  }
}
