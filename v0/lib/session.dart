/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'claude.dart';
import 'generative.dart';
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
// Re-classification correction (F-14): "no, that was a walk" — the last log was the wrong
// TYPE; reverse it and re-log as the corrected activity, carrying the original slots.
final _reclassifyRe =
    RegExp(r'^(?:no,?|actually,?|nope,?|wait,?)\s+that was (?:a |an )?(\w+)\.?$', caseSensitive: false);
const _activitySkill = {
  'run': 'log-run', 'running': 'log-run', 'jog': 'log-run', 'jogging': 'log-run',
  'walk': 'log-walk', 'walking': 'log-walk',
};
const _workoutSkills = {'log-run', 'log-walk'};
// Same-record slot correction (F-15): "actually, 28 minutes" / "make it 3k" updates a field
// of the just-logged workout in place (not a reverse-redispatch).
final _durationCorrectRe =
    RegExp(r'^(?:actually,?|no,?|make it|it was)\s+(\d+(?:\.\d+)?)\s*(?:minutes|mins?|minute)\.?$', caseSensitive: false);
final _distanceCorrectRe =
    RegExp(r'^(?:actually,?|no,?|make it|it was)\s+(\d+(?:\.\d+)?)\s*k(?:m|ilometers?)?\.?$', caseSensitive: false);
// abandons a pending slot-fill dialogue (Spec 03 §6.3 ProvideSlot)
final _cancelRe = RegExp(r'^(cancel|never ?mind|forget it|nvm|stop|no thanks)\.?$', caseSensitive: false);
// confirms an authored-capability draft (Spec 02 §6.5: nothing registered until "activate")
final _activateRe = RegExp(r'^(activate|add it|yes,? add it|go ahead|do it|yes,? do it|yes)\.?$', caseSensitive: false);
// Scope-denial floor (DF-10 / DP-03 / DP-04): external-world actions Plenara can't perform —
// send a message, touch an external calendar, move money. A SCOPE refusal (not tier), it
// offers what it CAN do. Anchored so reminder/list phrasings ("remind me to text mom", "add
// buy milk to my list") never trip it.
final _scopeDenialRe = RegExp(
    r'^(text|message|email|e-mail|dm|whatsapp|imessage|slack|tweet|post) \w+'
    r'|(add|put) .+ (to|on) my (google |outlook |apple |work )?calendar'
    r'|^(pay|transfer|venmo|wire|refund) '
    r'|^send (money|\$|payment)'
    r'|^buy .+ for \w+'
    r'|^(order|purchase) .+ (online|on amazon|from amazon)'
    r'|^book (a |an )?(flight|hotel|table|appointment|reservation|cab|uber)',
    caseSensitive: false);
// Medical-conclusion guardrail (DP-06): a memory app holds health-adjacent logs but is not a
// clinician — it can show what's logged, never diagnose.
final _medicalRe = RegExp(
    r"what'?s wrong with me|\bdiagnose\b|do i have (a |an )?(cancer|arthritis|diabetes|covid|the flu|an infection|a tumou?r|a disease|adhd)"
    r"|is (this|it|that) (cancer|a tumou?r|serious|dangerous|an infection)|what medication should i (take|be on)"
    r"|based on my (meds|medications|symptoms).{0,40}(wrong|diagnos|have|serious)",
    caseSensitive: false);
// Impersonation refusal (DP-09): drafts in the USER's voice, never as a third party.
final _impersonateRe =
    RegExp(r"\b(pretend(ing)? to be|impersonat(e|ing)|speak as (my|his|her|their)|write as (my|his|her|their))\b", caseSensitive: false);
// Schema-edit denial (DF-03): adding a field to an EXISTING tracker is a paid authoring edit.
final _schemaEditRe =
    RegExp(r'\badd (a |an )?[\w-]+( [\w-]+)? (field|score|metric|column|attribute) to my \w+', caseSensitive: false);
