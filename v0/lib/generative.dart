/// Plenara v0 — GenerativeService (Spec 04 §3.10).
///
/// The paid, grounded generative path: gathers ONLY the user's own records as
/// context, asks the cloud for a synthesis (gift ideas, a daily briefing, a
/// weekly review, a pattern insight, a draft message in the user's voice), and
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

  /// True iff the LAST call produced a real cloud synthesis (not a degrade / unknown-person / local
  /// fallback). The caller resets it before a call and reads it after, to decide whether the
  /// recognition template is safe to learn (Spec 03 §2.7 "delivered", `G-46`).
  bool lastDelivered = false;

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
        lastDelivered = true;
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
        lastDelivered = true;
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
        lastDelivered = true;
        return value;
      case CloudError(:final kind):
        return _degrade('a briefing', kind);
    }
  }

  /// A reflective review of the last week's logged activity (P-10): workouts,
  /// moods, interactions, tasks completed — grounded ONLY in records that exist.
  Future<String> weeklyReview(Map<String, _Record> store, DateTime now) async {
    final since = now.subtract(const Duration(days: 7));
    bool inWeek(String? d) {
      if (d == null) return false;
      final t = DateTime.tryParse(d);
      return t != null && !t.isBefore(since) && !t.isAfter(now);
    }

    final workouts = store.values
        .where((r) => r['typeId'] == 'workout' && inWeek(r['date']?.toString()))
        .toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final moods = store.values
        .where((r) => r['typeId'] == 'mood' && inWeek(r['loggedAt']?.toString()))
        .toList()
      ..sort((a, b) => '${a['loggedAt']}'.compareTo('${b['loggedAt']}'));
    final interactions = store.values
        .where((r) => r['typeId'] == 'interaction' && inWeek(r['at']?.toString()))
        .toList()
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    final done = store.values
        .where((r) => r['typeId'] == 'task' && r['completed'] == true)
        .toList();

    // Nothing logged at all -> honest, no generative call spent on an empty week.
    if (workouts.isEmpty && moods.isEmpty && interactions.isEmpty && done.isEmpty) {
      return "There's nothing logged this past week yet — log a workout, a mood, or a "
          "chat with someone and I can put together a weekly review.";
    }

    final ctx = StringBuffer('Week ending: ${now.toIso8601String().substring(0, 10)}\n\n');
    ctx.write(workouts.isEmpty
        ? 'Workouts this week: none logged.\n'
        : 'Workouts this week:\n');
    for (final w in workouts) {
      final dist = w['distance'] == null ? '' : ' ${w['distance']} km';
      ctx.write('  - ${w['activity']}$dist on ${w['date']}\n');
    }
    ctx.write(moods.isEmpty ? 'Moods logged: none.\n' : 'Moods logged:\n');
    for (final m in moods) {
      ctx.write('  - ${m['loggedAt']}: ${m['rating']}\n');
    }
    ctx.write(interactions.isEmpty
        ? 'People you connected with: none logged.\n'
        : 'People you connected with:\n');
    for (final i in interactions) {
      final note = i['note'] == null ? '' : ' (${i['note']})';
      ctx.write('  - ${_contactName(i['subject'], store)} on ${i['at']}$note\n');
    }
    ctx.write('Tasks completed: '
        '${done.isEmpty ? 'none' : done.map((t) => t['description'] ?? t['title']).join('; ')}\n');
    ctx.write('\nWrite a short, reflective weekly review from the above — only what is there.');

    switch (await cloud.generate('weekly_review', ctx.toString())) {
      case CloudOk(:final value):
        lastDelivered = true;
        return value;
      case CloudError(:final kind):
        return _degrade('a weekly review', kind);
    }
  }

  /// A cross-record pattern (P-11) — e.g. mood vs exercise days — grounded ONLY in
  /// the logged series. Needs at least two trackers with data to compare; the model
  /// is told to say so if the records are too thin to support a real pattern.
  Future<String> patternInsight(Map<String, _Record> store, DateTime now) async {
    final moods = store.values
        .where((r) => r['typeId'] == 'mood' && r['loggedAt'] != null)
        .toList()
      ..sort((a, b) => '${a['loggedAt']}'.compareTo('${b['loggedAt']}'));
    final workouts = store.values
        .where((r) => r['typeId'] == 'workout' && r['date'] != null)
        .toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final interactions = store.values
        .where((r) => r['typeId'] == 'interaction' && r['at'] != null)
        .toList()
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));

    // A pattern needs at least two series to relate — with less, be honest and
    // spend nothing.
    final series = [moods, workouts, interactions].where((s) => s.isNotEmpty).length;
    if (series < 2) {
      return "I don't have enough logged data to spot a pattern yet — I need at least "
          "two things to compare (say, moods and workouts). Keep logging and ask again.";
    }

    final ctx = StringBuffer('Today: ${now.toIso8601String().substring(0, 10)}\n\n');
    ctx.write(moods.isEmpty ? 'Mood log: none.\n' : 'Mood log (date: rating):\n');
    for (final m in moods) {
      ctx.write('  - ${m['loggedAt']}: ${m['rating']}\n');
    }
    ctx.write(workouts.isEmpty ? 'Workout days: none.\n' : 'Workout days:\n');
    for (final w in workouts) {
      final dist = w['distance'] == null ? '' : ', ${w['distance']} km';
      ctx.write('  - ${w['date']}: ${w['activity']}$dist\n');
    }
    ctx.write(interactions.isEmpty
        ? 'Days you connected with someone: none.\n'
        : 'Days you connected with someone:\n');
    for (final i in interactions) {
      ctx.write('  - ${i['at']}: ${_contactName(i['subject'], store)}\n');
    }
    ctx.write('\nLooking ONLY at the records above, describe one genuine pattern across '
        'them (for example, how mood relates to exercise days). If the data is too thin '
        'to support a pattern, say so honestly — never invent one.');

    switch (await cloud.generate('pattern_insight', ctx.toString())) {
      case CloudOk(:final value):
        lastDelivered = true;
        return value;
      case CloudError(:final kind):
        return _degrade('a pattern insight', kind);
    }
  }

  /// A short draft message to [personName] in the USER's own voice (P-20), grounded
  /// in what we know about them and the recent interactions we actually logged.
  /// A draft only — the app never sends messages (DP-03).
  Future<String> draftMessage(String personName, Map<String, _Record> store, DateTime now) async {
    final person = _resolveContact(personName, store);
    if (person == null) {
      return "I don't have $personName as a contact yet — tell me about them and log a "
          "chat or two, and I can draft a message that sounds like you.";
    }
    final name = person['displayName'];
    final facts = store.values
        .where((r) => r['typeId'] == 'contact_fact' && r['subject'] == person['id'])
        .map((r) => r['fact'].toString())
        .toList();
    final recent = store.values
        .where((r) => r['typeId'] == 'interaction' && r['subject'] == person['id'])
        .toList()
      ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}')); // most recent first
    final ctx = StringBuffer('Person: $name\n');
    if (facts.isEmpty) {
      ctx.write('Known facts: none recorded yet.\n');
    } else {
      ctx.write('Known facts about them:\n');
      for (final f in facts) {
        ctx.write('  - $f\n');
      }
    }
    if (recent.isEmpty) {
      ctx.write('Recent interactions: none logged yet.\n');
    } else {
      ctx.write('Recent interactions with them (most recent first):\n');
      for (final i in recent.take(3)) {
        final note = i['note'] == null ? '' : ': ${i['note']}';
        ctx.write('  - ${i['at']}$note\n');
      }
    }
    ctx.write('Today: ${now.toIso8601String().substring(0, 10)}\n');
    ctx.write('\nDraft a short, casual message from the user to $name, in the user\'s own '
        'voice, grounded only in the above (pick up a real recent thread if there is one). '
        'This is a draft the user will copy — the app never sends messages.');

    switch (await cloud.generate('draft_message', ctx.toString())) {
      case CloudOk(:final value):
        lastDelivered = true;
        return value;
      case CloudError(:final kind):
        return _degrade('a draft', kind);
    }
  }

  // Resolve an interaction's subject id back to a contact display name, so the
  // grounded context reads like the user's world ("Sarah"), never a raw id.
  String _contactName(dynamic subjectId, Map<String, _Record> store) {
    for (final c in store.values) {
      if (c['typeId'] == 'contact' && c['id'] == subjectId) {
        return (c['displayName'] as String?) ?? 'someone';
      }
    }
    return 'someone';
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
