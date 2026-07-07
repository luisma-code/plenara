/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'claude.dart';
import 'interpreter.dart';
import 'people.dart';
import 'reminders.dart';
import 'router.dart';
import 'storage_repository.dart';

final _undoRe = RegExp(r'^(undo|undo that|no,? take that back|scratch that)\.?$', caseSensitive: false);
// Discoverability (Spec 03 §6.3): a clarify dead-ends without "here's what I can do".
// A DSL skill can't introspect the skill registry, so this is a Session-level surface.
final _helpRe = RegExp(
    r'^(?:help|what can you do|what can i (?:say|do|ask)( you)?|what are your (?:skills|capabilities)|'
    r'show me what you can do)\??$',
    caseSensitive: false);
// Correction (§3.3): a natural prefix + "I meant …" reverses the last turn and re-routes.
// The "I meant" anchor is deliberate — a bare "no, X" is too easily a non-correction, and
// reversing a good write on a false positive is the worse failure.
final _corrRe = RegExp(
    r'^(?:no,?|nope,?|actually,?|no wait,?|wait,?|sorry,?|oops,?|hang on,?)\s+i meant (?:to |it was )?(.+?)\.?$',
    caseSensitive: false);
// abandons a pending slot-fill dialogue (Spec 03 §6.3 ProvideSlot)
final _cancelRe = RegExp(r'^(cancel|never ?mind|forget it|nvm|stop|no thanks)\.?$', caseSensitive: false);
// Out-of-domain boundary (Spec 03 §7.2, G-19). A clearly-external question with NO
// personal cue gets a graceful "that's not what I do" instead of "I didn't catch that".
// The personal-cue guard is a PRIVACY boundary, not just UX: "what did I say about X"
// must NEVER be classified out-of-domain and handed to an external assistant — a records
// query stays in the records domain even when we can't yet answer it.
final _worldKnowledgeRe = RegExp(
    r"\b(capital of|the weather|weather in|forecast|tell me a joke|what time is it in|"
    r"who (is|was|were|are) (?!my |our )|what year|how (tall|far|old|big|deep|hot|cold) is|"
    r"translate|how do you say|what does .+ mean|^define |stock price|exchange rate|"
    r"convert |the news|latest news|score of|who won|population of|"
    r"distance (from|to|between)|meaning of life)\b",
    caseSensitive: false);
final _personalCueRe = RegExp(r"\b(i|i'?ve|i'?m|my|mine|our|ours|we|us|me)\b", caseSensitive: false);
// A tracker the app ALREADY ships — "start tracking my runs" should use it for FREE,
// not pay Haiku to author a duplicate type (Spec 05 §3.7; the free→paid misroute). Kept
// deliberately narrow: only unambiguous SELF trackers, and skipped entirely when a
// third-party possessive is present ("my daughter's mood" is a genuinely new capability).
final _thirdPartyRe = RegExp(
    r"\b(daughter|son|kid|kids|child|children|wife|husband|partner|mom|mum|dad|friend|colleague|coworker|team)('s|s')?\b",
    caseSensitive: false);
// Anchored to the WHOLE description so only a BARE built-in matches ("runs", "my
// journal") — a qualified variant ("daily gratitude journal") is a new structured type
// and correctly falls through to authoring.
const _builtinTrackers = <String, String>{
  r'^(my )?(runs?|running|jogs?|jogging)$': 'log a 3k run',
  r'^(my )?(journal|diary)$': 'journal that today was a good day',
  r'^(my )?(moods?|feelings?)$': 'log your mood, e.g. "I\'m feeling great"',
};
final _defRe = RegExp(
    r'^(?:start tracking|track|i want to track|i want to start tracking|make me a|create a|'
    r'build me a|build a|set up a|set me up a) '
    r'(?:my |a |an )?(.+?)(?: tracker)?\.?$',
    caseSensitive: false);