// Record-integrity floor (locked principle #7 / DP-05): refuse to fabricate the past.
// Narrow, framing-keyed — a genuine backdated log ("I talked to Sam yesterday") is NOT
// this; only "pretend/fake/fabricate a <record>" framing. The general case is the
// deferred Layer-2 model gate (G-30); this catches the explicit asks.
final _fabricationRe = RegExp(
    r"\b(pretend (that |i )|make it look like|falsify|fabricate|"
    r"(log|add|create|make|record) (a |an |some )?fake|fake (a |an |some )?"
    r"(interaction|call|meeting|conversation|entry|record|note|log|visit|chat))\b",
    caseSensitive: false);
// Generative-request intents (Spec 04 §3.10) — paid, grounded synthesis.
final _giftRe = RegExp(
    r"^(?:(?:gift|present)\s+ideas?\s+for\s+|what\s+(?:should|can|could)\s+i\s+(?:get|buy|give)\s+|"
    r"what\s+to\s+(?:get|buy|give)\s+)(.+?)(?:\s+for\s+(?:his|her|their)\s+(?:birthday|present|gift))?\??$",
    caseSensitive: false);
final _briefingRe = RegExp(
    r"^(?:(?:give me |what'?s )?my (?:daily )?briefing|brief me|"
    r"what(?:'?s| does) my day look like|catch me up on my day)\??$",
    caseSensitive: false);
final _reconnectRe = RegExp(
    r"^(?:help me |how (?:do|can|should) i |ways to )?reconnect with (.+?)\??$"
    r"|^i(?:'ve| have)? lost touch with (.+?)\??$"
    r"|^i should (?:catch up with|reach out to) (.+?)\??$",
    caseSensitive: false);
final _weeklyReviewRe = RegExp(
    r"^(?:how was my week|weekly review|recap (?:of )?my week|"
    r"summar(?:ise|ize) my week|how did my week go|review my week)\??$",
    caseSensitive: false);
final _patternInsightRe = RegExp(
    r"^(?:(?:do you )?(?:notice|see) any patterns\??|any patterns\??|any insights\??|"
    r"what patterns do you see\??|surface a pattern\??|what have you noticed about me\??)$",
    caseSensitive: false);
