/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'automations.dart';
import 'claude.dart';
import 'content_search.dart';
import 'reference.dart';
import 'generative.dart';
import 'interpreter.dart';
import 'migration.dart';
import 'people.dart';
import 'reminders.dart';
import 'router.dart';
import 'storage_repository.dart';

final _undoRe = RegExp(
    r"^(?:(?:no,?|never ?mind,?|wait,?|actually,?)\s+)?(?:(?:can|could|will) you\s+)?(?:please\s+)?(?:undo|revert|take (?:that|it) back|scratch that|roll (?:that|it) back)(?:\s+(?:that|it|this|please|(?:the|my|that) last (?:one|thing|entry|log)))?[.!]?$",
    caseSensitive: false);
// Discoverability (Spec 03 §6.3): a clarify dead-ends without "here's what I can do".
// A DSL skill can't introspect the skill registry, so this is a Session-level surface.
final _helpRe = RegExp(
    r"^(?:help|help me|what (?:can|do) you do|what else can you do|what can i (?:say|do|ask)(?: you)?|what (?:are|do) (?:your|you have for) (?:skills|capabilities|commands|features)|what are (?:my|the) options|what (?:commands|features) (?:do you have|are there|can i use)|show me (?:what you can do|the commands|your skills)|list (?:your )?(?:commands|skills|capabilities)|how do i use (?:this|you|it|the app)|how does this (?:app )?work|what (?:can|does) (?:this|the) app do|what can plenara do|give me (?:some )?examples|what should i say|i don'?t know what to (?:say|do|ask)(?: you)?)\??$",
    caseSensitive: false);
// Domain-scoped help (queries gap): captures the TOPIC of a help request so we can answer
// "what can you do with reminders" / "how do I track water" with just that area's examples.
// Only help-shaped stems match; the captured topic is validated against known domains before
// it wins, so "tell me about Sarah"-style phrasings never reach this.
final _helpTopicRe = RegExp(
    r"^(?:what can (?:you|i) do with|what can i do (?:for|about)|how (?:do|can|would) i (?:use|track|log|manage|handle)|how do(?:es)?|help (?:me )?with|what are my options for)\s+(?:my |the )?(.+?)(?:\s+work)?\??$",
    caseSensitive: false);
// ---- The Tour (Fable's capability-discovery design) — a guided, conversational answer to "what
// can you do?" instead of a bullet dump. A closed vocabulary + a one-slot state machine; zero LLM.
// Each chapter is a TERRITORY (not a skill): essence + one example + an invitation to try it live.
class _TourChapter {
  final String id;
  final List<String> gate; // shown only if ALL these skills are registered
  final String essence; // the one/two-sentence spoken intro
  final String tryLine; // the single "you could say" example
  final String followOn; // the invitation (names the next chapter)
  final String coda; // appended after a live, in-domain try (teach-by-doing)
  final List<String> domainKeywords; // a dispatched skill id containing one of these = "tried this"
  final List<String> aliases; // selection words ("tell me about reminders")
  const _TourChapter(this.id, this.gate, this.essence, this.tryLine, this.followOn, this.coda,
      this.domainKeywords, this.aliases);
}

// Curated order: reminders → tasks → people → tracking. Journal/mood/birthdays fold into essences.
const _tourChapters = <_TourChapter>[
  _TourChapter(
    'reminders',
    ['set-reminder'],
    "Reminders are one sentence: what, and when — once or repeating. I'll speak up when it's time.",
    'You could say — "remind me to water the plants tomorrow at eight."',
    'Go ahead, try one of your own — or say "next" and I\'ll show you tasks.',
    "And that's the whole trick: say it, it's done. Say \"undo that\" if you were only playing.",
    ['remind'],
    ['reminder', 'reminders', 'remind'],
  ),
  _TourChapter(
    'tasks',
    ['create-task'],
    'Tasks are your running to-do list — add things, and I keep them until they\'re done.',
    'You could say — "add call the plumber to my list."',
    'Try adding one — or say "next" for the people you care about.',
    "That's it — one sentence and it's on the list. \"Undo that\" takes it back off.",
    ['task'],
    ['task', 'tasks', 'todo', 'todos', 'to-do', 'to-dos'],
  ),
  _TourChapter(
    'people',
    ['remember-person-fact'],
    'This is the part I care about most. Tell me facts about your people and I\'ll hold them — who\'s related to whom, what you talked about, when birthdays land.',
    'You could say — "remember that Mia is Sarah\'s daughter."',
    'Later you\'d just ask "what do I know about Mia." Want to try one, or hear about tracking?',
    "Now it's yours to ask back anytime. \"Undo that\" forgets it again.",
    ['person', 'contact', 'interaction', 'relation', 'fact', 'birthday', 'alias'],
    ['people', 'person', 'contact', 'contacts', 'friend', 'friends', 'relationship', 'relationships'],
  ),
  _TourChapter(
    'tracking',
    ['log-run'],
    "I come with runs, moods, meals, and a journal — and if I don't track something yet, say \"start tracking my water intake\" and I'll build it.",
    'You could say — "log a 3k run."',
    'That one\'s free to try — I\'ll undo it after if you like. Or say "next" for one last thing: how to read me.',
    "Logged — and I'll total it up whenever you ask. \"Undo that\" clears it.",
    ['run', 'walk', 'mood', 'journal', 'meal', 'goal', 'streak', 'track', 'water', 'step'],
    ['track', 'tracking', 'run', 'running', 'mood', 'journal', 'habit', 'habits'],
  ),
  // The presence itself — no skill to gate on, no live "try". The UI stages a colour demo while this
  // is spoken (drives idle→listening→thinking→the cooler AI shade). Kept LAST: a capstone that
  // explains the colours the user has been watching, and lands the cost/Settings note after they've
  // seen the features. Excluded from the opener's "pick a territory" menu (it isn't a "remember" one).
  _TourChapter(
    'colors',
    [],
    'One more thing — my colours. Warm amber is me at rest. I brighten, and cool a little, while I\'m '
        'listening or working something out. And when I reach out to the AI for the harder things, I '
        'shift to a cooler, bluer shade — I keep those moments as few as I can to save you money, and '
        'you can see every one, and what it cost, in Settings.',
    'Nothing to say here — just watch me for a moment.',
    'That\'s the whole of me. Say "done" whenever you like, or "next" to wrap up.',
    "", // no coda — there's no in-domain write to teach
    [], // no domain keywords — this chapter has no live try
    ['color', 'colors', 'colour', 'colours'],
  ),
];
// Advance / start the tour ("next", "give me the tour").
final _tourNextRe = RegExp(
    r"^(?:(?:give me |show me |start |take me on )?(?:the )?tour|next|another(?: one)?|more|go on|keep going|what else|surprise me)[.!]?$",
    caseSensitive: false);
// Done with the tour (in addition to the shared _cancelRe family).
final _tourDoneRe = RegExp(
    r"^(?:done|that'?s (?:enough|it|plenty|great)|i'?m good|got it|thanks|no more|enough)[.!]?$",
    caseSensitive: false);