// Layer-1 policy floor (Spec 02 §7.6): key on harmful FRAMING, never merely a
// sensitive topic. "track my kid's mood" (the flagship marquee) is fine; "track
// my kid secretly / without their knowledge" is not. Layers 2/3 (model + review)
// are v2.
final _harmfulRe = RegExp(
    // covert / non-consensual surveillance framing (DP-01: "…location without them knowing")
    r"secretly|covertly"
    r"|without (?:them|their|him|his|her|your) (?:knowing|knowledge|consent|permission|noticing|finding out)"
    r"|behind (?:their|his|her) back|\bspy on\b|\bstalk\b|keep tabs on|\bsnoop\b"
    // self-harm, weapons, disordered-eating framing (DP-08: "…so I can cut down harder")
    r"|self.?harm|hurt (?:myself|someone|somebody)|make a weapon|build a weapon"
    r"|purge (?:after|my|food|meal)|hide (?:my )?(?:eating|calories)|restrict (?:my )?calories"
    r"|cut down harder|so i can cut|eat less so",
    caseSensitive: false);
// authored ids are model output; keep them out of file paths and odd charsets
final _idRe = RegExp(r'^[a-z0-9_-]{1,64}$');

/// One reversible turn (Spec 02 §5.2 / Spec 04 §3.11): the before-images to
/// restore + a human description of what it did. The execution journal is a
/// device-local, volatile ring of these — undo can walk back the last N turns.
class _JournalEntry {
  final Map<String, Map<String, dynamic>?> before;
  final String? desc;
  _JournalEntry(this.before, this.desc);
}