final _draftMessageRe = RegExp(
    r"^(?:draft|write|compose|help me write) (?:a |an )?(?:message|note|text|reply) (?:to|for) (.+?)\??$",
    caseSensitive: false);
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
  late Map<String, Map<String, dynamic>> templates; // binary-shipped tracker templates (Spec 05 §6)
  late Map<String, Map<String, dynamic>> store;
  late Interpreter interp;
  late Router router;
  late CloudClient claude;
  late GenerativeService _generative;
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
  // The immediately-previous WRITING dispatch {skillId, slots}, so a re-classification
  // ("no, that was a walk", F-14) can re-log the corrected activity carrying the slots.
  Map<String, dynamic>? _lastDispatch;
  String _outSource = 'clarify'; // telemetry: how this turn resolved
  String? _outSkill;
  String? _cloudStatus; // telemetry: cloud health this turn ('ok' or a CloudErrorKind name)
  // Rich debug-trace fields (dogfood diagnosis: read the turnlog instead of retrying) —
  // reset each turn in handle(), populated as the turn resolves.
  String? _outTemplate; // the corpus template matched, if a corpus route
  Map<String, dynamic>? _outSlots; // the slots dispatched into the skill
  final List<Map<String, dynamic>> _outWrites = []; // record ops this turn: {op,id,typeId}
  String? _outError; // exception type + message + stack, on the error path (never shown to the user)
  // A paused turn waiting for the user to supply a missing required slot (Spec 03
  // §6.3 ProvideSlot): {skillId, slots (partial), missing (remaining required names)}.
  // The next turn's input fills it and the completed skill dispatches.
  Map<String, dynamic>? _pendingFill;
  // A validated-but-UNREGISTERED authored capability awaiting the user's "activate"
  // (Spec 02 §6.5 / G-18): {type, skill, typeId, skillId, displayName, examples}.
  Map<String, dynamic>? _pendingActivation;
  String? _pendingAuthorOffer; // DF-01: a "start tracking X" awaiting a yes before paid authoring
  // Whether retrieval (the embed-server index) is active this session. Authoring
  // grows the inventory and must re-index — but only when retrieval is on, so the
  // authoring path stays hermetic under init(retrieval: false), like init() itself.
  bool _retrievalEnabled = true;

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart); [storage]
  /// lets them inject a repository (in-memory / test double). Production leaves both
  /// null -> a live ClaudeClient over a FileStorageRepository.
  Session(this.dataDir,
      {DateTime? clock,
      CloudClient? cloud,
      StorageRepository? storage,
      NotificationScheduler? scheduler,
      String? deviceDir})
      : _fixedClock = clock,
        _injectedCloud = cloud,
        _injectedStorage = storage,
        _scheduler = scheduler,
        _deviceDir = deviceDir;

  /// A device-local (non-synced) dir for the deviceId + turnlog; the app injects
  /// `~/.plenara`, tests/CLI leave it null (-> [dataDir]). See FileStorageRepository.
  final String? _deviceDir;

  /// Files that failed to load (corrupt / half-synced), surfaced for repair rather than
  /// silently dropped (P2.8). Populated during [init]; empty unless a FileStorageRepository
  /// backed the load.
  List<String> get corruptFiles {
    final r = repo;
    return r is FileStorageRepository ? r.corruptFiles : const <String>[];
  }

  /// [retrieval] builds the embedding index (needs the embed server, ~2s per anchor
  /// when it's DOWN — so the app defaults it OFF). Tests pass false to stay hermetic.
  /// [onPhase] receives a line at the start/end of each init phase — the app writes
  /// these to its diagnostics log, so a startup HANG shows the last phase that began.
  Future<void> init({bool retrieval = true, void Function(String msg)? onPhase}) async {
    final sw = Stopwatch()..start();
    void phase(String msg) => onPhase?.call('init: $msg (+${sw.elapsedMilliseconds}ms)');
    phase('start');
    repo = _injectedStorage ?? FileStorageRepository(dataDir, deviceDir: _deviceDir);
    types = repo.loadDefs('types', 'typeId');
    skills = repo.loadDefs('skills', 'skillId');
    templates = repo.loadDefs('templates', 'templateId');
    store = repo.loadRecords();
    phase('loaded ${types.length} types, ${skills.length} skills, ${store.length} records');
    final r = repo;
    if (r is FileStorageRepository && r.corruptFiles.isNotEmpty) {
      // P2.8: never drop a bad file on the floor — surface it in diagnostics for repair.
      phase('WARNING: skipped ${r.corruptFiles.length} unreadable file(s), surfaced for repair: ${r.corruptFiles.join(', ')}');
    }
    interp = Interpreter(types, now);
    router = Router.load('$dataDir/corpus.json', now, learnedPath: '$dataDir/corpus-learned.json');
    claude = _injectedCloud ?? ClaudeClient();
    _generative = GenerativeService(claude);
    for (final s in skills.values) {
      interp.validateSkill(s);
    }
    phase('validated skills');
    _retrievalEnabled = retrieval;
    if (retrieval) {
      phase('building retrieval index (embed server — may hang if it is down)…');
      await router.buildRetrievalIndex(skills);
      phase('retrieval index built');
    } else {
      phase('retrieval disabled');
    }
    await _reconcileReminders(); // arm any future reminders already on disk (re-open)
    phase('reminders reconciled — READY');
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
        '• Reminders — "remind me to call mom on thursday at 5pm", "remind me every day at 9am to take my meds", "what are my reminders", "snooze the reminder to X to friday at 9am", "cancel the reminder to X"',
      if (has('log-run'))
        '• Running — "log a 3k run", "how much have I run this week", "how far have I run", "what\'s my running streak"',
      if (has('log-mood')) '• Mood — "I\'m feeling great", "how have I been feeling"',
      if (has('log-journal')) '• Journal — "journal that today was a good day", "read my journal"',
      if (has('remember-person-fact'))
        '• People — "remember that Mia is Sarah\'s daughter", "what do I know about Mia", "talked to Sam about the trip", "when did I last talk to Sam"',
      if (has('set-birthday'))
        '• Birthdays — "Sarah\'s birthday is july 16", "whose birthday is coming up"',
      if (has('set-alias')) '• Nicknames — "Sarah\'s nickname is Mum", then "when did I last talk to Mum"',
      '• Ideas & briefings (needs a connection) — "gift ideas for Sarah", "help me reconnect with Sam", "give me my briefing"',
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
    _outTemplate = null;
    _outSlots = null;
    _outWrites.clear();
    _outError = null;
    final startedAt = DateTime.now();
    String resp;
    try {
      resp = await _handle(u);
    } catch (e, st) {
      _outSource = 'error';
      _outError = '${e.runtimeType}: $e\n$st'; // full detail to the trace, never to the user
      resp = "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
    }
    // the turn may have added/undone/completed a reminder — keep the OS armed set
    // in sync with the (now-updated) store. Derived, so no per-skill wiring needed.
    await _reconcileReminders();
    // Rich per-turn trace (dogfood): summary telemetry (clarify/cloud/correction rates) PLUS
    // enough to DIAGNOSE a bad turn from the log alone — route path, matched template,
    // extracted slots, records written/deleted, the response, and any error + stack.
    repo.logTurn({
      'at': startedAt.toIso8601String(),
      'ms': DateTime.now().difference(startedAt).inMilliseconds,
      'utterance': u,
      'source': _outSource,
      if (_outSkill != null) 'skill': _outSkill,
      if (_outTemplate != null) 'template': _outTemplate,
      if (_outSlots != null && _outSlots!.isNotEmpty) 'slots': _outSlots,
      if (_cloudStatus != null) 'cloud': _cloudStatus,
      if (_outWrites.isNotEmpty) 'writes': _outWrites,
      'response': resp.length > 240 ? '${resp.substring(0, 240)}…' : resp,
      if (_outError != null) 'error': _outError,
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

    // Snapshot the PREVIOUS turn's write-outcome (for undo/correction), then default THIS
    // turn to "wrote nothing" — only _dispatch upgrades it. Without this, a stale flag
    // left by an early-return path (a clarify miss, a generative reply, an authoring turn)
    // would make a later correction reverse an UNRELATED earlier write (data loss).
    final prevWrote = _lastTurnWrote;
    final prevTemplate = _lastTurnTemplate;
    final prevDispatch = _lastDispatch;
    _lastTurnWrote = false;
    _lastTurnTemplate = null;
    _lastDispatch = null;

    // ProvideSlot (§6.3): a paused turn is waiting for one missing slot. Treat this
    // input as the answer — unless the user backs out — then re-ask or dispatch.
    final pending = _pendingFill;
    if (pending != null) {
      if (_cancelRe.hasMatch(u)) {
        _pendingFill = null;
        _outSource = 'clarify';
        return 'Okay — never mind.';
      }
      // A system command interrupts the slot-fill and is handled normally below, rather
      // than being swallowed as the slot answer ("help"/"undo"/"no, I meant …" mid-fill).
      final isSystemCmd =
          _undoRe.hasMatch(u) || _helpRe.hasMatch(u) || _corrRe.hasMatch(u) || _fabricationRe.hasMatch(u);
      if (!isSystemCmd) {
        _pendingFill = null; // consumed; re-set below if still incomplete
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
      _pendingFill = null; // interrupted by a system command — fall through to handle it
    }

    // Authoring activation (§6.5 / G-18): a validated draft is waiting. "activate" commits
    // it; "never mind" discards it; anything else abandons the draft and is handled normally
    // (nothing was registered while it sat pending).
    final draft = _pendingActivation;
    if (draft != null) {
      if (_activateRe.hasMatch(u)) {
        _pendingActivation = null;
        return _activateCapability(draft);
      }
      if (_cancelRe.hasMatch(u)) {
        _pendingActivation = null;
        _outSource = 'clarify';
        return "Okay — I won't add that.";
      }
      _pendingActivation = null; // moved on — drop the draft, handle this input normally
    }

    // Authoring OFFER (DF-01): a "start tracking X" with no built-in tracker and no template
    // was offered a paid custom build. A yes spends the cloud call; a decline drops it; any
    // other input abandons the offer and is handled normally (nothing was built).
    final offer = _pendingAuthorOffer;
    if (offer != null) {
      _pendingAuthorOffer = null;
      if (_activateRe.hasMatch(u)) {
        return _authorAndPreview(offer, now);
      }
      if (_cancelRe.hasMatch(u)) {
        _outSource = 'clarify';
        return "No problem — I won't build one.";
      }
      // else: fall through and handle this new input normally
    }

    // record-integrity floor: never fabricate history (DP-05, locked principle #7)
    if (_fabricationRe.hasMatch(u)) {
      _outSource = 'refused';
      return "I won't record things that didn't happen — I can only log what's real.";
    }

    // scope floor: external-world actions are outside what a personal-memory app does (DF-10,
    // DP-03/04). A scope refusal that offers the in-scope alternative.
    if (_scopeDenialRe.hasMatch(u)) {
      _outSource = 'out-of-scope';
      return "I can't do that directly — I'm your personal memory assistant, not connected to "
          "messaging, calendars, or payments. I can set a reminder or make a note about it, though.";
    }

    // medical guardrail (DP-06): show logs, never diagnose.
    if (_medicalRe.hasMatch(u)) {
      _outSource = 'refused';
      return "I'm not a medical device — I can show what you've logged and surface patterns, but "
          "I can't diagnose or give medical advice. Please talk to a doctor about this.";
    }
    // impersonation refusal (DP-09): the user's own voice only.
    if (_impersonateRe.hasMatch(u)) {
      _outSource = 'refused';
      return "I'll help you write in your OWN voice, but I won't impersonate someone else or put "
          "words in their mouth.";
    }
    // schema-edit denial (DF-03): editing a live tracker's fields is a paid customization.
    if (_schemaEditRe.hasMatch(u)) {
      _outSource = 'refused';
      return "Adding a field to an existing tracker is a schema edit — that's a paid customization. "
          "(Choosing fields when you first set up a tracker is free.)";
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

    // Re-classification (F-14): "no, that was a walk" reverses the last (mis-typed) workout
    // log and re-logs it as the corrected activity, carrying the original slots (distance).
    final recl = _reclassifyRe.firstMatch(u);
    if (recl != null && prevWrote && prevDispatch != null && _journal.isNotEmpty) {
      final prevSkill = prevDispatch['skillId'] as String;
      final target = _activitySkill[recl.group(1)!.toLowerCase()];
      if (target != null && _workoutSkills.contains(prevSkill) && target != prevSkill) {
        _reverse(_journal.removeLast().before); // undo the wrong-activity workout
        final redo = await _dispatch(target, Map<String, dynamic>.from(prevDispatch['slots'] as Map), 'corpus', now);
        _outSource = 'correction';
        return 'Fixed that — $redo';
      }
    }

    // Same-record slot correction (F-15): "actually, 28 minutes" / "make it 3k" updates a
    // field of the just-logged workout IN PLACE (distinguished from F-14: same record, not a
    // reverse-redispatch), journaled so undo restores the prior value.
    if (prevWrote && prevDispatch != null && _workoutSkills.contains(prevDispatch['skillId'])) {
      final dm = _durationCorrectRe.firstMatch(u);
      final km = _distanceCorrectRe.firstMatch(u);
      final id = prevDispatch['writtenId'] as String?;
      if ((dm != null || km != null) && id != null && store.containsKey(id)) {
        final field = dm != null ? 'duration' : 'distance';
        final value = num.tryParse((dm ?? km)!.group(1)!);
        if (value != null) {
          final rec = store[id]!;
          _journal.add(_JournalEntry({id: Map<String, dynamic>.from(rec)}, 'updated $field'));
          if (_journal.length > _journalMax) _journal.removeAt(0);
          rec[field] = value;
          repo.persist(rec);
          _lastTurnWrote = true;
          _lastDispatch = prevDispatch; // keep context so a further correction chains
          _outSource = 'correction';
          return 'Updated — that ${rec['activity']} was $value ${field == 'duration' ? 'minutes' : 'km'}.';
        }
      }
    }

    final corr = _corrRe.firstMatch(u);
    if (corr != null) {
      var pre = '';
      // §5.2 negative half: the previous turn misrouted — forget the LEARNED template
      // that routed it, whether it wrote or was read-only. (prev* = the PRIOR turn's
      // outcome, snapshotted at the top before this turn reset the live flags.)
      if (prevTemplate != null && router.forget(prevTemplate)) {
        repo.removeCorpusLearned(prevTemplate);
      }
      // reverse the previous turn ONLY if it actually wrote — never an unrelated earlier write
      if (prevWrote && _journal.isNotEmpty) {
        _reverse(_journal.removeLast().before);
        pre = 'Got it — undid that. ';
      }
      final redo = await _handle(corr.group(1)!.trim());
      _outSource = 'correction';
      return '$pre$redo';
    }

    // Generative requests (§3.10): grounded, paid synthesis over the user's own records.
    final gift = _giftRe.firstMatch(u);
    if (gift != null) {
      _outSource = 'generative';
      _outSkill = 'gift_ideas';
      return _generative.giftIdeas(gift.group(1)!.trim(), store, now);
    }
    if (_briefingRe.hasMatch(u)) {
      _outSource = 'generative';
      _outSkill = 'briefing';
      return _generative.briefing(store, now);
    }
    final reconnect = _reconnectRe.firstMatch(u);
    if (reconnect != null) {
      _outSource = 'generative';
      _outSkill = 'reconnect';
      final who = reconnect.group(1) ?? reconnect.group(2) ?? reconnect.group(3) ?? '';
      return _generative.reconnect(who.trim(), store, now);
    }
    if (_weeklyReviewRe.hasMatch(u)) {
      _outSource = 'generative';
      _outSkill = 'weekly_review';
      return _generative.weeklyReview(store, now);
    }
    if (_patternInsightRe.hasMatch(u)) {
      _outSource = 'generative';
      _outSkill = 'pattern_insight';
      return _generative.patternInsight(store, now);
    }
    final draftMsg = _draftMessageRe.firstMatch(u);
    if (draftMsg != null) {
      _outSource = 'generative';
      _outSkill = 'draft_message';
      return _generative.draftMessage(draftMsg.group(1)!.trim(), store, now);
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
        // A binary-shipped template? Instantiate it FREE (no cloud), before paid authoring.
        final instantiated = await _tryInstantiateTemplate(desc, now);
        if (instantiated != null) return instantiated;
      }
      // DF-01: no built-in tracker, no template -> OFFER a paid custom build; don't spend the
      // authoring cloud call until the user says yes (Spec 08 per-invocation paid consent).
      _pendingAuthorOffer = desc;
      _outSource = 'author-offer';
      return "I don't have a built-in tracker for that yet. I can build you a custom one — "
          "that uses your Claude credits (a paid step). Want me to go ahead?";
    }

    var routed = router.route(u, clock: now);
    // Compound utterance (F-13): two independent commands joined by "and" — "log a run
    // and journal that I feel great" — execute BOTH and compose the confirmations.
    // Deliberately conservative, because MANY single commands contain "and" ("remind me
    // to buy milk and eggs", "talked to Sam and Jo about X"): only attempted when the
    // WHOLE utterance did not route (a whole-utterance corpus match always wins), and
    // only when BOTH halves independently route offline with no missing required slots —
    // so a failed split has zero side effects and falls through to the normal miss path.
    if (routed == null) {
      final parts = _splitCompound(u, now);
      if (parts != null) {
        final replies = <String>[];
        for (final p in parts) {
          final slots = (p['slots'] as Map).cast<String, dynamic>();
          slots.updateAll(
              (k, v) => (v is String && const {'none', 'null'}.contains(v.trim().toLowerCase())) ? null : v);
          replies.add(await _dispatch(p['skillId'] as String, slots, 'corpus', now,
              template: p['template'] as String?));
        }
        _outSource = 'compound'; // telemetry: one turn, two dispatches
        _outSkill = parts.map((p) => p['skillId']).join('+');
        return replies.join(' ');
      }
    }
    // Out-of-domain boundary (§7.2, G-19): a clearly-external question with NO personal
    // cue gets a graceful "not what I do" — BEFORE spending a residual cloud call. The
    // personal-cue guard is the privacy line: "what did I say about X" is never OOD.
    if (routed == null &&
        _worldKnowledgeRe.hasMatch(u) &&
        !_personalCueRe.hasMatch(u) &&
        !_mentionsKnownContact(u)) {
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
    _outSkill = skillId; // debug trace
    _outSlots = slots;
    _outTemplate = template;
    try {
      final turnInterp = Interpreter(types, now); // per-turn clock (Spec 03 §4)
      final plan = turnInterp.resolve(skills[skillId]!, slots, store);
      final before = turnInterp.execute(plan, store);
      for (final w in plan.writes) {
        repo.persist(w);
        _outWrites.add({'op': 'write', 'id': w['id'], 'typeId': w['typeId']}); // debug trace
      }
      for (final id in plan.deletes) {
        repo.remove(id);
        _outWrites.add({'op': 'delete', 'id': id}); // debug trace
      }
      // record the previous-turn state for a correction (every routed turn, write or read)
      _lastTurnWrote = plan.writes.isNotEmpty || plan.deletes.isNotEmpty;
      _lastTurnTemplate = (template != null && router.isLearned(template)) ? template : null;
      if (_lastTurnWrote) {
        // for re-classify (F-14) + same-record slot correction (F-15)
        _lastDispatch = {
          'skillId': skillId, 'slots': slots,
          if (plan.writes.isNotEmpty) 'writtenId': plan.writes.first['id'],
        };
      }
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

  /// F-13 compound-utterance split: find the FIRST " and " (or ", and ") seam where
  /// both sides independently route through the corpus router into fully-slotted
  /// skills. Returns the two routed halves ({skillId, slots, template} each) or null
  /// if no seam qualifies — in which case the utterance is handled as ONE command.
  /// Pure detection: no dispatch, no writes, so declining to split costs nothing.
  /// Only called after the whole utterance failed to route, which is what keeps
  /// "remind me to buy milk and eggs" (one command containing "and") unsplit.
  /// A half that routes but is missing a required slot disqualifies the seam — a
  /// mid-compound ProvideSlot pause can't be composed into one confirmation.
  List<Map<String, dynamic>>? _splitCompound(String u, DateTime now) {
    for (final m in RegExp(r',?\s+and\s+', caseSensitive: false).allMatches(u)) {
      final left = u.substring(0, m.start).trim();
      final right = u.substring(m.end).trim();
      if (left.isEmpty || right.isEmpty) continue;
      final lr = router.route(left, clock: now);
      if (lr == null) continue;
      final rr = router.route(right, clock: now);
      if (rr == null) continue;
      if (_missingRequired(skills[lr['skillId']], (lr['slots'] as Map).cast<String, dynamic>()).isNotEmpty ||
          _missingRequired(skills[rr['skillId']], (rr['slots'] as Map).cast<String, dynamic>()).isNotEmpty) {
        continue;
      }
      return [lr, rr];
    }
    return null;
  }

  /// Does the utterance name a contact we actually store (by displayName or alias)?
  /// Used to keep a records question ("who is Mia?") from being classified out-of-domain
  /// and handed outward — the G-19 privacy boundary (a stored-person query stays in-domain).
  bool _mentionsKnownContact(String u) {
    final lu = u.toLowerCase();
    bool wordHit(String s) => s.isNotEmpty && RegExp('\\b${RegExp.escape(s)}\\b').hasMatch(lu);
    for (final r in store.values) {
      if (r['typeId'] != 'contact') continue;
      if (wordHit((r['displayName'] as String?)?.toLowerCase() ?? '')) return true;
      final a = r['aliases'];
      if (a is String) {
        for (final al in a.toLowerCase().split(',')) {
          if (wordHit(al.trim())) return true;
        }
      }
    }
    return false;
  }

  /// Instantiate a binary-shipped tracker template (Spec 05 §6 E4 / G-22) — FREE, immediate,
  /// no cloud: register its type(s) + skill(s), persist them, and inject its bundled corpus
  /// so the new tracker works by voice right away. Returns the confirmation, or null if no
  /// template matches [desc] (→ falls through to paid authoring).
  /// The paid authoring path (§6.5 / G-18): author the capability via the cloud, validate it
  /// WITHOUT committing, and stage it as a pending activation. Reached ONLY after the DF-01
  /// offer is accepted, so the cloud call is never spent on an unrequested build.
  Future<String> _authorAndPreview(String desc, DateTime now) async {
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
      String? tempType; // temporarily registered so validateSkill sees the type; rolled back
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
        // Validate WITHOUT committing (§6.5 / G-18): temporarily register the type so
        // validateSkill can resolve it, then roll it back — nothing is registered until
        // the user says "activate".
        interp.validateType(type);
        types[typeId] = type;
        tempType = typeId;
        interp.validateSkill(skill);
        types.remove(tempType);
        tempType = null;
        final eg = (skill['examplePhrases'] as List?)?.cast<String>() ?? const <String>[];
        _pendingActivation = {
          'type': type, 'skill': skill, 'typeId': typeId, 'skillId': skillId,
          'displayName': skill['displayName'] ?? skillId, 'examples': eg,
        };
        _outSource = 'authoring-preview';
        return 'I can build "${skill['displayName'] ?? skillId}" for you'
            '${eg.isNotEmpty ? ' — you\'d be able to say things like "${eg.first}"' : ''}. '
            'Say "activate" to add it, or "never mind" to skip.';
      } catch (e) {
        if (tempType != null) types.remove(tempType); // safe rollback
        priorError = e is ResolveError ? e.message : e.toString();
        if (attempt == 2) return 'I drafted that but it could not be validated — nothing was registered.';
      }
    }
    return "I couldn't build that right now."; // loop always returns; satisfies the analyzer
  }

  Future<String?> _tryInstantiateTemplate(String desc, DateTime now) async {
    final d = desc.toLowerCase();
    for (final t in templates.values) {
      final keywords = (t['keywords'] as List?)?.cast<String>() ?? const <String>[];
      if (!keywords.any((k) => d.contains(k.toLowerCase()))) continue;
      final skillDefs = (t['skills'] as List).map((s) => (s as Map).cast<String, dynamic>()).toList();
      final eg = t['example']?.toString() ?? 'logging one';
      _outSource = 'template';
      if (skillDefs.any((s) => skills.containsKey(s['skillId']))) {
        return 'You\'re already tracking that — try "$eg".';
      }
      try {
        for (final ty in (t['types'] as List)) {
          final type = (ty as Map).cast<String, dynamic>();
          interp.validateType(type);
          types[type['typeId'] as String] = type;
          repo.writeDef('types', 'typeId', type);
        }
        for (final skill in skillDefs) {
          interp.validateSkill(skill);
          skills[skill['skillId'] as String] = skill;
          repo.writeDef('skills', 'skillId', skill);
        }
        for (final c in (t['corpus'] as List)) {
          final sid = (c as Map)['skillId'] as String, tmpl = c['template'] as String;
          router.addLearned(sid, tmpl);
          repo.appendCorpusLearned({'skillId': sid, 'template': tmpl});
        }
        if (_retrievalEnabled) await router.buildRetrievalIndex(skills);
        return 'Set up ${t['displayName'] ?? t['templateId']} — it\'s ready. Try "$eg".';
      } catch (e) {
        return "I couldn't set that up: ${e is ResolveError ? e.message : e}";
      }
    }
    return null;
  }

  /// Commit a validated authored-capability draft (Spec 02 §6.5 "activate"): register the
  /// type + skill, persist them, refresh retrieval. Re-checks collisions since state may
  /// have changed while the draft sat pending.
  Future<String> _activateCapability(Map<String, dynamic> draft) async {
    final type = (draft['type'] as Map).cast<String, dynamic>();
    final skill = (draft['skill'] as Map).cast<String, dynamic>();
    final typeId = draft['typeId'] as String;
    final skillId = draft['skillId'] as String;
    _outSource = 'authored';
    if (types.containsKey(typeId) || skills.containsKey(skillId)) {
      return 'A capability like "$skillId" already exists now — nothing added.';
    }
    try {
      interp.validateType(type);
      types[typeId] = type;
      interp.validateSkill(skill);
      skills[skillId] = skill;
      repo.writeDef('types', 'typeId', type);
      repo.writeDef('skills', 'skillId', skill);
      if (_retrievalEnabled) await router.buildRetrievalIndex(skills);
      final eg = (draft['examples'] as List).cast<String>();
      return 'Added "${draft['displayName']}".${eg.isNotEmpty ? ' Try: "${eg.first}".' : ''}';
    } catch (e) {
      types.remove(typeId); // rollback — never leave a half-registered capability
      return "I couldn't add that after all: ${e is ResolveError ? e.message : e}";
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
