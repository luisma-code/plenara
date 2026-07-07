/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'claude.dart';
import 'interpreter.dart';
import 'router.dart';
import 'storage_repository.dart';

final _undoRe = RegExp(r'^(undo|undo that|no,? take that back|scratch that)\.?$', caseSensitive: false);
final _corrRe = RegExp(r'^(?:no,?|actually,?|nope,?)\s+i meant (?:to |it was )?(.+?)\.?$', caseSensitive: false);
final _defRe = RegExp(
    r'^(?:start tracking|track|i want to track|i want to start tracking|make me a|create a) '
    r'(?:my |a |an )?(.+?)(?: tracker)?\.?$',
    caseSensitive: false);
// Layer-1 policy floor (Spec 02 §7.6): key on harmful FRAMING, never merely a
// sensitive topic. "track my kid's mood" (the flagship marquee) is fine; "track
// my kid secretly / without their knowledge" is not. Layers 2/3 (model + review)
// are v2.
final _harmfulRe = RegExp(
    // covert / non-consensual surveillance framing
    r"secretly|covertly|without (?:their|his|her|your) (?:knowledge|consent|permission)"
    r"|behind (?:their|his|her) back|\bspy on\b|\bstalk\b|keep tabs on|\bsnoop\b"
    // self-harm, weapons, disordered-eating framing
    r"|self.?harm|hurt (?:myself|someone|somebody)|make a weapon|build a weapon"
    r"|purge (?:after|my|food|meal)|hide (?:my )?(?:eating|calories)|restrict (?:my )?calories",
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
  static const _journalMax = 25; // ring depth
  final List<_JournalEntry> _journal = []; // execution journal of REVERSIBLE (write) turns
  // the immediately-previous routed turn (write OR read), so a correction targets
  // the right thing: forget its template, and reverse it ONLY if it actually wrote.
  String? _lastTurnTemplate;
  bool _lastTurnWrote = false;
  String _outSource = 'clarify'; // telemetry: how this turn resolved
  String? _outSkill;
  // Whether retrieval (the embed-server index) is active this session. Authoring
  // grows the inventory and must re-index — but only when retrieval is on, so the
  // authoring path stays hermetic under init(retrieval: false), like init() itself.
  bool _retrievalEnabled = true;

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart); [storage]
  /// lets them inject a repository (in-memory / test double). Production leaves both
  /// null -> a live ClaudeClient over a FileStorageRepository.
  Session(this.dataDir, {DateTime? clock, CloudClient? cloud, StorageRepository? storage})
      : _fixedClock = clock,
        _injectedCloud = cloud,
        _injectedStorage = storage;

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
  }

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
    String resp;
    try {
      resp = await _handle(u);
    } catch (e) {
      _outSource = 'error';
      resp = "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
    }
    // dogfood telemetry — measures clarify/cloud/correction rates in real use
    repo.logTurn({
      'at': DateTime.now().toIso8601String(),
      'utterance': u,
      'source': _outSource,
      if (_outSkill != null) 'skill': _outSkill,
    });
    return resp;
  }

  /// Process one utterance; returns the assistant's response text (may be multi-line).
  Future<String> _handle(String u) async {
    u = u.trim();
    final now = this.now; // one frozen snapshot for the whole turn
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
      String? priorError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        final authored = await claude.authorCapability(desc, priorError: priorError);
        if (authored == null) return "I couldn't build that right now (offline or no key).";
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
    routed ??= await claude.routeResidual(u, skills);
    if (routed == null) {
      final sg = await router.retrievalSuggest(u);
      if (sg == null) return "I didn't catch that.";
      final name = skills[sg['skillId']]!['displayName'];
      final s1 = (sg['s1'] as double).toStringAsFixed(2);
      return sg['confident'] == true
          ? 'I don\'t have that phrasing learned — did you mean to "$name"? Say it a known way and I\'ll learn it.'
          : 'I\'m not sure what you meant — closest is "$name" ($s1), below my confidence bar, so I won\'t guess.';
    }
    _outSource = routed['source'] as String; // telemetry: corpus | cloud
    _outSkill = routed['skillId'] as String?;
    // normalize leaked sentinel slot values from any source before they reach a
    // resolver (a replayed/live "none" for an absent date would otherwise persist
    // as garbage; the crash it once caused is already handled in _asDate).
    (routed['slots'] as Map?)?.updateAll(
        (k, v) => (v is String && const {'none', 'null'}.contains(v.trim().toLowerCase())) ? null : v);
    try {
      final turnInterp = Interpreter(types, now); // per-turn clock (Spec 03 §4)
      final plan = turnInterp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      final before = turnInterp.execute(plan, store);
      for (final w in plan.writes) {
        repo.persist(w);
      }
      for (final id in plan.deletes) {
        repo.remove(id);
      }
      // record the previous-turn state for a correction (every routed turn, write or read)
      _lastTurnWrote = plan.writes.isNotEmpty || plan.deletes.isNotEmpty;
      final tmpl = routed['source'] == 'corpus' ? routed['template'] as String? : null;
      _lastTurnTemplate = (tmpl != null && router.isLearned(tmpl)) ? tmpl : null;
      if (_lastTurnWrote) {
        _journal.add(_JournalEntry(before, plan.confirmation));
        if (_journal.length > _journalMax) _journal.removeAt(0);
      }
      if (routed['source'] == 'cloud') {
        final tmpl = router.learn(u, routed['skillId'] as String,
            (routed['slots'] as Map).cast<String, dynamic>());
        if (tmpl != null) {
          repo.appendCorpusLearned({'skillId': routed['skillId'], 'template': tmpl});
        }
      }
      return plan.confirmation ?? 'Done.';
    } on ResolveError catch (e) {
      return "Couldn't do that: ${e.message}";
    }
  }
}
