/// NLU / routing layer — the corpus fast-path (Spec 03 §5/§6). Hundreds of
/// hero-example phrasings + every date form + slot extraction, all deterministic
/// and offline (no cloud). route() mutates nothing, so one shared Router is safe;
/// learning tests use their own.
import 'package:plenara/router.dart';
import 'package:test/test.dart';

final _now = DateTime.parse('2026-07-06T09:00:00'); // a Monday
final _r = Router.load('data/corpus.json', _now);

const _descriptions = [
  'call the plumber', 'buy milk', 'water the plants', 'email the accountant',
  'pick up the dry cleaning', 'schedule a dentist appointment', 'renew the car registration',
  'book flights to Boston', 'call mom', 'submit the expense report', 'fix the leaky faucet',
  'walk the dog', 'return the library books', 'pay the electric bill', 'order a birthday gift',
  'reply to the landlord', 'charge the drill battery', 'defrost the chicken',
  'text the babysitter', 'confirm the reservation', 'back up my laptop',
  'sign the permission slip', 'water the tomatoes', 'call grandma',
  'schedule the oil change', 'buy stamps', 'wash the car', 'cancel the subscription',
  'pick up prescriptions', 'draft the newsletter',
];

// (phrase, expected ISO) relative to Monday 2026-07-06
const _dateCases = <List<String>>[
  ['today', '2026-07-06'], ['tomorrow', '2026-07-07'], ['yesterday', '2026-07-05'],
  ['in 1 days', '2026-07-07'], ['in 2 days', '2026-07-08'], ['in 3 days', '2026-07-09'],
  ['in 5 days', '2026-07-11'], ['in 7 days', '2026-07-13'], ['in 10 days', '2026-07-16'],
  ['in 30 days', '2026-08-05'],
  ['monday', '2026-07-13'], ['tuesday', '2026-07-07'], ['wednesday', '2026-07-08'],
  ['thursday', '2026-07-09'], ['friday', '2026-07-10'], ['saturday', '2026-07-11'],
  ['sunday', '2026-07-12'],
  ['on thursday', '2026-07-09'], ['next tuesday', '2026-07-07'], ['next monday', '2026-07-13'],
  ['2026-12-25', '2026-12-25'], ['2027-01-01', '2027-01-01'],
  // month-name dates (current year; birthday skills roll to the next occurrence)
  ['march 3', '2026-03-03'], ['mar 3rd', '2026-03-03'], ['on july 12', '2026-07-12'],
  ['december 25', '2026-12-25'], ['3 march', '2026-03-03'], ['the 3rd of december', '2026-12-03'],
  ['sept 9', '2026-09-09'],
];