// The user wants the exhaustive list, not the guided tour.
final _tourMapRe = RegExp(
    r"^(?:show me everything|everything|the (?:full|whole) (?:list|map|thing)|list (?:it|them|everything)(?: all)?|all of (?:it|them)|the whole list)[.!]?$",
    caseSensitive: false);

// Correction (§3.3): a natural prefix + "I meant …" reverses the last turn and re-routes.
// The "I meant" anchor is deliberate — a bare "no, X" is too easily a non-correction, and
// reversing a good write on a false positive is the worse failure.
final _corrRe = RegExp(
    r"^(?:(?:no,?|nope,?|actually,?|no wait,?|wait,?|sorry,?|oops,?|whoops,?|hang on,?|hold on,?|my bad,?|my mistake,?)\s+)?(?:i meant(?: to say)?|i actually meant|correction[:,]?|that'?s wrong[,:]?\s*i meant)\s+(?:to |it was |that )?(.+?)\.?$",
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
final _durationCorrectRe = RegExp(
    r"^(?:actually,?|no,?|nope,?|wait,?|sorry,?|make (?:it|that)|change (?:it|that) to|it was|that was|(?:it|that) should (?:be|have been)|should be|correction[:,]?)\s+(?:that was |it was |it'?s |more like )?(\d+(?:\.\d+)?)\s*(?:minutes?|mins?)\.?$",
    caseSensitive: false);
final _distanceCorrectRe = RegExp(
    r"^(?:actually,?|no,?|nope,?|wait,?|sorry,?|make (?:it|that)|change (?:it|that) to|it was|that was|(?:it|that) should (?:be|have been)|should be|correction[:,]?)\s+(?:that was |it was |it'?s |more like )?(\d+(?:\.\d+)?)\s*k(?:ms?|ilomet(?:er|re)s?)?\.?$",
    caseSensitive: false);
// abandons a pending slot-fill dialogue (Spec 03 §6.3 ProvideSlot)
final _cancelRe = RegExp(
    r"^(?:(?:no,?|nah,?|actually,?|ok(?:ay)?,?|on second thought,?)\s+)?(?:cancel(?: (?:that|it|this))?|never ?mind(?: (?:that|it))?|forget (?:it|that|about it)|nvm|nah|stop|abort|drop it|leave it|skip it|no thanks?|no thank you|don'?t (?:bother|worry about it))[.!]?$",
    caseSensitive: false);
// confirms an authored-capability draft (Spec 02 §6.5: nothing registered until "activate")
final _activateRe = RegExp(r'^(activate|add it|yes,? add it|go ahead|do it|yes,? do it|yes)\.?$', caseSensitive: false);
// resolves a HELD automation write (Spec 02 §7.5 Review Feed): apply it, or dismiss it.
final _approveReviewRe = RegExp(
    r'^(?:approve|apply|run)(?: (?:it|that|the (?:change|automation|review|suggestion|task)))?\.?$',
    caseSensitive: false);
final _declineReviewRe = RegExp(
    r'^(?:decline|dismiss|reject|skip)(?: (?:it|that|the (?:change|automation|review|suggestion)))?\.?$',
    caseSensitive: false);
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
// A "start tracking X in glasses / with calories" specifies a UNIT or FIELD a shipped template
// can't honor — so a keyword match ("water") must NOT pre-empt it (route to authoring instead).
// The negative lookahead excludes innocuous "in the morning"/"with my book" time/possessive tails.
// Require a UNIT-ish noun after in/with/per, so "water intake in glasses" / "meals with calories"
// trigger authoring but "walks with Sarah" / "reading in bed" fall through to the free template
// (erring toward the free template is the safe default — Fable review).
final _customizationRe = RegExp(
    r'\b(?:in|with|per) (?:glasses?|cups?|grams?|g|kg|ml|l|liters?|litres?|oz|ounces?|calories|cals?|'
    r'pounds?|lbs?|servings?|portions?|pieces?|slices?|scoops?|bottles?|tb?sp|tablespoons?|teaspoons?|'
    r'reps?|sets?|steps|miles?|km|minutes?|mins?|hours?|hrs?)\b',
    caseSensitive: false);
// Content search (F-12). _searchNoteRe wants a "note/entry" + "about/mentioning" shape;
// _searchForRe catches the terse "search (my notes) for X".
final _searchNoteRe = RegExp(
    r"^(?:can you |could you |please )?(?:(?:find|show(?: me)?|pull up|bring up|dig up|look up|look for|locate|do i have|is there|where(?:'?s| is| are))\s+(?:(?:that|my|the|a|an|any|all|old)\s+)*(?:notes?|entry|entries|journal(?:\s+entr(?:y|ies))?|thing|one)\s+(?:about|on|mentioning|regarding|where|that\s+(?:says?|mentions?))|where\s+did\s+i\s+(?:write|journal|note)\s+(?:something\s+)?(?:about|down)|what\s+did\s+i\s+(?:write|note)\s+(?:down\s+)?about)\s+(.+?)\??$",
    caseSensitive: false);
final _searchForRe = RegExp(
    r"^(?:search\s+(?:(?:through\s+)?(?:my\s+|the\s+)?(?:notes?|journal|entries)\s+)?(?:for\s+)?|(?:look|go|dig|flip)\s+through\s+(?:my\s+|the\s+)?(?:notes?|journal|entries)\s+(?:for\s+|and\s+find\s+)|(?:check|scan)\s+(?:my\s+|the\s+)?(?:notes?|journal|entries)\s+for\s+|(?:find|look\s+up)\s+(?=.+\s+in\s+(?:my\s+|the\s+)?(?:notes?|journal)\??$))(.+?)(?:\s+in\s+(?:my\s+|the\s+)?(?:notes?|journal))?\??$",
    caseSensitive: false);
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
// ALL FROZEN (Spec 03 §2.2a `G-44`/`G-46`): these regexes are the zero-cost offline / free-tier
// recognition floor for the common phrasings — no longer grown per-miss. Anything they miss is now
// recognized by the cloud residual (§7.3.2) and learned into the corpus, not hand-patched here.
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
  /// The AutomationRunner + Review Feed (Spec 04 §3.9). Fired after _dispatch's
  /// writes via the onWrite seam (§4.8); read-only results are delivered
  /// (pendingNudges / takeDeliveries), writing plans are HELD in
  /// [AutomationRunner.pendingReview] for the user's approval (Spec 02 §7.5).
  late AutomationRunner automations;
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
  /// How the LAST turn resolved (corpus | cloud | cloud-multi | compound | generative | ...).
  String get lastSource => _outSource;
  bool _lastTurnSpentCloud = false;
  /// Whether the last turn actually SPENT Anthropic tokens — drives the per-response cloud
  /// indicator. Keyed on real token spend (not the route source), so a cloud/generative call
  /// that FAILED and fell back to an offline reply shows no dot (review #22).
  bool get lastTurnUsedCloud => _lastTurnSpentCloud;
  String? _outSkill;
  /// The skill id (or "a+b" for a compound/multi-action turn) that the last turn dispatched.
  /// Read by the UI to choose an occasion-appropriate presence glyph (Spec 15 §5A.5).
  String? get lastSkill => _outSkill;
  String? _enteredChapter; // the tour chapter this turn opened (null if none)
  /// The Tour chapter id ('reminders'|'tasks'|'people'|'tracking'|'colors') that THIS turn opened, or
  /// null. Read by the UI to stage a chapter-apt glyph + (for 'colors') a live presence-colour demo.
  String? get lastTourChapter => _enteredChapter;
  String? _cloudStatus; // telemetry: cloud health this turn ('ok' or a CloudErrorKind name)
  // Rich debug-trace fields (dogfood diagnosis: read the turnlog instead of retrying) —
  // reset each turn in handle(), populated as the turn resolves.
  String? _outTemplate; // the corpus template matched, if a corpus route
  Map<String, dynamic>? _outSlots; // the slots dispatched into the skill
  final List<Map<String, dynamic>> _outWrites = []; // record ops this turn: {op,id,typeId}
  final List<Map<String, dynamic>> _outReads = []; // what each read RESOLVED to (diagnose wrong-match bugs)
  String? _outError; // exception type + message + stack, on the error path (never shown to the user)
  Map<String, dynamic>? _outDiag; // on a MISS: the near-miss (closest skill + score) it computed
  // A paused turn waiting for the user to supply a missing required slot (Spec 03
  // §6.3 ProvideSlot): {skillId, slots (partial), missing (remaining required names)}.
  // The next turn's input fills it and the completed skill dispatches.
  Map<String, dynamic>? _pendingFill;
  // A generative request paused for its missing contact param (Spec 03 §6.3, G-46): {kind,
  // template}. The next turn supplies the person and the synthesis runs.
  Map<String, dynamic>? _pendingGen;
  // A validated-but-UNREGISTERED authored capability awaiting the user's "activate"
  // (Spec 02 §6.5 / G-18): {type, skill, typeId, skillId, displayName, examples}.
  Map<String, dynamic>? _pendingActivation;
  String? _pendingAuthorOffer; // DF-01: a "start tracking X" awaiting a yes before paid authoring
  // The Tour (guided "what can you do?"): {'chapter': String?, 'visited': Set, 'codaGiven': Set}.
  // Ephemeral, never persisted; dropped on app close or when a turn dispatches OUT of the current
  // chapter (the user moved on). A read/undo/clarify keeps it alive (the user is engaging as coached).
  Map<String, dynamic>? _pendingTour;
  // True iff THIS outer turn was a Tour navigation turn (open/enter/exit/map). Set by the tour
  // helpers, reset per turn in handle(). Used instead of `_outSource == 'tour'` because the
  // correction path overwrites _outSource (so a chapter entered via "no, I meant tracking" wasn't
  // seen as a tour turn and got killed). Fable review #10.
  bool _tourSpokeThisTurn = false;
  // Whether retrieval (the embed-server index) is active this session. Authoring
  // grows the inventory and must re-index — but only when retrieval is on, so the
  // authoring path stays hermetic under init(retrieval: false), like init() itself.
  bool _retrievalEnabled = true;
  ContentSearchIndex? _contentIndex; // semantic content search (F-12); null until retrieval builds it
  Map<String, ReferenceStore> _references = const {}; // reference KBs (Spec 13), loaded at init

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
    // Migrate-on-read (Spec 01 §7.4 / Spec 06 D12): bring records written under an older schema
    // forward to their type's current version, re-persisting only what changed. A future-versioned
    // record (a newer app wrote it) is left intact and surfaced, never mangled.
    var migrated = 0, tooNew = 0;
    for (final e in store.entries.toList()) {
      final td = types[e.value['typeId']];
      if (td == null) continue;
      final m = migrateRecord(e.value, td);
      if (m.changed) {
        store[e.key] = m.record;
        repo.persist(m.record);
        migrated++;
      } else if (isFutureVersioned(e.value, td)) {
        tooNew++;
      }
    }
    if (migrated > 0 || tooNew > 0) {
      phase('migrated $migrated record(s) to current schema${tooNew > 0 ? '; $tooNew from a newer app left as-is' : ''}');
    }
    // Reference knowledge bases (Spec 13): shipped, read-only datasets (nutrition calories) —
    // load once; a missing file yields an empty store (the feature just goes quiet).
    _references = {'nutrition': ReferenceStore.load(dataDir, 'nutrition')};
    interp = Interpreter(types, now, references: _references);
    // Automations registry (Spec 01 §4.4 / Spec 04 §3.9): loaded like types/skills;
    // an absent automations/ folder is simply an empty registry (zero behavior change).
    final autoRepo = repo;
    final autoState =
        autoRepo is FileStorageRepository ? autoRepo.loadAutomationState() : <String, DateTime>{};
    automations = AutomationRunner(
      types: types,
      skills: skills,
      store: store,
      clock: () => now,
      persist: repo.persist,
      lastFired: autoState, // the runner mutates this map in place
      onFired: (_, __) {
        if (autoRepo is FileStorageRepository) autoRepo.saveAutomationState(autoState);
      },
    );
    automations.register(repo.loadDefs('automations', 'automationId'));
    automations.tick(now); // fire any schedule automation whose cron time passed since last open
    if (automations.statuses.isNotEmpty) {
      phase('automations: ${automations.statuses.map((a) => '${a.automationId}=${a.state}').join(', ')}');
    }
    // schedule catch-up outcome (diagnosable from the log, not a black box)
    if (automations.deliveries.isNotEmpty || automations.pendingReview.isNotEmpty || automations.refusals.isNotEmpty) {
      phase('automation tick: ${automations.deliveries.length} delivered, '
          '${automations.pendingReview.length} held, ${automations.refusals.length} refused');
    }
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
      _contentIndex = ContentSearchIndex();
      await _contentIndex!.build(store.values); // semantic content search (F-12); no-op if server down
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

  // ---- The Tour (Fable's capability discovery) — a stateful, conversational "what can you do?" ----

  /// Chapters whose gating skills are all registered (never advertise what isn't installed).
  List<_TourChapter> _availableChapters() =>
      _tourChapters.where((c) => c.gate.every(skills.containsKey)).toList();

  _TourChapter? _tourChapterOf(String id) {
    for (final c in _tourChapters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Match an utterance to a chapter ONLY when it's a selection — the alias IS the utterance, after
  /// stripping a small set of lead-ins ("tell me about reminders" -> "reminders"). Crucially it must
  /// NOT match an alias merely CONTAINED in a command or correction (e.g. "no, I meant to log a 3k
  /// run" must reach the correction path, not re-enter the tracking chapter). Gated on availability.
  _TourChapter? _tourSelect(String u) {
    var s = u.toLowerCase().trim().replaceAll(RegExp(r'[.!?,]+$'), '').trim();
    s = s.replaceFirst(
        RegExp(r"^(?:(?:tell|show) me (?:more )?about |what about |how about |let'?s (?:do|try|hear about) |i'?d like |can we do |about )"),
        '');
    s = s.replaceFirst(RegExp(r'^the '), '').trim();
    for (final c in _availableChapters()) {
      if (c.aliases.contains(s)) return c;
    }
    return null;
  }

  /// The next available chapter not yet visited, in curated order.
  _TourChapter? _nextChapter(Set<String> visited) {
    for (final c in _availableChapters()) {
      if (!visited.contains(c.id)) return c;
    }
    return null;
  }

  /// Open the tour: name the territory in one breath, invite a pick or the full tour. Preserves an
  /// in-progress tour's visited set (a repeat "what can you do" continues rather than restarts).
  String _openTour() {
    final prior = _pendingTour;
    final visited = prior == null ? <String>{} : (prior['visited'] as Set).cast<String>();
    final codaGiven = prior == null ? <String>{} : (prior['codaGiven'] as Set).cast<String>();
    _outSource = 'tour';
    _tourSpokeThisTurn = true;
    final avail = _availableChapters();
    // The 'colors' capstone is not a menu territory and doesn't gate "seen it all" — the opener shows
    // the full map once the real territories are visited (colours stays reachable via "next").
    final menuable = avail.where((c) => c.id != 'colors').toList();
    final remaining = menuable.where((c) => !visited.contains(c.id)).toList();
    if (remaining.isEmpty) {
      // seen it all → show the map and CLOSE the tour (don't leave it live to mislabel later turns).
      _pendingTour = null;
      return _helpText();
    }
    _pendingTour = {'chapter': null, 'visited': visited, 'codaGiven': codaGiven};
    // Only name territories that are actually installed (never advertise a gated-off chapter). The
    // 'colors' capstone isn't a "remember" territory, so it's left off the pick-menu (still reachable
    // via "next").
    const label = {
      'reminders': 'reminders',
      'tasks': 'tasks',
      'people': 'the people you care about',
      'tracking': 'anything you want to track',
    };
    final names = menuable.map((c) => label[c.id] ?? c.id).toList();
    final territory = names.length <= 1
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
    // Privacy first — only on a FRESH tour (not on a repeat "what can you do"), and said before the
    // people/journal chapters ever ask for anything personal. Accurate to the posture: on-device by
    // default; the only thing that leaves is a smart feature calling the user's OWN AI account.
    final privacy = prior == null // only on a brand-new tour, never on a repeat while one is live
        ? 'First, so you know: everything you tell me stays on your phone — it\'s yours. Nothing goes '
            'to any server unless a smart feature needs the AI, and even then it goes to your own '
            'private account, never to me.'
        : null;
    final intro = "I remember things so you don't have to — $territory. "
        'Pick one and I\'ll show you, or say "give me the tour."';
    // Separate paragraphs (blank line) → the voice inserts a real silent beat between the privacy note
    // and the capabilities intro, so it's clear one topic closed before the next.
    return privacy == null ? intro : '$privacy\n\n$intro';
  }

  /// Enter a chapter: essence + the single "you could say" example + the invitation. Marks the
  /// chapter visited so "next" advances past it (and a repeat "what can you do" skips it).
  String _enterChapter(_TourChapter ch, Set<String> visited) {
    final codaGiven = _pendingTour == null
        ? <String>{}
        : (_pendingTour!['codaGiven'] as Set).cast<String>();
    _pendingTour = {
      'chapter': ch.id,
      'visited': {...visited, ch.id},
      'codaGiven': codaGiven,
    };
    _outSource = 'tour';
    _tourSpokeThisTurn = true;
    _enteredChapter = ch.id; // UI stages a chapter-apt glyph / colour demo
    return '${ch.essence}\n\n${ch.tryLine}\n\n${ch.followOn}';
  }

  /// The closing — always teaches the two meta-moves that make everything else discoverable.
  /// (Caller sets _outSource; the post-turn teach-by-doing check appends this without touching it.)
  String _tourClosing() =>
      "That's the shape of it. When in doubt, just say the thing — if I don't follow, I'll ask. "
      'And "undo that" reverses whatever I last did.';

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

  /// Domain-scoped help: given the captured topic, return just that area's examples, or
  /// null if the topic isn't a recognized domain (so the caller falls through to routing).
  String? _helpForTopic(String topic) {
    final t = topic.toLowerCase();
    bool m(List<String> kws) => kws.any(t.contains);
    bool has(String id) => skills.containsKey(id);
    if (m(['reminder']) && has('set-reminder')) {
      return 'With reminders you can say things like: "remind me to call mom on thursday at 5pm", '
          '"remind me every weekday at 9am to stretch", "remind me on the 15th of every month to pay rent", '
          '"what reminders do I have tomorrow", "snooze the reminder to X to friday at 9am", "cancel the reminder to X".';
    }
    if (m(['task', 'todo', 'to-do', 'to do']) && has('create-task')) {
      return 'With tasks you can say: "add call the plumber to my list", "add milk, eggs, and bread to my list", '
          '"list my tasks", "what\'s due tomorrow", "move X to friday", "mark X done", "delete the first task".';
    }
    if (m(['run', 'jog', 'exercise', 'workout']) && has('log-run')) {
      return 'For running: "log a 3k run", "how much have I run this week", "how far have I run", "what\'s my running streak".';
    }
    if (m(['mood', 'feeling', 'feel']) && has('log-mood')) {
      return 'For mood: "I\'m feeling great", "I\'m exhausted", "how have I been feeling".';
    }
    if (m(['journal', 'diary']) && has('log-journal')) {
      return 'For your journal: "journal that today was a good day", "read my journal", '
          '"what did I write yesterday", "delete my last journal entry".';
    }
    if (m(['people', 'contact', 'friend', 'relationship']) && has('remember-person-fact')) {
      return 'For people: "remember that Mia is Sarah\'s daughter", "what do I know about Mia", '
          '"talked to Sam yesterday", "how old is Sarah", "when did I last talk to Sam".';
    }
    if (m(['birthday', 'bday']) && has('set-birthday')) {
      return 'For birthdays: "Sarah\'s birthday is july 16", "when is Sarah\'s birthday", "whose birthday is coming up".';
    }
    if (m(['meal', 'food', 'eat', 'calorie']) && has('log-meal')) {
      return 'For meals: "I had eggs for breakfast", "what did I eat today", "how many calories have I had today".';
    }
    if (m(['water', 'hydrat', 'step', 'weight', 'reading', 'medication', 'meds', 'track'])) {
      return 'You can start a new tracker any time — e.g. "start tracking my water intake", '
          '"start tracking my steps", or "start tracking my weight" — then log with things like "I drank 2 glasses of water".';
    }
    if (m(['nickname', 'alias']) && has('set-alias')) {
      return 'For nicknames: "Sarah\'s nickname is Mum", then "when did I last talk to Mum".';
    }
    return null;
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
      // a FORWARD-intent date (e.g. create-task.dueDate): a bare month-day that already passed
      // this year rolls to next year — no due dates in the past (reviewer b #6).
      if (type == 'futuredate') slots[name] = router.resolveFutureDate(slots[name] as String, now);
      if (type == 'datetime') slots[name] = router.resolveDateTime(slots[name] as String, now);
      // a PAST-event date (e.g. log-interaction.at): a bare "tuesday" is the PREVIOUS Tuesday, not
      // the next — else a past interaction gets stamped with a future date (reviews a#4 / b#2).
      if (type == 'pastday') slots[name] = router.resolvePastday(slots[name] as String, now);
    }
  }

  /// Normalise a raw slot value from any router before it reaches a resolver or gets persisted.
  /// The cloud sometimes fills an absent optional slot with a sentinel ("none"/"null") or a blank
  /// string; both must become a real null so the skill's own isNull branches fire and no
  /// whitespace-only "note"/"kind" is stored as a present value (reviewer b #7).
  static dynamic _sanitizeSlot(dynamic v) {
    if (v is! String) return v;
    final t = v.trim();
    if (t.isEmpty || t.toLowerCase() == 'none' || t.toLowerCase() == 'null') return null;
    return v;
  }

  /// On-open nudge lines (the UI shows these on launch). Two derived sources, so
  /// each drops out the moment its record changes: past-due reminders (you can't
  /// schedule a toast in the past) and birthdays coming up within a week. Each line
  /// carries its own icon.
  List<String> pendingNudges() => [
        // the notification backend can't fire (permission denied / init failed) — surface it so
        // reminders don't fail silently (directive #7), never blank when healthy.
        if (_scheduler?.unavailableReason() case final r?) '⚠️ $r',
        for (final r in dueReminders(store, now)) '⏰ Reminder: ${r.body}',
        ...upcomingBirthdayNudges(store, now),
        // read-only automation results (Spec 02 §7.5 "deliver") — shown until drained
        for (final d in automations.deliveries) '✨ ${d.text}',
        // held automation writes (Spec 02 §7.5 "hold for review") — never auto-applied
        for (final p in automations.pendingReview)
          '📋 Pending review: ${p.preview ?? p.description} (from ${p.automationId})',
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
    _tourSpokeThisTurn = false; // set true by the tour helpers if THIS turn navigates the tour
    _enteredChapter = null; // set by _enterChapter when THIS turn opens a tour chapter (UI reads it)
    _cloudStatus = null;
    _outTemplate = null;
    _outSlots = null;
    _outWrites.clear();
    _outReads.clear();
    _outError = null;
    _outDiag = null;
    // Snapshot the automation runner so this turn's UNATTENDED activity (onWrite fires) is
    // visible in the trace — otherwise an automation that fired/held/refused leaves no record.
    final autoDelivered0 = automations.deliveries.length;
    final autoHeld0 = automations.pendingReview.length;
    final autoRefused0 = automations.refusals.length;
    final startedAt = DateTime.now();
    // Cost telemetry: snapshot the cloud token counters so this turn's spend is logged per-turn
    // (the turnlog is append-only, so summing 'cost.usd' across it gives a real running total).
    final c = claude;
    final inTok0 = c is ClaudeClient ? c.inTokens : 0;
    final outTok0 = c is ClaudeClient ? c.outTokens : 0;
    String resp;
    try {
      resp = await _handle(u);
    } catch (e, st) {
      _outSource = 'error';
      _outError = '${e.runtimeType}: $e\n$st'; // full detail to the trace, never to the user
      resp = "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
    }
    // Tour teach-by-doing (post-turn). A tour is live and THIS turn wasn't tour-navigation:
    //  - In-domain WRITE (the user tried the example for real) → append the coda ONCE per chapter,
    //    and close if every chapter is now visited. (Fable review #1: gate on _lastTurnWrote so a
    //    read-only query — "what are my reminders", "my running streak" — never gets a write-flavored
    //    coda whose "undo that" would reverse an UNRELATED earlier write. #4: once per chapter.)
    //  - In-domain READ / undo / clarify / error / a template-or-authoring turn → keep the tour alive;
    //    the user is engaging as coached (Fable review #3/#7 — don't kill on "undo that"/"yes").
    //  - A dispatch OUT of the current chapter's domain → the user moved on → end the tour silently.
    final liveTour = _pendingTour;
    if (liveTour != null && !_tourSpokeThisTurn) {
      final chapter = liveTour['chapter'] as String?;
      final ch = chapter == null ? null : _tourChapterOf(chapter);
      final skill = _outSkill;
      final inDomain = ch != null && skill != null && ch.domainKeywords.any(skill.contains);
      if (inDomain) {
        final codaGiven = liveTour['codaGiven'] as Set;
        if (_lastTurnWrote && _outSource != 'error' && !codaGiven.contains(chapter)) {
          codaGiven.add(chapter);
          resp = '$resp ${ch.coda}';
          if (_availableChapters().every((c) => (liveTour['visited'] as Set).contains(c.id))) {
            _pendingTour = null;
            resp = '$resp\n\n${_tourClosing()}';
          }
        }
      } else if (skill != null) {
        _pendingTour = null; // a skill ran outside this chapter's domain → moved on → end silently
      }
      // else (no skill dispatched — clarify/undo/error/template) → keep the tour alive.
    }
    // Did this turn actually spend cloud tokens? (drives the per-response cloud dot — accurate
    // even when a cloud/generative call failed to an offline reply, which spends nothing.)
    _lastTurnSpentCloud = c is ClaudeClient && (c.inTokens - inTok0 > 0 || c.outTokens - outTok0 > 0);
    // Post-turn housekeeping (reminder reconcile + the diagnostics trace) must NEVER lose the
    // already-computed response — a turnlog I/O error or a reconcile hiccup is non-fatal to the
    // turn (Fable review: these sat outside the try). Wrap so they can't escape to the UI.
    try {
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
      if (c is ClaudeClient && (c.inTokens - inTok0 > 0 || c.outTokens - outTok0 > 0))
        'cost': {
          'in': c.inTokens - inTok0,
          'out': c.outTokens - outTok0,
          'usd': ClaudeClient.costUsd(c.inTokens - inTok0, c.outTokens - outTok0),
        },
      if (_outReads.isNotEmpty) 'reads': _outReads,
      if (_outWrites.isNotEmpty) 'writes': _outWrites,
      'response': resp.length > 240 ? '${resp.substring(0, 240)}…' : resp,
      if (_outDiag != null) 'diag': _outDiag,
      if (_outError != null) 'error': _outError,
      if (automations.deliveries.length > autoDelivered0 ||
          automations.pendingReview.length > autoHeld0 ||
          automations.refusals.length > autoRefused0)
        'automations': {
          if (automations.deliveries.length > autoDelivered0) 'delivered': automations.deliveries.length - autoDelivered0,
          if (automations.pendingReview.length > autoHeld0) 'held': automations.pendingReview.length - autoHeld0,
          if (automations.refusals.length > autoRefused0) 'refused': automations.refusals.sublist(autoRefused0),
        },
    });
    } catch (_) {/* housekeeping/logging failure must not break the turn */}
    return resp;
  }

  /// A short, honest, user-facing reason a cloud call failed — so a miss names the
  /// cause instead of always blaming the user's phrasing (no silent degradation).
  static String cloudReason(CloudErrorKind k) => switch (k) {
        CloudErrorKind.noKey => "I don't have an API key set — add one in ~/.plenara/config.json.",
        CloudErrorKind.badKey => "my API key was rejected — update it in ~/.plenara/config.json.",
        CloudErrorKind.insufficientCredits =>
          "your Anthropic account has no credits — add a payment method or credits at console.anthropic.com (Settings → Billing). Your key is fine.",
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

    // A generative request paused for its contact (§6.3, G-46): this input names the person — UNLESS
    // it's a backout, a system command, or a fresh command, which must not be swallowed as a name
    // (mirrors the _pendingFill guards below; without this "undo"/"remind me…" became the "contact").
    final pendingGen = _pendingGen;
    if (pendingGen != null) {
      _pendingGen = null;
      if (_cancelRe.hasMatch(u)) {
        _outSource = 'clarify';
        return 'Okay — never mind.';
      }
      final genIsSystemCmd =
          _undoRe.hasMatch(u) || _helpRe.hasMatch(u) || _corrRe.hasMatch(u) || _fabricationRe.hasMatch(u);
      final genLooksLikeCommand = router.route(u, clock: now, contacts: _knownContactTokens()) != null ||
          _searchNoteRe.hasMatch(u) || _searchForRe.hasMatch(u);
      if (!genIsSystemCmd && !genLooksLikeCommand) {
        return _dispatchGenerative(pendingGen['kind'] as String, {'contact': u.trim()},
            pendingGen['template'] as String?, 'cloud', u, now);
      }
      // else: a command, not a name — abandon the pause and handle this input normally (fall through).
    }

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
        final skillId = pending['skillId'] as String;
        final skill = skills[skillId];
        final slots = Map<String, dynamic>.from(pending['slots'] as Map);
        final missing = List<String>.from(pending['missing'] as List);
        // A reply that is itself a NEW command — it routes to a skill, or is a search/query intent —
        // must NOT be swallowed as the slot value (a TEXT slot coerces ANY string, so without this
        // "what are my reminders" would be written as a meal's food). Treat it as null so the
        // abandon-and-fall-through path below runs. (Fable review, major.)
        final looksLikeNewCommand = router.route(u, clock: now, contacts: _knownContactTokens()) != null ||
            _searchNoteRe.hasMatch(u) ||
            _searchForRe.hasMatch(u);
        final coerced = looksLikeNewCommand ? null : _coerceSlot(skill, missing.first, u, now);
        if (coerced != null) {
          _pendingFill = null; // got the answer
          slots[missing.first] = coerced;
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
        // The input did NOT provide the missing slot — it's a NEW command, not a slot answer.
        // Abandon the paused turn and handle the input normally (fall through), so the user is
        // never trapped re-answering. (Surfaced by the live cloud tier: a cloud-routed reminder
        // with no time swallowed every later turn as a failed "when?" answer.)
        _pendingFill = null;
      } else {
        _pendingFill = null; // interrupted by a system command — handle it normally
      }
      // both branches cleared _pendingFill and fall through to normal handling below
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

    // The Tour (guided discovery): while live, a closed vocabulary steers it — exit, the full map,
    // pick a chapter, or advance. Selection/advance only fire when the input ISN'T a real command,
    // so "remind me to …" during the reminders chapter is TRIED live, not re-selected. Anything else
    // falls through to normal routing; the teach-by-doing coda (in handle()) then keeps or ends it.
    final tour = _pendingTour;
    if (tour != null) {
      final visited = (tour['visited'] as Set).cast<String>();
      if (_cancelRe.hasMatch(u) || _tourDoneRe.hasMatch(u)) {
        _pendingTour = null;
        _outSource = 'tour';
        return _tourClosing();
      }
      if (_tourMapRe.hasMatch(u)) {
        _pendingTour = null;
        _outSource = 'help';
        return _helpText();
      }
      final chapter = tour['chapter'] as String?;
      final sel = _tourSelect(u);
      // At the "pick one" state a lone alias ("tasks") is a SELECTION even though it also routes to
      // a query (list-tasks) — take it before the command guard (Fable review #2). Once IN a chapter,
      // keep command-first so "remind me to …" is TRIED live, not re-selected.
      if (sel != null && chapter == null) return _enterChapter(sel, visited);
      final isCommand = router.route(u, clock: now, contacts: _knownContactTokens()) != null;
      if (!isCommand) {
        if (sel != null) return _enterChapter(sel, visited);
        if (_tourNextRe.hasMatch(u)) {
          final next = _nextChapter(visited);
          if (next == null) {
            _pendingTour = null;
            _outSource = 'tour';
            return _tourClosing();
          }
          return _enterChapter(next, visited);
        }
      }
      // not a tour command → fall through; handle()'s post-turn coda check evaluates the outcome.
    }

    // Automation Review Feed (Spec 02 §7.5): a held automation WRITE awaits the user's call —
    // "approve it" applies the deterministically re-resolved plan; "dismiss it" reaps it.
    if (automations.pendingReview.isNotEmpty) {
      if (_approveReviewRe.hasMatch(u)) {
        final item = automations.pendingReview.first;
        final res = automations.approve(item.id);
        _outSource = 'automation-review';
        _outSkill = item.skillId;
        return switch (res.kind) {
          'applied' => 'Done — applied "${item.description}".',
          'planChanged' => "That automation's data changed since it queued — ${res.message ?? 'have a look and re-approve'}.",
          'refused' => "I couldn't apply that — ${res.message ?? 'it was refused'}.",
          _ => 'That review is no longer pending.',
        };
      }
      if (_declineReviewRe.hasMatch(u)) {
        final item = automations.pendingReview.first;
        automations.decline(item.id);
        _outSource = 'automation-review';
        return 'Dismissed — I won\'t apply "${item.description}".';
      }
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

    // "what can you do?" opens the Tour — a guided conversation, not a bullet dump.
    if (_helpRe.hasMatch(u)) {
      return _openTour();
    }
    // Domain-scoped help (queries gap): "what can you do with reminders", "how do I track water".
    // A topic that IS a tour chapter opens directly into it; otherwise fall back to the flat
    // domain examples (meals, nicknames, …). An unknown topic falls through to normal routing.
    final topicMatch = _helpTopicRe.firstMatch(u);
    if (topicMatch != null) {
      final topic = topicMatch.group(1)!;
      final ch = _tourSelect(topic);
      if (ch != null) {
        // Preserve an in-progress tour's visited set (don't reset "next" progress). Fable review #9.
        final visited = _pendingTour == null
            ? <String>{}
            : (_pendingTour!['visited'] as Set).cast<String>();
        return _enterChapter(ch, visited);
      }
      final domainHelp = _helpForTopic(topic);
      if (domainHelp != null) {
        _outSource = 'help';
        return domainHelp;
      }
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
    if (def != null && router.route(u, clock: now, contacts: _knownContactTokens()) == null) {
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

    // Content search (F-12): "find that note about the cabin trip" / "search my notes for X".
    // Checked before corpus routing so it isn't mis-parsed; semantic when the embed index is up,
    // keyword otherwise — so it works offline too.
    final searchM = _searchNoteRe.firstMatch(u) ?? _searchForRe.firstMatch(u);
    if (searchM != null) return _searchContent(searchM.group(1) ?? '');

    var routed = router.route(u, clock: now, contacts: _knownContactTokens());
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
      switch (await claude.routeResidual(u, skills, knownContacts: _knownContactNames())) {
        case CloudOk(:final value):
          _cloudStatus = 'ok';
          routed = value; // may be null == the model abstained
        case CloudError(:final kind):
          _cloudStatus = kind.name;
          cloudErr = kind;
      }
    }
    // Generative recognition (Spec 03 §2.2a / §7.3.2, G-46): the residual classified a SYNTHESIS
    // request (gift ideas, briefing, …) — dispatch it to the GenerativeService, not the interpreter.
    if (routed != null && routed['generativeKind'] is String) {
      return _dispatchGenerative(routed['generativeKind'] as String,
          (routed['params'] as Map?)?.cast<String, dynamic>() ?? const {},
          routed['template'] as String?, routed['source'] as String? ?? 'cloud', u, now);
    }
    if (routed == null) {
      // A miss is corpus + (abstain | cloud error | no cloud). If the cloud FAILED,
      // say so honestly instead of only blaming the phrasing (no silent degradation).
      final sg = await router.retrievalSuggest(u);
      // Diagnose the miss in the trace: corpus didn't match; what the cloud did; and the
      // nearest skill + score (when retrieval is on) — so "why didn't it catch that?" is answerable.
      _outDiag = {
        'corpus': 'no-match',
        'cloud': cloudErr != null ? 'error:${cloudErr.name}' : (_cloudStatus == 'ok' ? 'abstained' : 'not-consulted'),
        if (sg != null) 'closest': sg['skillId'],
        if (sg != null) 'score': sg['s1'],
        if (sg != null) 'confident': sg['confident'],
      };
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
    // Multi-record decomposition (cloud only): the router split a rich statement into
    // several records ("dinner with X and Y", or a relationship AND a fact). Execute each
    // fully-slotted action and compose the confirmations — like the F-13 compound path.
    // An action missing a required slot is skipped (no per-action ProvideSlot in a batch).
    if (routed['actions'] is List) {
      final replies = <String>[];
      final done = <String>[];
      var skipped = (routed['skippedGenerative'] as int?) ?? 0; // generative half(s) dropped from a batch (G-46)
      final journalBefore = _journal.length;
      final seen = <String>{}; // dedup: a cloud split can emit the same record twice (reviewer a #8)
      for (final a in (routed['actions'] as List).cast<Map>()) {
        final sid = a['skillId'] as String?;
        final slots = (a['slots'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        slots.updateAll((k, v) => _sanitizeSlot(v));
        if (sid == null || !skills.containsKey(sid)) {
          skipped++; // an unusable action is NOT silently dropped — the reply admits it below
          continue;
        }
        _normalizeTypedSlots(skills[sid], slots, now);
        if (_missingRequired(skills[sid], slots).isNotEmpty) {
          skipped++;
          continue;
        }
        // Resolve-then-dedup: two actions that normalise to the same skill + slots are ONE
        // record, not two (a duplicated "dinner with Katherine" would otherwise double-write).
        final key = '$sid|${(slots.entries.toList()..sort((x, y) => x.key.compareTo(y.key)))
            .map((e) => '${e.key}=${e.value}').join('&')}';
        if (!seen.add(key)) continue; // silent — a dedup'd duplicate isn't a "skipped" failure
        // One bad action (model-shaped slots hitting a resolver, a clarify throw) must not abort
        // the batch after earlier actions already persisted, nor let handle()'s catch-all falsely
        // claim nothing was done (review #18). Contain it and count it as skipped.
        try {
          replies.add(await _dispatch(sid, slots, 'cloud', now)); // no learn: a compound isn't one template
          done.add(sid);
        } catch (_) {
          skipped++;
        }
      }
      if (replies.isNotEmpty) {
        // Collapse this turn's per-action journal entries into ONE, so undo / "no, I meant"
        // reverses the WHOLE turn — not just the last record (review #5).
        if (_journal.length - journalBefore > 1) {
          final merged = <String, Map<String, dynamic>?>{};
          for (var i = journalBefore; i < _journal.length; i++) {
            _journal[i].before.forEach((id, prior) => merged.putIfAbsent(id, () => prior));
          }
          _journal.removeRange(journalBefore, _journal.length);
          _journal.add(_JournalEntry(merged, null));
        }
        _lastTurnWrote = _journal.length > journalBefore; // the turn is undoable as a unit
        _outSource = 'cloud-multi'; // telemetry: one turn, several records
        _outSkill = done.join('+');
        final reply = replies.join(' ');
        return skipped > 0
            ? "$reply (I couldn't record $skipped part${skipped > 1 ? 's' : ''} of that — try rephrasing ${skipped > 1 ? 'them' : 'it'}.)"
            : reply;
      }
      // every action was unusable — fall through to the honest miss path
      _outDiag = {'corpus': 'no-match', 'cloud': 'multi-empty'};
      return "I understood a few things there but couldn't record them cleanly — try one at a time?";
    }
    _outSource = routed['source'] as String; // telemetry: corpus | cloud
    _outSkill = routed['skillId'] as String?;
    // normalize leaked sentinel slot values from any source before they reach a
    // resolver (a replayed/live "none" for an absent date would otherwise persist
    // as garbage; the crash it once caused is already handled in _asDate).
    (routed['slots'] as Map?)?.updateAll((k, v) => _sanitizeSlot(v));
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
    // A cloud route may carry a SUGGESTED template (surface-abstracted) to learn — distinct
    // from a matched corpus `template`. The router validates it by round-trip before adopting.
    final learnTemplate = routed['source'] == 'cloud' ? routed['template'] as String? : null;
    final reply = await _dispatch(skillId, slots, routed['source'] as String, now,
        template: template, learnTemplate: learnTemplate, utterance: u);
    // A batch collapsed to one skill because its generative half was dropped (§7.3.2) — admit it, so
    // "log a run and suggest a gift for Sarah" doesn't silently swallow the gift request (P2.8).
    final droppedGen = (routed['skippedGenerative'] as int?) ?? 0;
    return droppedGen > 0
        ? "$reply (I can't do a gift suggestion as part of a bigger request — ask me that on its own.)"
        : reply;
  }

  /// Dispatch a residual-recognized generative request (Spec 03 §2.2a / §7.3.2, G-46) to the
  /// GenerativeService — the "suggest a gift for Elena" class, recognized by the cloud instead of a
  /// hand-written regex. A contact-param kind with no contact pauses for a missing-param follow-up
  /// (§6.3); [_pendingGen] resumes it next turn. (Recognition-learning is layered on in a follow-up.)
  Future<String> _dispatchGenerative(String kind, Map<String, dynamic> params, String? template,
      String source, String u, DateTime now) async {
    const contactKinds = {'gift_ideas', 'reconnect', 'draft_message'};
    _outSource = 'generative';
    _outSkill = kind;
    _outTemplate = template; // so a bad generative-template match is diagnosable in the turnlog
    // Coerce a non-string contact (the model can return a list/number) to null rather than throwing —
    // parity with routeResidual's "coerce, never throw" contract; it then takes the follow-up.
    final raw = params['contact'];
    final contact = raw is String ? raw.trim() : null;
    if (contactKinds.contains(kind) && (contact == null || contact.isEmpty)) {
      _pendingGen = {'kind': kind, if (template != null) 'template': template};
      _outSource = 'clarify';
      return switch (kind) {
        'reconnect' => 'Reconnect with whom?',
        'draft_message' => 'Draft a message to whom?',
        _ => 'Gift ideas for whom?',
      };
    }
    // Track a matched LEARNED template so a next-turn "correct" can forget it (§5.2 negative half) —
    // even on a corpus-matched turn that re-learns nothing. Without this, a mislearned generative
    // template is uncorrectable (both Fable reviewers, HIGH). Mirrors _dispatch.
    if (template != null && router.isLearned(template)) _lastTurnTemplate = template;
    _generative.lastDelivered = false; // reset; set true only by a real cloud synthesis
    final reply = await (switch (kind) {
      'gift_ideas' => _generative.giftIdeas(contact!, store, now),
      'reconnect' => _generative.reconnect(contact!, store, now),
      'draft_message' => _generative.draftMessage(contact!, store, now),
      'briefing' => _generative.briefing(store, now),
      'weekly_review' => _generative.weeklyReview(store, now),
      'pattern_insight' => _generative.patternInsight(store, now),
      _ => Future<String>.value("I didn't catch that."),
    });
    // Learn the RECOGNITION (not the generation) ONLY on a CLOUD-recognized, DELIVERED synthesis
    // (Spec 03 §2.7, G-46). Skip it when the route was already a corpus match (source == 'corpus') —
    // it's learned; re-learning appends case/punctuation near-duplicates forever (parity with
    // _dispatch, which learns only on 'cloud'). A degrade / unknown-person leaves lastDelivered false.
    if (source == 'cloud' && _generative.lastDelivered && contactKinds.contains(kind)) {
      final learned = router.learnGenerative(u, kind, contact, contacts: _knownContactTokens());
      if (learned != null) {
        repo.appendCorpusLearned({'generativeKind': kind, 'template': learned});
        _lastTurnTemplate = learned;
      }
    }
    return reply;
  }

  /// Resolve → execute → persist → journal → learn for a fully-slotted skill. Shared by
  /// the normal routing path and a completed ProvideSlot fill.
  Future<String> _dispatch(String skillId, Map<String, dynamic> slots, String source, DateTime now,
      {String? template, String? learnTemplate, String? utterance}) async {
    _outSkill = skillId; // debug trace
    _outSlots = slots;
    _outTemplate = template;
    final turnInterp = Interpreter(types, now, references: _references); // per-turn clock (Spec 03 §4)
    try {
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
      // onWrite automations (Spec 04 §4.8): the hook lives at the completion of
      // this turn's writes. Read-only results are delivered out-of-band; writing
      // plans are HELD in the review feed (Spec 02 §7.5) — the turn's response
      // is never changed by an automation, and a runner fault never fails the
      // turn (failures surface via automations.refusals, P2.8).
      if (plan.writes.isNotEmpty) {
        try {
          automations.notifyWrites(plan.writes);
        } catch (_) {/* contained — an automation must never break the user's turn */}
      }
      if (source == 'cloud' && utterance != null) {
        // Prefer the cloud's surface-abstracted suggestion (learns date/time phrasings the
        // verbatim reconstruction can't), validated by round-trip; fall back to the mechanical
        // abstraction when the cloud offered none or it failed a guard.
        var tmpl = learnTemplate == null
            ? null
            : router.learnSuggested(utterance, skillId, slots, learnTemplate,
                clock: now, contacts: _knownContactTokens());
        tmpl ??= router.learn(utterance, skillId, slots, contacts: _knownContactTokens());
        if (tmpl != null) {
          repo.appendCorpusLearned({'skillId': skillId, 'template': tmpl});
          // If the cloud misread this turn and we just LEARNED from it, a next-turn "no, I
          // meant…" must be able to forget that fresh template — else the bad pattern re-routes
          // future utterances. The matched-template branch at line ~1106 can't see it (the cloud
          // path has no corpus `template`), so record it here (reviewer a #6).
          _lastTurnTemplate = tmpl;
        }
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
    } finally {
      // capture the read-resolution trace even when resolve/execute THREW mid-plan — that's
      // exactly the turn you most want to diagnose from the log (review low).
      _outReads.addAll(turnInterp.lastPlan?.reads ?? const []);
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
      final lr = router.route(left, clock: now, contacts: _knownContactTokens());
      if (lr == null) continue;
      final rr = router.route(right, clock: now, contacts: _knownContactTokens());
      if (rr == null) continue;
      // A generative half (learned {generativeKind} route) has no skillId/slots — it can't be a
      // batched skill dispatch (Spec 03 §7.3.2: no generative inside a compound). Skip the seam so a
      // generative-shaped half never reaches the skill dispatch code (which would throw after the
      // other half already wrote, then falsely claim nothing was done).
      if (lr['generativeKind'] != null || rr['generativeKind'] != null) continue;
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

  /// Content search (F-12): semantic ranking if the embed index is up, else an always-on keyword
  /// fallback — so "find that note about X" never silently fails. Returns the matching records'
  /// text (journal entries, facts, tasks, interaction notes).
  Future<String> _searchContent(String rawQuery) async {
    final query = rawQuery.trim();
    _outSource = 'search';
    if (query.isEmpty) return 'What should I search your notes for?';
    var ids = await _contentIndex?.search(query) ?? const <String>[];
    if (ids.isEmpty) ids = ContentSearchIndex.keywordSearch(query, store.values);
    if (ids.isEmpty) return 'I couldn\'t find anything about "$query".';
    final byId = {for (final r in store.values) r['id']: r};
    final lines = <String>[];
    for (final id in ids) {
      final r = byId[id];
      final c = r == null ? null : ContentSearchIndex.contentOf(r);
      if (c != null) lines.add('• $c');
    }
    if (lines.isEmpty) return 'I couldn\'t find anything about "$query".';
    final head = lines.length == 1 ? 'Found 1 match:' : 'Found ${lines.length} matches:';
    return '$head\n${lines.join('\n')}';
  }

  /// Lowercase set of every stored contact's display name + aliases — the vocabulary a router
  /// `:contact` slot may match, so a fact-recall template only fires for a real person.
  /// The full displayNames of known contacts — passed to the cloud router so it reuses an
  /// existing contact ("Katherine" -> "Katherine Zinger") instead of minting a duplicate.
  Set<String> _knownContactNames() {
    final s = <String>{};
    for (final r in store.values) {
      if (r['typeId'] != 'contact') continue;
      final dn = (r['displayName'] as String?)?.trim();
      if (dn != null && dn.isNotEmpty) s.add(dn);
    }
    return s;
  }

  Set<String> _knownContactTokens() {
    final s = <String>{};
    for (final r in store.values) {
      if (r['typeId'] != 'contact') continue;
      final dn = (r['displayName'] as String?)?.toLowerCase().trim();
      if (dn != null && dn.isNotEmpty) s.add(dn);
      final a = r['aliases'];
      if (a is String) {
        for (final al in a.toLowerCase().split(',')) {
          final t = al.trim();
          if (t.isNotEmpty) s.add(t);
        }
      }
    }
    return s;
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
    // "track my water intake IN GLASSES" / "meals WITH CALORIES" carries a unit/field the shipped
    // template can't honor — don't let a keyword match pre-empt it; fall through to authoring.
    if (_customizationRe.hasMatch(d)) return null;
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