class Session {
  final String dataDir;
  final DateTime? _fixedClock;
  /// The clock, read live per access so a long-open app never freezes at launch
  /// time (Spec 03 §4 wants a per-turn snapshot). Tests/the demo pin it via the
  /// [clock] constructor arg for reproducibility.
  DateTime get now => _fixedClock ?? DateTime.now();
  late Map<String, Map<String, dynamic>> types;
  late Map<String, Map<String, dynamic>> skills;
  late Map<String, Map<String, dynamic>> store;
  late Interpreter interp;
  late Router router;
  late CloudClient claude;
  late StorageRepository repo;
  final CloudClient? _injectedCloud;
  final StorageRepository? _injectedStorage;
  // The OS-notification adapter (Spec 04 §3.1). Null -> reminders still persist and
  // nudge on open, they just don't arm a native toast. The reconciled armed set is
  // DERIVED from the record store, so undo/delete cancel notifications for free.
  final NotificationScheduler? _scheduler;
  static const _journalMax = 25; // ring depth
  final List<_JournalEntry> _journal = []; // execution journal of REVERSIBLE (write) turns
  // the immediately-previous routed turn (write OR read), so a correction targets
  // the right thing: forget its template, and reverse it ONLY if it actually wrote.
  String? _lastTurnTemplate;
  bool _lastTurnWrote = false;
  String _outSource = 'clarify'; // telemetry: how this turn resolved
  String? _outSkill;
  String? _cloudStatus; // telemetry: cloud health this turn ('ok' or a CloudErrorKind name)
  // A paused turn waiting for the user to supply a missing required slot (Spec 03
  // §6.3 ProvideSlot): {skillId, slots (partial), missing (remaining required names)}.
  // The next turn's input fills it and the completed skill dispatches.
  Map<String, dynamic>? _pendingFill;
  // Whether retrieval (the embed-server index) is active this session. Authoring
  // grows the inventory and must re-index — but only when retrieval is on, so the
  // authoring path stays hermetic under init(retrieval: false), like init() itself.
  bool _retrievalEnabled = true;

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart); [storage]
  /// lets them inject a repository (in-memory / test double). Production leaves both
  /// null -> a live ClaudeClient over a FileStorageRepository.
  Session(this.dataDir,
      {DateTime? clock, CloudClient? cloud, StorageRepository? storage, NotificationScheduler? scheduler})
      : _fixedClock = clock,
        _injectedCloud = cloud,
        _injectedStorage = storage,
        _scheduler = scheduler;

  /// [retrieval] builds the embedding index (needs the embed server). Tests pass
  /// false to stay hermetic — the corpus fast-path and injected cloud need no
  /// embeddings; only the cold-start suggestion on a full miss does.
  Future<void> init({bool retrieval = true}) async {
    repo = _injectedStorage ?? FileStorageRepository(dataDir);
    types = repo.loadDefs('types', 'typeId');
    skills = repo.loadDefs('skills', 'skillId');
    store = repo.loadRecords();
    interp = Interpreter(types, now);
    router = Router.load('$dataDir/corpus.json', now, learnedPath: '$dataDir/corpus-learned.json');
    claude = _injectedCloud ?? ClaudeClient();
    for (final s in skills.values) {
      interp.validateSkill(s);
    }
    _retrievalEnabled = retrieval;
    if (retrieval) await router.buildRetrievalIndex(skills);
    await _reconcileReminders(); // arm any future reminders already on disk (re-open)
  }

  /// Re-derive the armed notification set from the record store and reconcile the
  /// OS scheduler to it. Idempotent, so calling it every turn + on open never
  /// double-arms. A scheduler failure is contained — it must never break a turn.
  Future<void> _reconcileReminders() async {
    final sched = _scheduler;
    if (sched == null) return;
    try {
      await reconcileReminders(sched, store, now);
    } catch (_) {/* an OS notification hiccup is not worth failing the turn over */}
  }

  /// A concise, capability-grounded "what can you do" surface. Grouped by area with
  /// real example phrasings (more useful than dumping 19 raw displayNames); each line
  /// is gated on the skill actually being registered, so it never advertises a
  /// capability the current inventory doesn't have.
  String _helpText() {
    bool has(String id) => skills.containsKey(id);
    final lines = <String>[
      if (has('create-task'))
        '• Tasks — "add call the plumber to my list", "list my tasks", "what\'s due", "move X to friday", "mark X done", "delete X"',
      if (has('set-reminder'))
        '• Reminders — "remind me to call mom on thursday at 5pm", "what are my reminders", "snooze the reminder to X to friday at 9am", "cancel the reminder to X"',
      if (has('log-run'))
        '• Running — "log a 3k run", "how much have I run this week", "how far have I run", "what\'s my running streak"',
      if (has('log-mood')) '• Mood — "I\'m feeling great", "how have I been feeling"',
      if (has('log-journal')) '• Journal — "journal that today was a good day", "read my journal"',
      if (has('remember-person-fact'))
        '• People — "remember that Mia is Sarah\'s daughter", "what do I know about Mia", "talked to Sam about the trip", "when did I last talk to Sam"',
      if (has('set-birthday'))
        '• Birthdays — "Sarah\'s birthday is july 16", "whose birthday is coming up"',
      if (has('set-alias')) '• Nicknames — "Sarah\'s nickname is Mum", then "when did I last talk to Mum"',
      '• New trackers — "start tracking my water intake"',
    ];
    return 'Here\'s what I can do:\n${lines.join('\n')}\nAnd "undo that" reverses the last thing.';
  }

  /// Resolve a cloud-routed skill's declared date/datetime input slots through the
  /// deterministic resolver, so the cloud path matches the corpus path's typed slots.
  /// An unresolvable required datetime becomes null — which drops into a skill's own
  /// "when?" clarify branch rather than persisting a wrong or unparseable time.
  void _normalizeTypedSlots(Map<String, dynamic>? skill, Map<String, dynamic> slots, DateTime now) {
    final inputs = skill?['inputs'] as List?;
    if (inputs == null) return;
    for (final i in inputs) {
      if (i is! Map) continue;
      final name = i['name'], type = i['type'];
      if (name is! String || slots[name] is! String) continue;
      if (type == 'date') slots[name] = router.resolveDate(slots[name] as String, now);
      if (type == 'datetime') slots[name] = router.resolveDateTime(slots[name] as String, now);
    }
  }

  /// On-open nudge lines (the UI shows these on launch). Two derived sources, so
  /// each drops out the moment its record changes: past-due reminders (you can't
  /// schedule a toast in the past) and birthdays coming up within a week. Each line
  /// carries its own icon.
  List<String> pendingNudges() => [
        for (final r in dueReminders(store, now)) '⏰ Reminder: ${r.body}',
        ...upcomingBirthdayNudges(store, now),
      ];

  /// Reverse a turn's writes via the repository (undo / correction).
  void _reverse(Map<String, Map<String, dynamic>?> before) {
    before.forEach((id, prior) {
      if (prior == null) {
        store.remove(id);
        repo.remove(id); // tombstone
      } else {
        store[id] = Map<String, dynamic>.from(prior);
        repo.persist(prior);
      }
    });
  }

  /// Public entry: a catch-all boundary so NO exception (ResolveError or a raw
  /// TypeError/RangeError from model-shaped input) ever escapes into the UI or
  /// console. A crash becomes a visible, non-destructive message (no silent
  /// failure, P7) rather than a bricked input box.
  Future<String> handle(String u) async {
    u = u.trim();
    _outSource = 'clarify';
    _outSkill = null;
    _cloudStatus = null;
    String resp;
    try {
      resp = await _handle(u);
    } catch (e) {
      _outSource = 'error';
      resp = "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
    }
    // the turn may have added/undone/completed a reminder — keep the OS armed set
    // in sync with the (now-updated) store. Derived, so no per-skill wiring needed.
    await _reconcileReminders();
    // dogfood telemetry — measures clarify/cloud/correction rates + cloud health in real use
    repo.logTurn({
      'at': DateTime.now().toIso8601String(),
      'utterance': u,
      'source': _outSource,
      if (_outSkill != null) 'skill': _outSkill,
      if (_cloudStatus != null) 'cloud': _cloudStatus,
    });
    return resp;
  }

  /// A short, honest, user-facing reason a cloud call failed — so a miss names the
  /// cause instead of always blaming the user's phrasing (no silent degradation).
  static String cloudReason(CloudErrorKind k) => switch (k) {
        CloudErrorKind.noKey => "I don't have an API key set — add one in ~/.plenara/config.json.",
        CloudErrorKind.badKey => "my API key was rejected — update it in ~/.plenara/config.json.",
        CloudErrorKind.offline => "I'm offline right now.",
        CloudErrorKind.timeout => "the cloud didn't respond in time.",
        CloudErrorKind.rateLimited => "I'm being rate-limited — try again shortly.",
        CloudErrorKind.serverError => "the cloud had a server error.",
        CloudErrorKind.malformed => "I got an unexpected response from the cloud.",
      };

  /// Process one utterance; returns the assistant's response text (may be multi-line).
  Future<String> _handle(String u) async {
    u = u.trim();
    final now = this.now; // one frozen snapshot for the whole turn

    // ProvideSlot (§6.3): a paused turn is waiting for one missing slot. Treat this
    // input as the answer — unless the user backs out — then re-ask or dispatch.
    final pending = _pendingFill;
    if (pending != null) {
      _pendingFill = null; // consumed; re-set below if still incomplete
      if (_cancelRe.hasMatch(u) || _undoRe.hasMatch(u)) {
        _outSource = 'clarify';
        return 'Okay — never mind.';
      }
      final skillId = pending['skillId'] as String;
      final skill = skills[skillId];
      final slots = Map<String, dynamic>.from(pending['slots'] as Map);
      final missing = List<String>.from(pending['missing'] as List);
      slots[missing.first] = _coerceSlot(skill, missing.first, u, now);
      final stillMissing = _missingRequired(skill, slots);
      if (stillMissing.isNotEmpty) {
        _pendingFill = {'skillId': skillId, 'slots': slots, 'missing': stillMissing};
        _outSource = 'clarify';
        return _askForSlot(skill, stillMissing.first);
      }
      _outSource = 'provide-slot';
      _outSkill = skillId;
      return _dispatch(skillId, slots, 'corpus', now);
    }

    if (_undoRe.hasMatch(u)) {
      _outSource = 'undo';
      _lastTurnTemplate = null;
      _lastTurnWrote = false; // an undo is not itself a correctable route
      if (_journal.isEmpty) return 'Nothing to undo.';
      final entry = _journal.removeLast(); // walk back the ring, most-recent first
      _reverse(entry.before);
      // say WHAT was reversed — a silent "Undone." can't be trusted as the safety net
      return entry.desc == null ? 'Undone.' : 'Undone — reversed: "${entry.desc}"';
    }

    if (_helpRe.hasMatch(u)) {
      _outSource = 'help';
      return _helpText();
    }

    final corr = _corrRe.firstMatch(u);
    if (corr != null) {
      var pre = '';
      // §5.2 negative half: the previous turn misrouted — forget the LEARNED template
      // that routed it, whether it wrote or was read-only.
      if (_lastTurnTemplate != null && router.forget(_lastTurnTemplate!)) {
        repo.removeCorpusLearned(_lastTurnTemplate!);
      }
      // reverse the previous turn ONLY if it actually wrote — never an unrelated earlier write
      if (_lastTurnWrote && _journal.isNotEmpty) {
        _reverse(_journal.removeLast().before);
        pre = 'Got it — undid that. ';
      }
      _lastTurnTemplate = null;
      _lastTurnWrote = false;
      final redo = await _handle(corr.group(1)!.trim());
      _outSource = 'correction';
      return '$pre$redo';
    }

    final def = _defRe.firstMatch(u);
    if (def != null && router.route(u, clock: now) == null) {
      final desc = def.group(1)!;
      if (_harmfulRe.hasMatch('$desc $u')) {
        return "I can't build that — it could monitor someone without consent or cause harm, "
            "and I won't create tools for that.";
      }
      // Already ships? Point to it for free instead of authoring a duplicate (no cloud).
      if (!_thirdPartyRe.hasMatch(desc)) {
        for (final e in _builtinTrackers.entries) {
          if (RegExp(e.key, caseSensitive: false).hasMatch(desc)) {
            _outSource = 'builtin-tracker';
            return 'You can already track that — try "${e.value}". No need to build a new one.';
          }
        }
      }
      String? priorError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        final Map<String, dynamic>? authored;
        switch (await claude.authorCapability(desc, priorError: priorError)) {
          case CloudError(:final kind):
            _cloudStatus = kind.name;
            return "I couldn't build that — ${cloudReason(kind)}"; // the real reason, not a guess
          case CloudOk(:final value):
            _cloudStatus = 'ok';
            authored = value;
        }
        if (authored == null) return "I couldn't build that right now.";
        String? addedTypeId; // rollback removes ONLY a type we registered this attempt
        try {
          final type = (authored['type'] as Map).cast<String, dynamic>();
          final skill = (authored['skill'] as Map).cast<String, dynamic>();
          final typeId = type['typeId'], skillId = skill['skillId'];
          if (typeId is! String || skillId is! String) {
            throw ResolveError('authored capability is missing a string typeId/skillId');
          }
          if (!_idRe.hasMatch(typeId) || !_idRe.hasMatch(skillId)) {
            // model-controlled ids must never steer a file path or carry odd chars
            throw ResolveError('authored id must match [a-z0-9_-] (1-64 chars)');
          }
          if (types.containsKey(typeId) || skills.containsKey(skillId)) {
            // never overwrite a built-in / existing capability
            throw ResolveError('a capability like "$skillId" already exists — nothing built');
          }
          interp.validateType(type);
          types[typeId] = type;
          addedTypeId = typeId;
          interp.validateSkill(skill);
          skills[skillId] = skill;
          repo.writeDef('types', 'typeId', type);
          repo.writeDef('skills', 'skillId', skill);
          if (_retrievalEnabled) await router.buildRetrievalIndex(skills);
          _outSource = 'authored';
          final eg = (skill['examplePhrases'] as List?)?.cast<String>();
          return 'Built "${skill['displayName'] ?? skillId}" — a new capability, authored and validated.'
              '${eg != null && eg.isNotEmpty ? ' Try: "${eg.first}".' : ''}';
        } catch (e) {
          if (addedTypeId != null) types.remove(addedTypeId); // safe rollback
          priorError = e is ResolveError ? e.message : e.toString();
          if (attempt == 2) return 'I drafted that but it could not be validated — nothing was registered.';
        }
      }
    }

    var routed = router.route(u, clock: now);
    // Out-of-domain boundary (§7.2, G-19): a clearly-external question with NO personal
    // cue gets a graceful "not what I do" — BEFORE spending a residual cloud call. The
    // personal-cue guard is the privacy line: "what did I say about X" is never OOD.
    if (routed == null && _worldKnowledgeRe.hasMatch(u) && !_personalCueRe.hasMatch(u)) {
      final sg = await router.retrievalSuggest(u);
      if (sg == null || sg['confident'] != true) {
        _outSource = 'out-of-domain';
        return "That's outside what I can help with — I'm your assistant for reminders, people, "
            "tasks, notes, and moods, not general questions.";
      }
    }
    CloudErrorKind? cloudErr;
    if (routed == null) {
      switch (await claude.routeResidual(u, skills)) {
        case CloudOk(:final value):
          _cloudStatus = 'ok';
          routed = value; // may be null == the model abstained
        case CloudError(:final kind):
          _cloudStatus = kind.name;
          cloudErr = kind;
      }
    }
    if (routed == null) {
      // A miss is corpus + (abstain | cloud error | no cloud). If the cloud FAILED,
      // say so honestly instead of only blaming the phrasing (no silent degradation).
      final sg = await router.retrievalSuggest(u);
      final base = sg == null
          ? "I didn't catch that."
          : (() {
              final name = skills[sg['skillId']]!['displayName'];
              final s1 = (sg['s1'] as double).toStringAsFixed(2);
              return sg['confident'] == true
                  ? 'I don\'t have that phrasing learned — did you mean to "$name"? Say it a known way and I\'ll learn it.'
                  : 'I\'m not sure what you meant — closest is "$name" ($s1), below my confidence bar, so I won\'t guess.';
            })();
      return cloudErr == null ? base : '$base (I also couldn\'t check with the cloud: ${cloudReason(cloudErr)})';
    }
    _outSource = routed['source'] as String; // telemetry: corpus | cloud
    _outSkill = routed['skillId'] as String?;
    // normalize leaked sentinel slot values from any source before they reach a
    // resolver (a replayed/live "none" for an absent date would otherwise persist
    // as garbage; the crash it once caused is already handled in _asDate).
    (routed['slots'] as Map?)?.updateAll(
        (k, v) => (v is String && const {'none', 'null'}.contains(v.trim().toLowerCase())) ? null : v);
    // The corpus types its slots via the template; the cloud returns raw strings, so
    // normalize any date/datetime input the routed skill declares (Spec 03 §6.2).
    // A cloud "2026-07-08" for a datetime slot -> null (no midnight reminders); a raw
    // "tomorrow at 3pm" -> a real ISO datetime (no silently-dropped reminders).
    if (routed['source'] == 'cloud') {
      _normalizeTypedSlots(skills[routed['skillId']], routed['slots'] as Map<String, dynamic>, now);
    }
    final skillId = routed['skillId'] as String;
    final slots = (routed['slots'] as Map).cast<String, dynamic>();
    // ProvideSlot (§6.3): if a REQUIRED input the router couldn't fill is missing, pause
    // and ask for it (resumable next turn) instead of dispatching a half-filled skill.
    final missing = _missingRequired(skills[skillId], slots);
    if (missing.isNotEmpty) {
      _pendingFill = {'skillId': skillId, 'slots': slots, 'missing': missing};
      _outSource = 'clarify';
      return _askForSlot(skills[skillId], missing.first);
    }
    final template = routed['source'] == 'corpus' ? routed['template'] as String? : null;
    return _dispatch(skillId, slots, routed['source'] as String, now, template: template, utterance: u);
  }

  /// Resolve → execute → persist → journal → learn for a fully-slotted skill. Shared by
  /// the normal routing path and a completed ProvideSlot fill.
  Future<String> _dispatch(String skillId, Map<String, dynamic> slots, String source, DateTime now,
      {String? template, String? utterance}) async {
    try {
      final turnInterp = Interpreter(types, now); // per-turn clock (Spec 03 §4)
      final plan = turnInterp.resolve(skills[skillId]!, slots, store);
      final before = turnInterp.execute(plan, store);
      for (final w in plan.writes) {
        repo.persist(w);
      }
      for (final id in plan.deletes) {
        repo.remove(id);
      }
      // record the previous-turn state for a correction (every routed turn, write or read)
      _lastTurnWrote = plan.writes.isNotEmpty || plan.deletes.isNotEmpty;
      _lastTurnTemplate = (template != null && router.isLearned(template)) ? template : null;
      if (_lastTurnWrote) {
        _journal.add(_JournalEntry(before, plan.confirmation));
        if (_journal.length > _journalMax) _journal.removeAt(0);
      }
      if (source == 'cloud' && utterance != null) {
        final tmpl = router.learn(utterance, skillId, slots);
        if (tmpl != null) repo.appendCorpusLearned({'skillId': skillId, 'template': tmpl});
      }
      return plan.confirmation ?? 'Done.';
    } on ResolveError catch (e) {
      final opts = e.options;
      if (opts != null && opts.isNotEmpty) {
        // an ambiguity (G-12): ask which one instead of leaking a raw error string
        _outSource = 'clarify';
        final shown = opts.length <= 5 ? opts.join(', ') : '${opts.take(5).join(', ')}, …';
        return 'I know more than one match for that — $shown. Which one? (say the full name)';
      }
      return "I couldn't do that: ${e.message}";
    }
  }

  /// The required input slots a routed skill left null (candidates for ProvideSlot).
  List<String> _missingRequired(Map<String, dynamic>? skill, Map<String, dynamic> slots) {
    final inputs = skill?['inputs'] as List?;
    if (inputs == null) return const [];
    return [
      for (final i in inputs)
        if (i is Map && i['required'] == true && slots[i['name']] == null) i['name'] as String
    ];
  }

  String _askForSlot(Map<String, dynamic>? skill, String slotName) {
    final inputs = skill?['inputs'] as List?;
    final input = inputs?.cast<dynamic>().firstWhere((i) => i is Map && i['name'] == slotName, orElse: () => null);
    final prompt = input is Map ? input['prompt'] as String? : null;
    return prompt ?? "What's the $slotName?";
  }

  /// Resolve a slot answer through its declared type (date/datetime) so a ProvideSlot
  /// reply like "tomorrow at 5pm" becomes a real ISO value, like the corpus path.
  dynamic _coerceSlot(Map<String, dynamic>? skill, String slotName, String raw, DateTime now) {
    final inputs = skill?['inputs'] as List?;
    final input = inputs?.cast<dynamic>().firstWhere((i) => i is Map && i['name'] == slotName, orElse: () => null);
    final type = input is Map ? input['type'] : null;
    final r = raw.trim();
    if (type == 'datetime') return router.resolveDateTime(r, now);
    if (type == 'date') return router.resolveDate(r, now);
    return r;
  }
}