void main() {
  group('create-task — no date (${_descriptions.length} descriptions × 2 phrasings)', () {
    for (final d in _descriptions) {
      test('"add $d to my list"', () {
        final r = _r.route('add $d to my list');
        expect(r?['skillId'], 'create-task');
        expect(r?['slots']['description'], d);
        expect(r?['slots'].containsKey('dueDate'), isFalse);
        expect(r?['source'], 'corpus');
      });
      test('"remind me to $d"', () {
        final r = _r.route('remind me to $d');
        expect(r?['skillId'], 'create-task');
        expect(r?['slots']['description'], d);
      });
    }
  });

  group('create-task — with date (6 descriptions × ${_dateCases.length} dates × 2 templates)', () {
    const dueDescs = ['call mom', 'buy milk', 'wash the car', 'pay the rent', 'walk the dog', 'book a table'];
    for (final d in dueDescs) {
      for (final c in _dateCases) {
        final phrase = c[0], iso = c[1];
        // "on X" only reads naturally after "due"; skip it for the "on {date}" template
        test('"add $d to my list due $phrase" -> $iso', () {
          final r = _r.route('add $d to my list due $phrase');
          expect(r?['skillId'], 'create-task', reason: phrase);
          expect(r?['slots']['description'], d);
          expect(r?['slots']['dueDate'], iso, reason: phrase);
        });
        if (!phrase.startsWith('on ')) {
          test('"remind me to $d on $phrase" -> $iso', () {
            final r = _r.route('remind me to $d on $phrase');
            expect(r?['skillId'], 'create-task', reason: phrase);
            expect(r?['slots']['description'], d);
            expect(r?['slots']['dueDate'], iso, reason: phrase);
          });
        }
      }
    }
  });

  group('date resolver (Spec 03 §6.2) — direct', () {
    for (final c in _dateCases) {
      test('"${c[0]}" -> ${c[1]}', () => expect(_r.resolveDate(c[0], _now), c[1]));
    }
    for (final bad in ['someday', 'later', 'whenever', 'next month', 'in a while', 'eventually', 'soon']) {
      test('"$bad" -> null (unparseable)', () => expect(_r.resolveDate(bad, _now), isNull));
    }
    test('case-insensitive', () {
      expect(_r.resolveDate('TOMORROW', _now), '2026-07-07');
      expect(_r.resolveDate('Thursday', _now), '2026-07-09');
    });
  });

  group('per-turn clock (Fable review)', () {
    test('route resolves dates against the passed clock, not construction time', () {
      final r = Router.load('data/corpus.json', DateTime.parse('2020-01-01T00:00:00')); // stale construction clock
      expect(r.route('remind me to call mom on friday', clock: _now)?['slots']['dueDate'], '2026-07-10');
      final nextWeek = DateTime.parse('2026-07-13T09:00:00'); // a later Monday
      expect(r.route('remind me to call mom on friday', clock: nextWeek)?['slots']['dueDate'], '2026-07-17');
    });
  });

  group('log-run — quantity extraction', () {
    for (final n in [1, 2, 3, 5, 8, 10, 12, 15, 21, 26]) {
      test('"log a ${n}k run" -> $n', () {
        final r = _r.route('log a ${n}k run');
        expect(r?['skillId'], 'log-run');
        expect(r?['slots']['distance'], n);
      });
      test('"i ran ${n}k" -> $n', () {
        final r = _r.route('i ran ${n}k');
        expect(r?['skillId'], 'log-run');
        expect(r?['slots']['distance'], n);
      });
    }
    for (final n in [0.5, 3.5, 10.5, 13.1, 26.2]) {
      test('"log a ${n}k run" -> $n (decimal)', () {
        expect(_r.route('log a ${n}k run')?['slots']['distance'], n);
      });
    }
    test('"log a run" -> log-run, no distance', () {
      final r = _r.route('log a run');
      expect(r?['skillId'], 'log-run');
      expect(r?['slots']['distance'], isNull);
    });
  });

  group('log-mood — rating extraction (2 templates)', () {
    const ratings = ['great', 'good', 'okay', 'anxious', 'down', 'tired', 'excited',
      'stressed', 'happy', 'sad', 'angry', 'calm', 'overwhelmed', 'content', 'fine'];
    for (final m in ratings) {
      test('"i\'m feeling $m" -> $m', () {
        final r = _r.route("i'm feeling $m");
        expect(r?['skillId'], 'log-mood');
        expect(r?['slots']['rating'], m);
      });
      test('"log my mood as $m" -> $m', () {
        expect(_r.route('log my mood as $m')?['slots']['rating'], m);
      });
    }
  });

  group('remember-person-fact', () {
    for (final n in ['Sarah', 'Mia', 'Tom', 'Priya', 'Chen', 'Ana']) {
      test('"note that $n loves hiking" -> $n', () {
        final r = _r.route('note that $n loves hiking');
        expect(r?['skillId'], 'remember-person-fact');
        expect(r?['slots']['personName'], n);
        expect(r?['slots']['fact'], 'loves hiking');
      });
    }
    test('relational: "remember that Mia is allergic to peanuts and she is Sarah Mitchell\'s daughter"', () {
      final r = _r.route("remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter");
      expect(r?['skillId'], 'remember-person-fact');
      expect(r?['slots']['personName'], 'Mia');
      expect(r?['slots']['fact'], 'is allergic to peanuts');
      expect(r?['slots']['relationTo'], 'Sarah Mitchell');
      expect(r?['slots']['relationType'], 'daughter');
    });
    test('relational "he is": "remember that Leo plays piano and he is Ana\'s son"', () {
      final r = _r.route("remember that Leo plays piano and he is Ana's son");
      expect(r?['slots']['personName'], 'Leo');
      expect(r?['slots']['relationTo'], 'Ana');
      expect(r?['slots']['relationType'], 'son');
    });
  });

  group('recall-facts — including multi-word names', () {
    for (final n in ['Mia', 'Sarah Mitchell', 'Tom', 'Grandma Chen', 'Dr Patel']) {
      test('"what do i know about $n" -> $n', () {
        final r = _r.route('what do i know about $n');
        expect(r?['skillId'], 'recall-facts');
        expect(r?['slots']['personName'], n);
      });
      test('"tell me about $n" -> $n', () {
        expect(_r.route('tell me about $n')?['slots']['personName'], n);
      });
    }
  });

  group('list-tasks + count-runs — all templates', () {
    for (final u in ['list my tasks', 'show my tasks', 'what are my tasks', "what's on my to-do list"]) {
      test('"$u" -> list-tasks', () => expect(_r.route(u)?['skillId'], 'list-tasks'));
    }
    for (final u in ['how many runs this week', 'how far have i run this week',
      'how much have i run this week', 'how many km have i run this week']) {
      test('"$u" -> count-runs-this-week', () => expect(_r.route(u)?['skillId'], 'count-runs-this-week'));
    }
  });

  group('non-matches -> null (corpus miss; would go to cloud/clarify)', () {
    const misses = [
      "what's the weather today", 'play some music', 'call an uber', 'set an alarm for 7am',
      'turn off the lights', 'how are you', 'thanks', 'hello there', 'delete everything',
      "what's 2 plus 2", 'translate hello to spanish', 'add', 'remind', 'log', 'schedule a meeting',
    ];
    for (final u in misses) {
      test('"$u" -> null', () => expect(_r.route(u), isNull));
    }
  });

  group('slot-type resolution', () {
    test('quantity -> num (not string)', () {
      expect(_r.route('log a 7k run')?['slots']['distance'], isA<num>());
    });
    test('date -> ISO string', () {
      expect(_r.route('remind me to call mom on friday')?['slots']['dueDate'], '2026-07-10');
    });
    test('text -> surface string, trimmed', () {
      expect(_r.route('add   buy bread   to my list')?['slots']['description'], 'buy bread');
    });
  });

  group('learning (§5.2) — a cloud/novel phrasing becomes a fast-path template', () {
    test('learned template generalizes across the slot', () {
      final r = Router.load('data/corpus.json', _now);
      expect(r.route('jot down that I need to buy milk'), isNull);
      final tmpl = r.learn('jot down that I need to buy milk', 'create-task', {'description': 'buy milk'});
      expect(tmpl, 'jot down that I need to {description:text}');
      final hit = r.route('jot down that I need to call the vet');
      expect(hit?['skillId'], 'create-task');
      expect(hit?['slots']['description'], 'call the vet');
      expect(hit?['source'], 'corpus');
    });
    test('multiple learned templates coexist and route independently', () {
      final r = Router.load('data/corpus.json', _now);
      r.learn('jot down that I need to buy milk', 'create-task', {'description': 'buy milk'});
      r.learn('log my energy as high', 'log-mood', {'rating': 'high'});
      expect(r.route('jot down that I need to sweep')?['skillId'], 'create-task');
      final mood = r.route('log my energy as low');
      expect(mood?['skillId'], 'log-mood');
      expect(mood?['slots']['rating'], 'low');
    });
    test('a broad learned template does NOT shadow a specific seed skill (Fable#2)', () {
      final r = Router.load('data/corpus.json', _now);
      final tmpl = r.learn('note the milk is gone', 'create-task', {'description': 'the milk is gone'});
      expect(tmpl, 'note {description:text}'); // a broad learned entry
      // a phrasing the SEED "note that {person} {fact}" owns must still reach the seed skill,
      // not the broad learned "note {description}" that also matches it
      expect(r.route('note that Mia loves drawing')?['skillId'], 'remember-person-fact');
      // but the learned entry still fast-paths a phrasing no seed matches
      expect(r.route('note the dog needs a walk')?['skillId'], 'create-task');
    });
    test('a resolved-date slot that is not in the surface -> not abstracted -> null', () {
      final r = Router.load('data/corpus.json', _now);
      // slot value is the ISO date, which does not appear in the surface text
      expect(r.learn('remind me next friday', 'create-task', {'dueDate': '2026-07-10'}), isNull);
    });
    test('match-everything guard: a whole-utterance slot is NOT learned', () {
      final r = Router.load('data/corpus.json', _now);
      // "call mom" -> description IS the whole utterance -> a bare {description}
      // template would match everything and hijack all routing. Must be refused.
      expect(r.learn('call mom', 'create-task', {'description': 'call mom'}), isNull);
      expect(r.route('what do i know about Mia')?['skillId'], 'recall-facts'); // routing intact
      expect(r.route('log a 5k run')?['skillId'], 'log-run');
    });
    test('partial abstraction (one slot not in the surface) is NOT learned', () {
      final r = Router.load('data/corpus.json', _now);
      expect(r.learn('remind me to call mom next friday', 'create-task',
          {'description': 'call mom', 'dueDate': '2026-07-10'}), isNull);
    });
    test('dedupe: learning the same template shape twice returns null', () {
      final r = Router.load('data/corpus.json', _now);
      expect(r.learn('jot down that I need to buy milk', 'create-task', {'description': 'buy milk'}), isNotNull);
      expect(r.learn('jot down that I need to sweep', 'create-task', {'description': 'sweep'}), isNull);
    });
    test('negative half: forget removes a learned template; a seed template is never forgotten', () {
      final r = Router.load('data/corpus.json', _now);
      r.learn('jot down that I need to buy milk', 'create-task', {'description': 'buy milk'});
      const t = 'jot down that I need to {description:text}';
      expect(r.isLearned(t), isTrue);
      expect(r.route('jot down that I need to sweep')?['skillId'], 'create-task');
      expect(r.forget(t), isTrue);
      expect(r.route('jot down that I need to sweep'), isNull); // forgotten
      expect(r.forget('add {description:text} to my {_:text}'), isFalse); // seed can't be forgotten
    });
  });

  group('known corpus fast-path limitations (documented; cloud handles these)', () {
    test('"note that" captures only the first name token (multi-word name leaks into fact)', () {
      final r = _r.route('note that Sarah Mitchell loves hiking');
      expect(r?['slots']['personName'], 'Sarah'); // not "Sarah Mitchell"
      expect(r?['slots']['fact'], 'Mitchell loves hiking');
    });
    test('a description containing " on " confuses the "remind me to X on DATE" template', () {
      // "turn on the heater on friday": the date phrase is ambiguous with the "on" in the description
      final r = _r.route('remind me to turn on the heater on friday');
      // it still routes to create-task, but the split is imperfect — never a mis-route
      expect(r?['skillId'], 'create-task');
    });
  });

  group('resolveDateTime (Spec 03 §6.2 time-of-day extension)', () {
    // a time-of-day is REQUIRED — its absence returns null, which is what keeps a
    // date-only phrase a task rather than a (never-firing) reminder.
    const cases = <List<String?>>[
      ['thursday at 5pm', '2026-07-09T17:00:00'],
      ['on thursday at 5pm', '2026-07-09T17:00:00'],
      ['tomorrow at 9am', '2026-07-07T09:00:00'],
      ['today at 8:30pm', '2026-07-06T20:30:00'],
      ['at noon', '2026-07-06T12:00:00'],
      ['at midnight', '2026-07-07T00:00:00'], // 00:00 today already passed 09:00 -> rolls to tomorrow
      ['in 2 days at 14:15', '2026-07-08T14:15:00'],
      ['friday at 12pm', '2026-07-10T12:00:00'],
      ['friday at 12am', '2026-07-10T00:00:00'],
      ['thursday', null], // no time-of-day -> not a datetime
      ['next week', null],
      ['5 oclock', null], // a bare DIGIT stays excluded (task-vs-reminder discriminator)
      // WORD times (gap #44) — a spoken hour resolves; 1-6 default to PM (evening intent)
      ['at five', '2026-07-06T17:00:00'],
      ["five o'clock", '2026-07-06T17:00:00'],
      ['half past six', '2026-07-06T18:30:00'],
      ['quarter to seven', '2026-07-06T18:45:00'],
      ['quarter past five', '2026-07-06T17:15:00'],
      ['five thirty', '2026-07-06T17:30:00'],
      ['seven pm', '2026-07-06T19:00:00'],
      ['at eight', '2026-07-07T08:00:00'], // 7-12 stay as spoken -> 08:00 past 09:00 -> tomorrow
      ['nine in the morning', '2026-07-07T09:00:00'], // 09:00 == now -> not after -> tomorrow
      ['ten thirty', '2026-07-06T10:30:00'],
    ];
    for (final c in cases) {
      test('"${c[0]}" -> ${c[1]}', () => expect(_r.resolveDateTime(c[0]!, _now), c[1]));
    }

    test('a word-time routes an at-reminder end to end', () {
      final r = _r.route('remind me at five to call mom', clock: _now);
      expect(r?['skillId'], 'set-reminder');
      expect(r?['slots']['text'], 'call mom');
      expect(r?['slots']['when'], '2026-07-06T17:00:00');
    });

    test('a time-only phrase already past today rolls to tomorrow', () {
      expect(_r.resolveDateTime('at 8am', _now), '2026-07-07T08:00:00'); // 8am < 9am now
      expect(_r.resolveDateTime('at 11am', _now), '2026-07-06T11:00:00'); // still ahead today
    });
  });

  group('reminder vs task routing (the time discriminator)', () {
    test('"remind me to X on <day> at <time>" -> set-reminder with a full datetime', () {
      final r = _r.route('remind me to call mom on thursday at 5pm', clock: _now);
      expect(r?['skillId'], 'set-reminder');
      expect(r?['slots']['text'], 'call mom');
      expect(r?['slots']['when'], '2026-07-09T17:00:00');
    });
    test('"remind me to X at <time>" -> set-reminder', () {
      final r = _r.route('remind me to take medicine at 9am', clock: _now);
      expect(r?['skillId'], 'set-reminder');
      expect(r?['slots']['when'], '2026-07-07T09:00:00'); // 9am past 9:00:00 -> tomorrow
    });
    test('"remind me to X on <day>" (no time) still falls through to create-task', () {
      final r = _r.route('remind me to call mom on friday', clock: _now);
      expect(r?['skillId'], 'create-task');
      expect(r?['slots']['dueDate'], '2026-07-10');
    });
    test('postfix day + time keeps the day (gap #54): "X tomorrow at 5pm"', () {
      final r = _r.route('remind me to call mom tomorrow at 5pm', clock: _now);
      expect(r?['skillId'], 'set-reminder-on-day');
      expect(r?['slots']['text'], 'call mom');
      expect(r?['slots']['day'], '2026-07-07');
      expect(r?['slots']['when'], '2026-07-06T17:00:00'); // just the time part is combined with the day
    });
    test('bare postfix day, no time -> dated create-task (gap #45): "X tomorrow"', () {
      final r = _r.route('remind me to call mom tomorrow', clock: _now);
      expect(r?['skillId'], 'create-task');
      expect(r?['slots']['description'], 'call mom');
      expect(r?['slots']['dueDate'], '2026-07-07');
    });
    test('leading day, no time -> dated create-task (gap #45): "remind me tomorrow to X"', () {
      final r = _r.route('remind me tomorrow to call mom', clock: _now);
      expect(r?['skillId'], 'create-task');
      expect(r?['slots']['description'], 'call mom');
      expect(r?['slots']['dueDate'], '2026-07-07');
    });
  });

  group('reminder management routing (wins over task ops on overlap)', () {
    test('"what are my reminders" -> list-reminders (not list-tasks)', () {
      expect(_r.route('what are my reminders')?['skillId'], 'list-reminders');
    });
    test('"mark the reminder to X done" -> complete-reminder (not complete-task)', () {
      final r = _r.route('mark the reminder to call mom done');
      expect(r?['skillId'], 'complete-reminder');
      expect(r?['slots']['text'], 'call mom');
    });
    test('"cancel the reminder to X" -> cancel-reminder', () {
      final r = _r.route('cancel the reminder to call mom');
      expect(r?['skillId'], 'cancel-reminder');
      expect(r?['slots']['text'], 'call mom');
    });
    test('"forget the reminder to X" -> cancel-reminder', () {
      expect(_r.route('forget the reminder to water the plants')?['skillId'], 'cancel-reminder');
    });
  });

  group('expanded offline coverage (natural phrasings that were falling to cloud)', () {
    const cases = <List<String>>[
      ['i need to buy milk', 'create-task'],
      ['put buy milk on my list', 'create-task'],
      ['list my todos', 'list-tasks'],
      ['ping me to call mom at 5pm', 'set-reminder'],
      ['i feel great today', 'log-mood'],
      ['i feel tired', 'log-mood'],
      ['i went for a run', 'log-run'],
      ['any birthdays soon', 'upcoming-birthdays'],
    ];
    for (final c in cases) {
      test('"${c[0]}" -> ${c[1]}', () => expect(_r.route(c[0], clock: _now)?['skillId'], c[1]));
    }
    test('the residual fixtures still MISS the corpus (no accidental capture)', () {
      // these must stay cloud-routed; a new template must never steal them
      expect(_r.route('jot down that I need to buy milk'), isNull);
      expect(_r.route('put picking up dry cleaning on my to-do list'), isNull);
      expect(_r.route('went for a 5k this afternoon'), isNull);
    });
  });

  group('phrasing expansion — over-match guards + new coverage', () {
    for (final u in const [
      'what is the capital of france',
      'note that the meeting is at five',
      'remember the alamo',
      'i had a great day',
      'i had a rough night',
      'tell me a joke',
      'what is the weather like today',
    ]) {
      test('over-match guard: "$u" stays uncaptured', () => expect(_r.route(u), isNull));
    }
    const coverage = {
      'delete all my todos': 'clear-tasks',
      'i ate mac and cheese': 'log-meal',
      'remember that Sarah loves hiking': 'remember-person-fact',
      'i talked to Marco about the trip': 'log-interaction',
      'remind me every day at 9am to stretch': 'set-daily-reminder',
      'remind me on wednesdays at 8am to water plants': 'set-weekly-reminder',
    };
    coverage.forEach((u, skill) {
      test('coverage: "$u" -> $skill', () => expect(_r.route(u)?['skillId'], skill));
    });
  });

  group(':contact slot + learn (Fable review fixes)', () {
    test('learn abstracts a known contact to :contact, not :text (guard survives learning)', () {
      final r = Router.load('data/corpus.json', _now);
      // a NON-seed phrasing (a seed dedups to null) — the cloud could route this to recall
      final t = r.learn('tell me what Sam is allergic to', 'recall-fact-about',
          {'personName': 'Sam', 'query': 'allergic to'}, contacts: {'sam'});
      expect(t, contains('{personName:contact}'));
      expect(t, isNot(contains('{personName:text}'))); // :text here would hijack all "tell me what X is Y"
    });

    test('a :contact slot only matches a known contact', () {
      // "the" isn't a contact -> the recall template must NOT fire on world-knowledge
      expect(_r.route('what is the capital of france', contacts: {'mia'})?['skillId'], isNot('recall-fact-about'));
      // "mia" is a contact -> it fires
      expect(_r.route('what is mia allergic to', contacts: {'mia'})?['skillId'], 'recall-fact-about');
    });

    test('a trailing "?" is stripped from the captured slot', () {
      final hit = _r.route('what is mia allergic to?', contacts: {'mia'});
      expect(hit?['slots']['query'], 'allergic to'); // not "allergic to?"
    });
  });
}
