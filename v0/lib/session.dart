/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'dart:async';

import 'automations.dart';
import 'capability_draft_store.dart';
import 'claude.dart';
import 'content_search.dart';
import 'conversation_ledger.dart';
import 'execution_coordinator.dart';
import 'reference.dart';
import 'generative.dart';
import 'interpreter.dart';
import 'migration.dart';
import 'operation_center.dart';
import 'people.dart';
import 'plan_proposal.dart';
import 'planning_artifact.dart';
import 'planner.dart';
import 'reminders.dart';
import 'routines.dart';
import 'router.dart';
import 'schema_registry.dart';
import 'storage_repository.dart';
import 'value_codec.dart';
import 'weekly_review.dart';

final _undoRe = RegExp(
    r"^(?:(?:no,?|never ?mind,?|wait,?|actually,?)\s+)?(?:(?:can|could|will) you\s+)?(?:please\s+)?(?:undo|revert|take (?:that|it) back|scratch that|roll (?:that|it) back)(?:\s+(?:that|it|this|please|(?:the|my|that) last (?:one|thing|entry|log)))?[.!]?$",
    caseSensitive: false);

// Contextual planner commands operate only on records the planner has explicitly
// published as visible or selected. This keeps pronouns deterministic: "these"
// never means a guessed set, and "the first one" never re-derives a hidden order.
final _plannerDeferRe = RegExp(
    r'^(?:defer|unschedule|move)\s+(.+?)\s+(?:to\s+)?(?:someday|later|the backlog)[.!]?$',
    caseSensitive: false);
final _plannerScheduleRe = RegExp(
    r'^(?:move|schedule|put)\s+(.+?)\s+(?:to|on|at|for)\s+(.+?)[.!]?$',
    caseSensitive: false);
final _plannerEstimateRe = RegExp(
    r'^(?:make|set|estimate)\s+(.+?)\s+(?:(?:to|at|for|as)\s+)?(\d+)\s*(minutes?|mins?|hours?|hrs?)[.!]?$',
    caseSensitive: false);
final _plannerCompleteRe = RegExp(
    r'^(?:complete|finish|mark(?:\s+as)?\s+done|check\s+off)\s+(.+?)[.!]?$',
    caseSensitive: false);
final _planWeekRe = RegExp(
  r'^(?:(?:can|could) you\s+|please\s+)?(?:help me\s+)?(?:plan|organize|schedule)\s+(?:my|the|this)\s+week[.!]?$',
  caseSensitive: false,
);
final _applyProposalRe = RegExp(
  r'^(?:apply|accept|use)(?:\s+all)?(?:\s+(?:of\s+)?(?:the|this|that))?\s+(?:plan|proposal)[.!]?$',
  caseSensitive: false,
);
final _dismissProposalRe = RegExp(
  r'^(?:dismiss|discard|cancel|forget)(?:\s+(?:the|this|that))?\s+(?:plan|proposal)[.!]?$',
  caseSensitive: false,
);
final _proposalMoveRe = RegExp(
  r'^move\s+(?:the\s+)?(first|second|third|fourth|fifth)(?:\s+(?:one|item))?\s+(?:in\s+the\s+proposal\s+)?to\s+(.+?)[.!]?$',
  caseSensitive: false,
);
final _proposalExcludeRe = RegExp(
  r'^(?:drop|remove|leave out)\s+(?:the\s+)?(first|second|third|fourth|fifth)(?:\s+(?:one|item))?(?:\s+from\s+the\s+proposal)?[.!]?$',
  caseSensitive: false,
);
final _morningPlanRe = RegExp(
  r'^(?:help me\s+)?(?:plan (?:my|the) (?:morning|day)|what should i focus on this morning)[.!]?$',
  caseSensitive: false,
);
final _relationshipPrepRe = RegExp(
  r'^(?:help me\s+)?prepare(?: me)? for (?:(?:seeing|meeting|talking to|a call with|dinner with|lunch with|coffee with)\s+)?(.+?)[.!]?$',
  caseSensitive: false,
);

// ---- Numbered-list corrections (reference-by-number over the last spoken readback) ----------
// The ordered list Plena last read back, captured from the interpreter's `enumerate` channel.
// "delete 2" / "complete 1" / "correct 3" resolve N against THIS — by recordId, never by re-derived
// order or fuzzy text — so a misheard item ("Zpack my clothes") is still trivially re-targetable.
class _EnumItem {
  final String id;
  final String
      typeId; // per-item: one readback can enumerate several types (facts + relationships)
  final String labelField; // the field "correct" replaces on THIS item's type
  final String
      spokenLabel; // fallback if the record vanishes before a reference
  _EnumItem(this.id, this.typeId, this.labelField, this.spokenLabel);
}

class _EnumCtx {
  final List<_EnumItem>
      items; // ordered exactly as spoken (1-based to the user)
  final String skillId; // diagnostics only
  _EnumCtx(this.items, this.skillId);
}

// A number/ordinal atom — STT hands us words ("one", "the second", "last"), not just digits.
const _refNum = r'(?:number\s+|no\.?\s*|#\s*|item\s+|the\s+)?'
    r'(\d{1,3}|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|'
    r'one|two|three|four|five|six|seven|eight|nine|ten|last(?:\s+one)?)';
final _refCompleteRe = RegExp(
    r'^(?:complete|finish|mark(?:\s+off)?|check(?:\s+off)?|tick(?:\s+off)?|cross\s+off|'
            r"i(?:'ve)?\s+(?:finished|did|completed|done)|done\s+with)\s+"
            r'(?:the\s+)?(?:todo|task|item|entry|reminder|one)?\s*' +
        _refNum +
        r'(?:\s+(?:as\s+)?(?:done|complete|completed|off))?[.!]?$',
    caseSensitive: false);
final _refDeleteRe = RegExp(
    r'^(?:delete|remove|drop|scratch|erase|get\s+rid\s+of|take\s+(?:off|out))\s+'
            r'(?:the\s+)?(?:todo|task|item|entry|reminder|one)?\s*' +
        _refNum +
        r'(?:\s+(?:from|off)\s+(?:my|the)\s+list)?[.!]?$',
    caseSensitive: false);
final _refCorrectRe = RegExp(
    // two-turn: "correct 1" -> re-speak next turn
    r'^(?:correct|fix|change|edit|replace|reword|rephrase|redo)\s+'
            r'(?:the\s+)?(?:todo|task|item|entry|reminder|one)?\s*' +
        _refNum +
        r'[.!]?$', caseSensitive: false);
final _refCorrectInlineRe = RegExp(
    // one-turn: "change 2 to buy oat milk"
    r'^(?:correct|fix|change|edit|replace|reword|rephrase|update|make)\s+'
            r'(?:the\s+)?(?:todo|task|item|entry|reminder|one)?\s*' +
        _refNum +
        r'\s+(?:to|into|read|say)\s+(?:say\s+)?(.+?)[.!]?$',
    caseSensitive: false);

/// Resolve a captured number/ordinal word to a 1-based position, or -1 for "last".
/// Returns 0 on an unrecognized token (never matched by the regexes, but defensive).
int _refPos(String tok) {
  final t = tok.toLowerCase().trim();
  if (t.startsWith('last')) return -1;
  final d = int.tryParse(t);
  if (d != null) return d;
  const words = {
    'first': 1,
    'one': 1,
    'second': 2,
    'two': 2,
    'third': 3,
    'three': 3,
    'fourth': 4,
    'four': 4,
    'fifth': 5,
    'five': 5,
    'sixth': 6,
    'six': 6,
    'seventh': 7,
    'seven': 7,
    'eighth': 8,
    'eight': 8,
    'ninth': 9,
    'nine': 9,
    'tenth': 10,
    'ten': 10,
  };
  return words[t] ?? 0;
}

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
  final List<String>
      domainKeywords; // a dispatched skill id containing one of these = "tried this"
  final List<String> aliases; // selection words ("tell me about reminders")
  const _TourChapter(this.id, this.gate, this.essence, this.tryLine,
      this.followOn, this.coda, this.domainKeywords, this.aliases);
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
    [
      'person',
      'contact',
      'interaction',
      'relation',
      'fact',
      'birthday',
      'alias'
    ],
    [
      'people',
      'person',
      'contact',
      'contacts',
      'friend',
      'friends',
      'relationship',
      'relationships'
    ],
  ),
  _TourChapter(
    'tracking',
    ['log-run'],
    "I come with runs, moods, meals, and a journal — and if I don't track something yet, say \"start tracking my water intake\" and I'll build it.",
    'You could say — "log a 3k run."',
    'That one\'s free to try — I\'ll undo it after if you like. Or say "next" for one last thing: how to read me.',
    "Logged — and I'll total it up whenever you ask. \"Undo that\" clears it.",
    [
      'run',
      'walk',
      'mood',
      'journal',
      'meal',
      'goal',
      'streak',
      'track',
      'water',
      'step'
    ],
    [
      'track',
      'tracking',
      'run',
      'running',
      'mood',
      'journal',
      'habit',
      'habits'
    ],
  ),
  _TourChapter(
    'movement',
    ['list-routines'],
    "I can put together a stretch or strength routine and then walk you through it, one move at a "
        "time, out loud — so you're not squinting at a screen on the floor.",
    'You could say — "create a stretching routine for my low back."',
    'Making one takes a moment and uses your credits. Or say "next" for one last thing: how to read me.',
    "It's yours now — say \"let's do\" it whenever, and I'll count you through.",
    ['routine'],
    [
      'routine',
      'routines',
      'stretch',
      'stretching',
      'exercise',
      'workout',
      'movement'
    ],
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
final _reclassifyRe = RegExp(
    r'^(?:no,?|actually,?|nope,?|wait,?)\s+that was (?:a |an )?(\w+)\.?$',
    caseSensitive: false);
const _activitySkill = {
  'run': 'log-run',
  'running': 'log-run',
  'jog': 'log-run',
  'jogging': 'log-run',
  'walk': 'log-walk',
  'walking': 'log-walk',
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
// Yes / no for the post-activation "is that what you wanted?" check. Kept separate from
// _activateRe (which is a COMMIT word) and _cancelRe (which backs out of a pending action) —
// this pair answers a question about something that already happened.
final _yesRe = RegExp(
    r"^(?:yes|yep|yeah|yup|correct|that'?s (?:it|right)|perfect|great|exactly)[.!]?$",
    caseSensitive: false);
final _noRe = RegExp(
    r"^(?:no|nope|nah|not (?:really|quite|what i wanted|it)|that'?s not (?:it|right|what i meant)"
    r"|wrong|forget it)[.!]?$",
    caseSensitive: false);

// confirms an authored-capability draft (Spec 02 §6.5: nothing registered until "activate")
final _activateRe = RegExp(
    r'^(activate|add it|yes,? add it|go ahead|do it|yes,? do it|yes)\.?$',
    caseSensitive: false);
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
final _impersonateRe = RegExp(
    r"\b(pretend(ing)? to be|impersonat(e|ing)|speak as (my|his|her|their)|write as (my|his|her|their))\b",
    caseSensitive: false);
// Schema-edit denial (DF-03): adding a field to an EXISTING tracker is a paid authoring edit.
final _schemaEditRe = RegExp(
    r'\badd (a |an )?[\w-]+( [\w-]+)? (field|score|metric|column|attribute) to my \w+',
    caseSensitive: false);
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
final _personalCueRe = RegExp(r"\b(i|i'?ve|i'?m|my|mine|our|ours|we|us|me)\b",
    caseSensitive: false);
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
    // Named eating disorders and compensatory framing. These reached the routine path completely
    // ungated: exercise-as-treatment for anorexia, or "burn off my binge", is the single worst
    // thing this app could produce, and no layer was catching it.
    r"|anorexi\w*|bulimi\w*|eating disorder|binge\w*|purging"
    r"|burn(?:ing)? off (?:my |the )?(?:binge|meal|food|calories|dinner|lunch)"
    r"|compensate for (?:my |the )?(?:binge|meal|eating)"
    r"|cut down harder|so i can cut|eat less so", caseSensitive: false);
// ---- Routine creation / entry (Spec 16) -------------------------------------------------------
// "create a stretch routine for my low back" / "make me a chest day workout".
// The routine NOUN is REQUIRED (with it optional this swallowed "create a tracker to hide my
// eating" and skipped the safety floors). The FOCUS clause, by contrast, must be OPTIONAL: "create
// a stretching routine" with no "for X" is the most natural way to ask, and requiring the clause
// made it fall through to TRACKER authoring — which offered to build a "Log Stretching" tracker
// instead. Gerunds matter too: people say "stretching"/"strengthening", not "stretch"/"strength".
final _routineCreateRe = RegExp(
    r"^(?:can you |could you |please )?(?:create|make|build|put together|design|generate)\s+"
    r"(?:me\s+)?(?:a|an|my|some)?\s*"
    // Adjectives and durations between the article and the kind word. Without this, the phrase
    // the INJURY REDIRECT ITSELF tells the user to say — "create a gentle mobility routine" —
    // missed and fell through to paid TRACKER authoring. Same for "a quick stretching routine"
    // and "a 10 minute stretch routine".
    r"(?:(?:\d+[- ]?(?:minute|min)|gentle|quick|short|easy|light|simple|basic|daily|morning|"
    r"evening|full[- ]?body|beginner|advanced|deep|slow)\s+)*"
    r"(stretch(?:ing)?|strength(?:ening)?|mobility|flexibility|exercise|yoga)?\s*"
    r"(routine|workout|stretches|warm[- ]?up|session)"
    r"(?:\s+(?:for|to help with|targeting|around|to loosen|to open|to work|on)\s+(?:my\s+)?(.+?))?"
    r"[.!?]?$",
    caseSensitive: false);

// A "tracker"/"log"/"journal" ask is capability authoring, not a routine — "create a workout log"
// must keep going to the tracker path even though it contains "workout".
// "tracker"/"log"/"journal" words, and the routine nouns, as separate patterns. Which one comes
// FIRST decides the intent — see [_isTrackerAsk].
final _trackerWordRe = RegExp(r"\b(tracker|logger|log|journal|diary|track)\b",
    caseSensitive: false);
final _routineNounRe = RegExp(
    r"\b(routine|workout|stretches|warm[- ]?up|session)\b",
    caseSensitive: false);
// "let's do my low back routine" / "start chest day" / "run the shoulder routine"
final _routineDoRe = RegExp(
    r"^(?:(?:let'?s|lets)\s+)?(?:do|start|run|begin|play)\s+"
    r"(?:my|the|a)?\s*(.+?)\s*(?:routine|workout|session)?[.!?]?$",
    caseSensitive: false);

// ---- Routine player control words (Spec 16). Offline regex: free, deterministic, and available
// mid-workout with no cloud round-trip. Deliberately narrow so an ordinary command mid-run
// ("remind me to buy milk") falls through and routes normally instead of being swallowed.
final _routineNextRe = RegExp(
    r"^(?:next|done|got it|finished|ok(?:ay)?(?: done)?)[.!]?$",
    caseSensitive: false);
final _routineSkipRe = RegExp(
    r"^(?:skip(?: (?:this|it|that))?|pass|no(?:pe)?, ?skip)[.!]?$",
    caseSensitive: false);
final _routineBackRe = RegExp(
    r"^(?:back|go back|previous|last one|repeat that one)[.!]?$",
    caseSensitive: false);
final _routineRepeatRe = RegExp(
    r"^(?:repeat|again|say (?:that )?again|what(?:'| i)?s this one|how do i do (?:this|that)|what was that)\??[.!]?$",
    caseSensitive: false);
final _routinePauseRe = RegExp(
    r"^(?:pause|wait|hold on|hang on|one (?:sec|second|moment))[.!]?$",
    caseSensitive: false);
final _routineResumeRe = RegExp(
    r"^(?:go on|carry on|continue|resume|i'?m back|ready)[.!]?$",
    caseSensitive: false);
final _routineStopRe = RegExp(
    r"^(?:stop|quit|that'?s enough|i'?m done|end (?:it|the routine)|finish(?: up)?)[.!]?$",
    caseSensitive: false);

// authored ids are model output; keep them out of file paths and odd charsets
final _idRe = RegExp(r'^[a-z0-9_-]{1,64}$');

/// The visible cache of a reversible durable execution. Before-images and
/// execution state live only in [ExecutionCoordinator]'s device-local journal;
/// this cache carries the stable handle and user-facing description.
class _JournalEntry {
  final String? desc;
  final int
      id; // stable handle so a data-view snackbar can undo THIS entry, not the ring's tail
  _JournalEntry(this.desc, {required this.id});
}

/// Outcome of a manual (data-view) write — a VALUE, never an exception across the UI seam
/// (the engine's no-exceptions-outward posture). `message` is the act-then-describe line on
/// success or the actionable reason on failure; always shown (P2.8, no silent failure).
class ManualWrite {
  final bool ok;
  final String message;
  final int?
      undoId; // on success: the journal handle to pass to undoById for a TARGETED undo
  const ManualWrite.ok(this.message, {this.undoId}) : ok = true;
  const ManualWrite.fail(this.message)
      : ok = false,
        undoId = null;
}

/// One learned NLU corpus entry, shaped for the "Learned phrases" showcase (the UI never sees
/// the internal CorpusEntry). `template` is the raw surface (keyed for forget); `targetLabel` is
/// the human target (a skill's displayName, or a humanized generativeKind like "Gift ideas").
class LearnedFlow {
  final String template;
  final String targetLabel;
  final bool isGenerative;
  const LearnedFlow(this.template, this.targetLabel, this.isGenerative);
}

class Session {
  final String dataDir;
  final DateTime? _fixedClock;

  /// The clock, read live per access so a long-open app never freezes at launch
  /// time (Spec 03 §4 wants a per-turn snapshot). Tests/the demo pin it via the
  /// [clock] constructor arg for reproducibility.
  DateTime get now => _fixedClock ?? DateTime.now();
  late Map<String, Map<String, dynamic>> types;
  late SchemaRegistry schemaRegistry;
  final List<MigrationRepairItem> migrationRepairItems = [];
  final List<MigrationBackup> migrationBackups = [];
  final List<String> skillRepairIssues = [];
  final List<String> executionRepairIssues = [];
  final List<String> externalStorageIssues = [];
  late ConversationLedger conversationLedger;
  late OperationCenter operations;
  late CapabilityDraftStore capabilityDrafts;
  late PlanProposalStore planProposals;
  late WeeklyReviewStore weeklyReviews;
  late PlanningArtifactStore planningArtifacts;
  late Map<String, Map<String, dynamic>> skills;
  late Map<String, Map<String, dynamic>>
      templates; // binary-shipped tracker templates (Spec 05 §6)
  late Map<String, Map<String, dynamic>> store;
  late Interpreter interp;

  /// The AutomationRunner + Review Feed (Spec 04 §3.9). Fired after _dispatch's
  /// writes via the onWrite seam (§4.8); read-only results are delivered
  /// (pendingNudges / takeDeliveries), writing plans are HELD in
  /// [AutomationRunner.pendingReview] for the user's approval (Spec 02 §7.5).
  late AutomationRunner automations;
  late Router router;

  /// The shipped exercise catalogue that grounds routine authoring (Spec 16).
  late ExerciseCatalogue exercises;

  /// The in-flight figure fill, if any — awaited by tests, ignored by the app (figures are
  /// presentation and arrive after the routine is already usable).
  Future<void>? pendingFigureFill;
  String? _lastRoutineId;

  /// A live routine run, or null. Ephemeral like the Tour — losing it on app kill is acceptable.
  RoutineRun? _run;
  RoutineRun? get activeRun => _run;

  /// Set when a routine was asked for with no focus area ("create a stretching routine"); the next
  /// utterance supplies it. Holds the requested kind so "a STRENGTH routine" stays a strength one.
  String? _pendingRoutineKind;
  late CloudClient claude;
  late GenerativeService _generative;
  late StorageRepository repo;
  late ExecutionCoordinator executions;
  final StreamController<void> _storageChanges =
      StreamController<void>.broadcast();
  StreamSubscription<void>? _storageWatch;
  bool _turnInProgress = false;
  bool _storageRefreshInProgress = false;
  bool _storageRefreshPending = false;

  /// Fires after an external provider/file event has been reconciled into the
  /// live in-memory store. The UI rebuilds planner surfaces from this event.
  Stream<void> get storageChanges => _storageChanges.stream;

  /// A routine build awaiting a yes, when the confirm preference is on.
  Map<String, dynamic>? _pendingRoutineBuild;

  /// A just-activated capability awaiting the user's "is that what you wanted?" answer. A no
  /// removes it — the whole point is that a wrong build is reversible in one word.
  Map<String, dynamic>? _pendingCapabilityCheck;

  /// Ask before each paid authoring call? Read from config at init; false by default.
  bool confirmCloudSpend = false;
  final CloudClient? _injectedCloud;
  final StorageRepository? _injectedStorage;
  final ExecutionJournal? _injectedExecutionJournal;
  // The OS-notification adapter (Spec 04 §3.1). Null -> reminders still persist and
  // nudge on open, they just don't arm a native toast. The reconciled armed set is
  // DERIVED from the record store, so undo/delete cancel notifications for free.
  final NotificationScheduler? _scheduler;
  static const _journalMax = 25; // ring depth
  final List<_JournalEntry> _journal =
      []; // execution journal of REVERSIBLE (write) turns
  // the immediately-previous routed turn (write OR read), so a correction targets
  // the right thing: forget its template, and reverse it ONLY if it actually wrote.
  String? _lastTurnTemplate;
  bool _lastTurnWrote = false;
  // The immediately-previous WRITING dispatch {skillId, slots}, so a re-classification
  // ("no, that was a walk", F-14) can re-log the corrected activity carrying the slots.
  Map<String, dynamic>? _lastDispatch;
  String _outSource = 'clarify'; // telemetry: how this turn resolved
  int? _lastTurnExecutionId;

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
  String?
      _cloudStatus; // telemetry: cloud health this turn ('ok' or a CloudErrorKind name)
  // Rich debug-trace fields (dogfood diagnosis: read the turnlog instead of retrying) —
  // reset each turn in handle(), populated as the turn resolves.
  String? _outTemplate; // the corpus template matched, if a corpus route
  Map<String, dynamic>? _outSlots; // the slots dispatched into the skill
  final List<Map<String, dynamic>> _outWrites =
      []; // record ops this turn: {op,id,typeId}
  final List<Map<String, dynamic>> _outReads =
      []; // what each read RESOLVED to (diagnose wrong-match bugs)
  String?
      _outError; // exception type + message + stack, on the error path (never shown to the user)
  Map<String, dynamic>?
      _outDiag; // on a MISS: the near-miss (closest skill + score) it computed
  // A paused turn waiting for the user to supply a missing required slot (Spec 03
  // §6.3 ProvideSlot): {skillId, slots (partial), missing (remaining required names)}.
  // The next turn's input fills it and the completed skill dispatches.
  Map<String, dynamic>? _pendingFill;
  // A generative request paused for its missing contact param (Spec 03 §6.3, G-46): {kind,
  // template}. The next turn supplies the person and the synthesis runs.
  Map<String, dynamic>? _pendingGen;
  // The ordered list from the LAST numbered readback, so "delete 2" / "correct 1" resolve against
  // exactly what was spoken (Feature: numbered-list corrections). Survives intervening non-list
  // turns; replaced by the next readback, cleared by an empty one, never persisted.
  _EnumCtx? _enumCtx;
  // A correction paused for the user to re-speak an item's text ("correct 1" → "what should it
  // say?" → the answer). {id, typeId, labelField, oldLabel, n}. The safety net is the same journal
  // as every write, so "undo that" reverses an applied correction.
  Map<String, dynamic>? _pendingCorrection;
  // A validated-but-UNREGISTERED authored capability awaiting the user's "activate"
  // (Spec 02 §6.5 / G-18): {type, skill, typeId, skillId, displayName, examples}.
  Map<String, dynamic>? _pendingActivation;
  String?
      _pendingAuthorOffer; // DF-01: a "start tracking X" awaiting a yes before paid authoring
  // The Tour (guided "what can you do?"): {'chapter': String?, 'visited': Set, 'codaGiven': Set}.
  // Ephemeral, never persisted; dropped on app close or when a turn dispatches OUT of the current
  // chapter (the user moved on). A read/undo/clarify keeps it alive (the user is engaging as coached).
  Map<String, dynamic>? _pendingTour;
  // True iff THIS outer turn was a Tour navigation turn (open/enter/exit/map). Set by the tour
  // helpers, reset per turn in handle(). Used instead of `_outSource == 'tour'` because the
  // correction path overwrites _outSource (so a chapter entered via "no, I meant tracking" wasn't
  // seen as a tour turn and got killed). Fable review #10.
  bool _tourSpokeThisTurn = false;
  // Whether the in-process retrieval index is active this session. Authoring
  // grows the inventory and must re-index — but only when retrieval is on, so the
  // authoring path stays hermetic under init(retrieval: false), like init() itself.
  bool _retrievalEnabled = true;
  ContentSearchIndex?
      _contentIndex; // semantic content search (F-12); null until retrieval builds it
  PlannerContext _plannerContext = const PlannerContext();
  Map<String, ReferenceStore> _references =
      const {}; // reference KBs (Spec 13), loaded at init

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart); [storage]
  /// lets them inject a repository (in-memory / test double). Production leaves both
  /// null -> a live ClaudeClient over a FileStorageRepository.
  Session(this.dataDir,
      {DateTime? clock,
      CloudClient? cloud,
      StorageRepository? storage,
      ExecutionJournal? executionJournal,
      NotificationScheduler? scheduler,
      String? deviceDir})
      : _fixedClock = clock,
        _injectedCloud = cloud,
        _injectedStorage = storage,
        _injectedExecutionJournal = executionJournal,
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

  List<Map<String, dynamic>> get recordSyncConflicts =>
      repo is FileStorageRepository
          ? List.unmodifiable((repo as FileStorageRepository).recordConflicts)
          : const [];

  List<DefinitionConflict> get definitionSyncConflicts => repo
          is FileStorageRepository
      ? List.unmodifiable((repo as FileStorageRepository).definitionConflicts)
      : const [];

  bool resolveRecordSyncConflict(
    Map<String, dynamic> conflict, {
    required bool restoreOther,
  }) {
    final id = '${conflict['recordId']}';
    final field = '${conflict['field']}';
    final current = store[id];
    final fileRepo =
        repo is FileStorageRepository ? repo as FileStorageRepository : null;
    if (current == null || fileRepo == null) return false;
    if (restoreOther) {
      final updated = Map<String, dynamic>.from(current)
        ..[field] = conflict['value'];
      final result = _executeMutation(
        writes: [updated],
        deletes: const [],
        origin: 'sync-conflict-review',
        description: 'Resolved sync conflict for $field',
        frozenInputs: {'recordId': id, 'field': field},
      );
      if (result.state != ExecutionResultState.persisted &&
          result.state != ExecutionResultState.appliedInMemory) {
        return false;
      }
    }
    fileRepo.clearRecordConflicts(id, field);
    return true;
  }

  bool resolveDefinitionSyncConflict(
    DefinitionConflict conflict, {
    required bool useConflicting,
  }) {
    final fileRepo =
        repo is FileStorageRepository ? repo as FileStorageRepository : null;
    if (fileRepo == null) return false;
    fileRepo.resolveDefinitionConflict(
      conflict,
      useConflicting: useConflicting,
    );
    return true;
  }

  /// User-visible repair state across storage, schema, migration, execution,
  /// and conversation history. Diagnostics retain detail; the planner uses
  /// this bounded summary so degraded durability is never silent.
  List<String> get repairIssues => [
        ...corruptFiles.map((_) => 'A data file could not be read.'),
        if (repo is FileStorageRepository)
          ...(repo as FileStorageRepository)
              .recordConflicts
              .map((_) => 'A record field has a preserved sync conflict.'),
        if (repo is FileStorageRepository)
          ...(repo as FileStorageRepository)
              .definitionConflicts
              .map((_) => 'A data definition has a sync conflict.'),
        ...schemaRegistry.issues.map((_) => 'A data definition needs repair.'),
        ...skillRepairIssues
            .map((_) => 'A capability definition needs repair.'),
        ...migrationRepairItems.map((_) => 'A record migration needs repair.'),
        ...executionRepairIssues.map((_) => 'A recent change needs repair.'),
        ...externalStorageIssues
            .map((_) => 'The selected data folder could not be refreshed.'),
        ...conversationLedger.issues
            .map((_) => 'Conversation history needs repair.'),
        ...operations.issues.map((_) => 'Detached work history needs repair.'),
        ...capabilityDrafts.issues
            .map((_) => 'A pending capability draft needs repair.'),
        ...planProposals.issues.map((_) => 'A planning proposal needs repair.'),
        ...weeklyReviews.issues.map((_) => 'A weekly review needs repair.'),
        ...planningArtifacts.issues
            .map((_) => 'A planning artifact needs repair.'),
      ];

  /// [retrieval] builds the deterministic in-process embedding index. Tests may
  /// pass false when routing itself is not under test, keeping fixtures minimal.
  /// [onPhase] receives a line at the start/end of each init phase — the app writes
  /// these to its diagnostics log, so a startup HANG shows the last phase that began.
  Future<void> init(
      {bool retrieval = true,
      bool watchStorage = false,
      void Function(String msg)? onPhase}) async {
    final sw = Stopwatch()..start();
    void phase(String msg) =>
        onPhase?.call('init: $msg (+${sw.elapsedMilliseconds}ms)');
    phase('start');
    repo = _injectedStorage ??
        FileStorageRepository(dataDir, deviceDir: _deviceDir);
    skills = repo.loadDefs('skills', 'skillId');
    templates = repo.loadDefs('templates', 'templateId');
    final automationDefs = repo.loadDefs('automations', 'automationId');
    final typeSources = repo is FileStorageRepository
        ? (repo as FileStorageRepository)
            .loadDefDocuments('types')
            .map((doc) => SchemaSource(doc.filename, doc.definition))
        : repo
            .loadDefs('types', 'typeId')
            .entries
            .map((entry) => SchemaSource('${entry.key}.json', entry.value));
    schemaRegistry = SchemaRegistry.hydrate(
      typeSources,
      skills: skills,
      automations: automationDefs,
    );
    types = Map<String, Map<String, dynamic>>.from(schemaRegistry.all);
    store = repo.loadRecords();
    final executionJournal = _injectedExecutionJournal ??
        (repo is FileStorageRepository
            ? FileExecutionJournal((repo as FileStorageRepository).deviceDir)
            : MemoryExecutionJournal());
    conversationLedger = repo is FileStorageRepository
        ? FileConversationLedger((repo as FileStorageRepository).deviceDir)
        : MemoryConversationLedger();
    final localDir = repo is FileStorageRepository
        ? (repo as FileStorageRepository).deviceDir
        : _deviceDir;
    operations = OperationCenter(
      path: localDir == null ? null : '$localDir/operations.json',
      clock: () => now,
    );
    capabilityDrafts = CapabilityDraftStore(
      path: localDir == null ? null : '$localDir/pending-capability.json',
    );
    _pendingActivation = capabilityDrafts.active;
    planProposals = PlanProposalStore(
      path: localDir == null ? null : '$localDir/plan-proposal.json',
    );
    weeklyReviews = WeeklyReviewStore(
      path: localDir == null ? null : '$localDir/weekly-review.json',
    );
    planningArtifacts = PlanningArtifactStore(
      path: localDir == null ? null : '$localDir/planning-artifacts.json',
    );
    executionRepairIssues
      ..clear()
      ..addAll(executionJournal.issues);
    executions = ExecutionCoordinator(
      repository: repo,
      store: store,
      journal: executionJournal,
      recordValidator: (record, projectedStore) {
        final type = types[record['typeId']];
        if (type == null) {
          throw ValueCodecError(
            'unknown_record_type',
            'No active schema exists for ${record['typeId']}.',
          );
        }
        record.putIfAbsent('_schemaVersion', () => typeVersion(type));
        return const ValueCodec().validateRecord(
          type,
          record,
          records: projectedStore,
          dataRoot: dataDir,
        );
      },
    );
    final recoveredExecutions = executions.recover();
    _journal
      ..clear()
      ..addAll(executions.completed
          .where((record) => record.visible)
          .map((record) => _JournalEntry(
                record.description,
                id: record.id,
              )));
    if (recoveredExecutions.isNotEmpty) {
      phase('recovered ${recoveredExecutions.length} interrupted execution(s)');
    }
    phase(
        'loaded ${types.length} types, ${skills.length} skills, ${store.length} records');
    if (schemaRegistry.issues.isNotEmpty) {
      phase('WARNING: ${schemaRegistry.issues.length} schema repair item(s): '
          '${schemaRegistry.issues.map((issue) => '${issue.code}:${issue.source}').join(', ')}');
    }
    final r = repo;
    if (r is FileStorageRepository && r.corruptFiles.isNotEmpty) {
      // P2.8: never drop a bad file on the floor — surface it in diagnostics for repair.
      phase(
          'WARNING: skipped ${r.corruptFiles.length} unreadable file(s), surfaced for repair: ${r.corruptFiles.join(', ')}');
    }
    // Bring records forward only through an explicit contiguous migration
    // chain. Failed/future records retain their exact disk form but are parked
    // outside typed reads and exposed as repair items.
    migrationRepairItems.clear();
    migrationBackups.clear();
    var migrated = 0, tooNew = 0, failed = 0;
    for (final e in store.entries.toList()) {
      final td = types[e.value['typeId']];
      if (td == null) {
        migrationRepairItems.add(MigrationRepairItem(
          recordId: e.key,
          typeId: '${e.value['typeId']}',
          code: 'unknown_record_type',
          message: 'The record type is not active in the schema registry.',
          rawRecord: Map<String, dynamic>.from(e.value),
        ));
        store.remove(e.key);
        failed++;
        continue;
      }
      if (isFutureVersioned(e.value, td)) {
        migrationRepairItems.add(MigrationRepairItem(
          recordId: e.key,
          typeId: '${e.value['typeId']}',
          code: 'version_too_new',
          message:
              'This record needs schema version ${recordVersion(e.value)}, '
              'but this app has version ${typeVersion(td)}.',
          rawRecord: Map<String, dynamic>.from(e.value),
        ));
        store.remove(e.key);
        tooNew++;
        continue;
      }
      final m = migrateRecord(
        e.value,
        td,
        records: store,
        dataRoot: dataDir,
      );
      if (m.failure != null) {
        migrationRepairItems.add(MigrationRepairItem(
          recordId: e.key,
          typeId: '${e.value['typeId']}',
          code: m.failure!.code,
          message: m.failure!.message,
          rawRecord: Map<String, dynamic>.from(e.value),
        ));
        store.remove(e.key);
        failed++;
        continue;
      }
      if (m.changed) {
        try {
          if (repo is FileStorageRepository) {
            migrationBackups.add(
              (repo as FileStorageRepository)
                  .backupForMigration(e.value, typeVersion(td)),
            );
          }
          repo.persist(m.record);
          store[e.key] = m.record;
          migrated++;
        } catch (error) {
          migrationRepairItems.add(MigrationRepairItem(
            recordId: e.key,
            typeId: '${e.value['typeId']}',
            code: 'migration_persist_failed',
            message: '$error',
            rawRecord: Map<String, dynamic>.from(e.value),
          ));
          store.remove(e.key);
          failed++;
        }
      }
    }
    if (migrated > 0 || tooNew > 0 || failed > 0) {
      phase('migrated $migrated record(s) to current schema'
          '${tooNew > 0 ? '; $tooNew from a newer app parked' : ''}'
          '${failed > 0 ? '; WARNING: $failed migration repair item(s) parked' : ''}');
    }
    // Reference knowledge bases (Spec 13): shipped, read-only datasets (nutrition calories) —
    // load once; a missing file yields an empty store (the feature just goes quiet).
    _references = {'nutrition': ReferenceStore.load(dataDir, 'nutrition')};
    // The shipped exercise catalogue (Spec 16). A missing/corrupt file yields an EMPTY catalogue:
    // routine authoring then declines honestly and nothing else in the app is affected.
    exercises = ExerciseCatalogue.load(dataDir);
    interp = Interpreter(types, now, references: _references);
    // A user-authored skill can outlive a rejected/missing type definition. Park
    // only that capability and surface repair state; one bad definition must not
    // make every unrelated planner capability unavailable at startup.
    skillRepairIssues.clear();
    for (final entry in skills.entries.toList()) {
      try {
        interp.validateSkill(entry.value);
      } catch (error) {
        skillRepairIssues.add('${entry.key}: $error');
        skills.remove(entry.key);
      }
    }
    if (skillRepairIssues.isNotEmpty) {
      phase('WARNING: parked ${skillRepairIssues.length} invalid skill(s): '
          '${skillRepairIssues.join('; ')}');
    }
    phase('validated ${skills.length} active skills');
    // Automations registry (Spec 01 §4.4 / Spec 04 §3.9): loaded like types/skills;
    // an absent automations/ folder is simply an empty registry (zero behavior change).
    final autoRepo = repo;
    final autoState = autoRepo is FileStorageRepository
        ? autoRepo.loadAutomationState()
        : <String, DateTime>{};
    automations = AutomationRunner(
      types: types,
      skills: skills,
      store: store,
      clock: () => now,
      persist: repo.persist,
      lastFired: autoState, // the runner mutates this map in place
      onFired: (_, __) {
        if (autoRepo is FileStorageRepository)
          autoRepo.saveAutomationState(autoState);
      },
    );
    automations.register({
      for (final entry in automationDefs.entries)
        if (!schemaRegistry.inertAutomations.contains(entry.key))
          entry.key: entry.value,
    });
    automations.tick(
        now); // fire any schedule automation whose cron time passed since last open
    if (automations.statuses.isNotEmpty) {
      phase(
          'automations: ${automations.statuses.map((a) => '${a.automationId}=${a.state}').join(', ')}');
    }
    // schedule catch-up outcome (diagnosable from the log, not a black box)
    if (automations.deliveries.isNotEmpty ||
        automations.pendingReview.isNotEmpty ||
        automations.refusals.isNotEmpty) {
      phase('automation tick: ${automations.deliveries.length} delivered, '
          '${automations.pendingReview.length} held, ${automations.refusals.length} refused');
    }
    router = Router.load('$dataDir/corpus.json', now,
        learnedPath: '$dataDir/corpus-learned.json');
    if (router.corruptFiles.isNotEmpty) {
      // Routing is gutted without the seed corpus — say so loudly rather than let every utterance
      // clarify-fail for no visible reason (P2.8).
      phase(
          'WARNING: the seed corpus could not be read (${router.corruptFiles.join(', ')}) — '
          'routing is degraded; reinstall or restore that file to repair.');
    }
    claude = _injectedCloud ??
        ClaudeClient(
          usagePath: '${_deviceDir ?? dataDir}/cloud-usage.json',
        );
    _generative = GenerativeService(claude);
    _retrievalEnabled = retrieval;
    if (retrieval) {
      phase('building in-process retrieval index…');
      await router.buildRetrievalIndex(skills);
      _contentIndex = ContentSearchIndex();
      await _contentIndex!.build(
          store.values); // semantic content search (F-12); no-op if server down
      phase('retrieval index built');
    } else {
      phase('retrieval disabled');
    }
    _ensureProactiveRelationshipArtifact();
    await _reconcileReminders(); // arm any future reminders already on disk (re-open)
    if (watchStorage && repo is FileStorageRepository) {
      _storageWatch = (repo as FileStorageRepository).watchChanges().listen(
        (_) => _queueStorageRefresh(),
        onError: (Object error) {
          externalStorageIssues
            ..clear()
            ..add('$error');
          if (!_storageChanges.isClosed) _storageChanges.add(null);
        },
      );
    }
    phase('reminders reconciled — READY');
  }

  void _queueStorageRefresh() {
    _storageRefreshPending = true;
    if (_turnInProgress || _storageRefreshInProgress) return;
    unawaited(_refreshExternalStorage());
  }

  Future<void> _refreshExternalStorage() async {
    if (_turnInProgress || _storageRefreshInProgress) return;
    _storageRefreshInProgress = true;
    try {
      while (_storageRefreshPending && !_turnInProgress) {
        _storageRefreshPending = false;
        Map<String, Map<String, dynamic>> loaded;
        try {
          loaded = repo.loadRecords();
          externalStorageIssues.clear();
        } catch (error) {
          externalStorageIssues
            ..clear()
            ..add('$error');
          if (!_storageChanges.isClosed) _storageChanges.add(null);
          break;
        }
        final accepted = <String, Map<String, dynamic>>{};
        for (final entry in loaded.entries) {
          final type = types[entry.value['typeId']];
          if (type == null || isFutureVersioned(entry.value, type)) continue;
          final migrated = migrateRecord(
            entry.value,
            type,
            records: loaded,
            dataRoot: dataDir,
          );
          if (migrated.failure == null) accepted[entry.key] = migrated.record;
        }
        store
          ..clear()
          ..addAll(accepted);
        await _contentIndex?.build(store.values);
        await _reconcileReminders();
        if (!_storageChanges.isClosed) _storageChanges.add(null);
      }
    } finally {
      _storageRefreshInProgress = false;
    }
  }

  Future<void> dispose() async {
    await _storageWatch?.cancel();
    await _storageChanges.close();
  }

  /// Re-derive the armed notification set from the record store and reconcile the
  /// OS scheduler to it. Idempotent, so calling it every turn + on open never
  /// double-arms. A scheduler failure is contained — it must never break a turn.
  Future<void> _reconcileReminders() async {
    final sched = _scheduler;
    if (sched == null) return;
    try {
      await reconcileReminders(sched, store, now);
    } catch (_) {
      /* an OS notification hiccup is not worth failing the turn over */
    }
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
        RegExp(
            r"^(?:(?:tell|show) me (?:more )?about |what about |how about |let'?s (?:do|try|hear about) |i'?d like |can we do |about )"),
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
    final visited =
        prior == null ? <String>{} : (prior['visited'] as Set).cast<String>();
    final codaGiven =
        prior == null ? <String>{} : (prior['codaGiven'] as Set).cast<String>();
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
    _pendingTour = {
      'chapter': null,
      'visited': visited,
      'codaGiven': codaGiven
    };
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
    final privacy = prior ==
            null // only on a brand-new tour, never on a repeat while one is live
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
      if (has('log-mood'))
        '• Mood — "I\'m feeling great", "how have I been feeling"',
      if (has('log-journal'))
        '• Journal — "journal that today was a good day", "read my journal"',
      if (has('list-routines'))
        '• Movement — "create a stretching routine for my low back", then "let\'s do low back" '
            'and I\'ll walk you through it',
      if (has('remember-person-fact'))
        '• People — "remember that Mia is Sarah\'s daughter", "what do I know about Mia", "talked to Sam about the trip", "when did I last talk to Sam"',
      if (has('set-birthday'))
        '• Birthdays — "Sarah\'s birthday is july 16", "whose birthday is coming up"',
      if (has('set-alias'))
        '• Nicknames — "Sarah\'s nickname is Mum", then "when did I last talk to Mum"',
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
    if (m(['routine', 'stretch', 'exercise', 'workout', 'movement']) &&
        has('list-routines')) {
      return 'For movement you can say: "create a stretching routine for my low back" or '
          '"make me a strength workout for chest" — I\'ll build it once and keep it. Then '
          '"let\'s do low back" and I\'ll walk you through it a move at a time; say "next", '
          '"skip", "back", "repeat", "pause" or "stop" as you go. Ask "list my routines", '
          '"when did I last do chest day", or "what\'s my routine streak".';
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
    if (m(['people', 'contact', 'friend', 'relationship']) &&
        has('remember-person-fact')) {
      return 'For people: "remember that Mia is Sarah\'s daughter", "what do I know about Mia", '
          '"talked to Sam yesterday", "how old is Sarah", "when did I last talk to Sam".';
    }
    if (m(['birthday', 'bday']) && has('set-birthday')) {
      return 'For birthdays: "Sarah\'s birthday is july 16", "when is Sarah\'s birthday", "whose birthday is coming up".';
    }
    if (m(['meal', 'food', 'eat', 'calorie']) && has('log-meal')) {
      return 'For meals: "I had eggs for breakfast", "what did I eat today", "how many calories have I had today".';
    }
    if (m([
      'water',
      'hydrat',
      'step',
      'weight',
      'reading',
      'medication',
      'meds',
      'track'
    ])) {
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
  void _normalizeTypedSlots(
      Map<String, dynamic>? skill, Map<String, dynamic> slots, DateTime now) {
    final inputs = skill?['inputs'] as List?;
    if (inputs == null) return;
    for (final i in inputs) {
      if (i is! Map) continue;
      final name = i['name'], type = i['type'];
      if (name is! String || slots[name] is! String) continue;
      if (type == 'date')
        slots[name] = router.resolveDate(slots[name] as String, now);
      // a FORWARD-intent date (e.g. create-task.dueDate): a bare month-day that already passed
      // this year rolls to next year — no due dates in the past (reviewer b #6).
      if (type == 'futuredate')
        slots[name] = router.resolveFutureDate(slots[name] as String, now);
      if (type == 'datetime')
        slots[name] = router.resolveDateTime(slots[name] as String, now);
      // a PAST-event date (e.g. log-interaction.at): a bare "tuesday" is the PREVIOUS Tuesday, not
      // the next — else a past interaction gets stamped with a future date (reviews a#4 / b#2).
      if (type == 'pastday')
        slots[name] = router.resolvePastday(slots[name] as String, now);
    }
  }

  /// Normalise a raw slot value from any router before it reaches a resolver or gets persisted.
  /// The cloud sometimes fills an absent optional slot with a sentinel ("none"/"null") or a blank
  /// string; both must become a real null so the skill's own isNull branches fire and no
  /// whitespace-only "note"/"kind" is stored as a present value (reviewer b #7).
  static dynamic _sanitizeSlot(dynamic v) {
    if (v is! String) return v;
    final t = v.trim();
    if (t.isEmpty || t.toLowerCase() == 'none' || t.toLowerCase() == 'null')
      return null;
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

  /// Operational state that is not already represented as a dated planner
  /// object. Today renders these inline so scheduler degradation, automation
  /// deliveries, and held writes cannot disappear behind the old greeting.
  List<String> plannerNotices() => [
        if (_scheduler?.unavailableReason() case final reason?) '⚠️ $reason',
        for (final delivery in automations.deliveries) '✨ ${delivery.text}',
        for (final pending in automations.pendingReview)
          '📋 ${pending.preview ?? pending.description} (from ${pending.automationId})',
      ];

  /// Current planner truth, projected across tasks, reminders, routines, and
  /// relationship dates. The UI reads this directly; it never converts taps
  /// into synthetic English commands.
  TodayProjection todayProjection() {
    _ensureProactiveRelationshipArtifact();
    final latest =
        executions.completed.where((entry) => entry.visible).lastOrNull;
    return buildTodayProjection(
      store,
      now,
      latestChange: latest == null || latest.description == null
          ? null
          : PlannerChange(
              executionId: latest.id,
              description: latest.description!,
              origin: latest.origin,
              at: DateTime.parse(latest.createdAt),
            ),
    );
  }

  PlanProjection planProjection(
    DateTime selectedDay, {
    int dailyCapacityMinutes = 8 * 60,
  }) =>
      buildPlanProjection(
        store,
        now,
        selectedDay: selectedDay,
        dailyCapacityMinutes: dailyCapacityMinutes,
      );

  List<PlannerSignal> plannerSignals({int dailyCapacityMinutes = 8 * 60}) =>
      buildPlannerSignals(
        store,
        now,
        dailyCapacityMinutes: dailyCapacityMinutes,
      );

  PlannerEngagementSnapshot get plannerEngagement =>
      buildPlannerEngagement(store, planningArtifacts.history);

  PlanProposal? get activePlanProposal => planProposals.active;

  WeeklyReviewArtifact? get activeWeeklyReview => weeklyReviews.active;

  WeeklyReviewArtifact createWeeklyReview() {
    final review = buildWeeklyReviewArtifact(store, now);
    weeklyReviews.save(review);
    return review;
  }

  WeeklyReviewArtifact? setWeeklyReviewDecision(
    String recordId,
    ReviewDecision decision,
  ) {
    final review = weeklyReviews.active;
    if (review == null || review.state != WeeklyReviewState.draft) return null;
    final items = [
      for (final item in review.items)
        item.recordId == recordId ? item.copyWith(decision: decision) : item,
    ];
    final changed =
        review.copyWith(updatedAt: now, items: List.unmodifiable(items));
    weeklyReviews.save(changed);
    return changed;
  }

  WeeklyReviewArtifact? dismissWeeklyReview() {
    final review = weeklyReviews.active;
    if (review == null || review.state != WeeklyReviewState.draft) return null;
    final dismissed = review.copyWith(
      state: WeeklyReviewState.dismissed,
      updatedAt: now,
      message: 'Dismissed without changing tasks or goals.',
    );
    weeklyReviews.save(dismissed);
    return dismissed;
  }

  Future<ManualWrite> applyWeeklyReview() async {
    final review = weeklyReviews.active;
    if (review == null || review.state != WeeklyReviewState.draft) {
      return const ManualWrite.fail(
          'There is no active weekly review to apply.');
    }
    for (final item in review.items) {
      final record = store[item.recordId];
      if (record == null || reviewFingerprint(record) != item.baseFingerprint) {
        weeklyReviews.save(review.copyWith(
          state: WeeklyReviewState.stale,
          updatedAt: now,
          message: 'A reviewed item changed. Refresh before applying.',
        ));
        return const ManualWrite.fail(
          'A reviewed item changed after this review was made, so nothing was applied.',
        );
      }
      if (item.recordType == 'goal' && item.decision != ReviewDecision.keep) {
        return const ManualWrite.fail(
          'Goals can stay visible in this review; change goal status from its detail view.',
        );
      }
    }
    final taskItems =
        review.items.where((item) => item.recordType == 'task').toList();
    if (taskItems.isEmpty) {
      weeklyReviews.save(review.copyWith(
        state: WeeklyReviewState.applied,
        updatedAt: now,
        message: 'Reviewed goals; no task changes were needed.',
      ));
      return const ManualWrite.ok(
          'Reviewed the week — no task changes were needed.');
    }
    final result = await updateTaskPlans(
      [
        for (final item in taskItems)
          TaskPlanPatch(
            id: item.recordId,
            reviewDecision: item.decision.name,
          ),
      ],
      origin: 'weekly-review',
      description: 'applied ${taskItems.length} weekly review decisions',
      frozenInputs: {
        'weeklyReviewId': review.id,
        'decisions': {
          for (final item in taskItems) item.recordId: item.decision.name,
        },
      },
    );
    if (result.ok) {
      weeklyReviews.save(review.copyWith(
        state: WeeklyReviewState.applied,
        updatedAt: now,
        message: 'Applied as one reversible weekly review.',
      ));
    }
    return result;
  }

  List<PlanningArtifact> get activePlanningArtifacts =>
      planningArtifacts.activeAt(now);

  PlanningArtifact createMorningPlan() {
    final artifact = buildMorningPlanningArtifact(store, now);
    planningArtifacts.create(artifact);
    return artifact;
  }

  PlanningArtifact? createRelationshipPrep(String personName) {
    final artifact = buildRelationshipPrepArtifact(personName, store, now);
    if (artifact != null) planningArtifacts.create(artifact);
    return artifact;
  }

  PlanningArtifact? resolvePlanningArtifact(
    String id, {
    required bool accepted,
  }) =>
      planningArtifacts.resolve(
        id,
        accepted
            ? PlanningArtifactState.accepted
            : PlanningArtifactState.dismissed,
        now,
      );

  PlanningArtifact? deferPlanningArtifact(
    String id, {
    Duration forDuration = const Duration(days: 1),
  }) =>
      planningArtifacts.resolve(
        id,
        PlanningArtifactState.deferred,
        now,
        deferUntil: now.add(forDuration),
      );

  void _ensureProactiveRelationshipArtifact() {
    final nudge = buildTodayProjection(store, now).relationshipNudge;
    if (nudge == null || nudge.at == null) return;
    final day = nudge.at!;
    final occurrence =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    planningArtifacts.create(
      PlanningArtifact(
        id: 'relationship-suggestion-${nudge.id}-$occurrence',
        kind: PlanningArtifactKind.relationshipSuggestion,
        title: 'Prepare for ${nudge.title}',
        createdAt: now,
        updatedAt: now,
        state: PlanningArtifactState.draft,
        items: [
          PlanningArtifactItem(
            recordId: nudge.id,
            title: nudge.title,
            evidence: nudge.detail ?? 'Coming up',
          ),
        ],
        summary:
            'A timely suggestion based only on a date you saved. Keep it, dismiss it, or move it to tomorrow.',
      ),
    );
  }

  PlanProposal createWeeklyProposal() {
    final proposal = buildWeeklyPlanProposal(store, now);
    planProposals.save(proposal);
    return proposal;
  }

  PlanProposal? setProposalItemSelected(String taskId, bool selected) {
    final proposal = planProposals.active;
    if (proposal == null || proposal.state != PlanProposalState.draft) {
      return null;
    }
    final items = [
      for (final item in proposal.items)
        item.taskId == taskId ? item.copyWith(selected: selected) : item,
    ];
    return _saveRefinedProposal(proposal, items);
  }

  PlanProposal? moveProposalItem(String taskId, DateTime start) {
    final proposal = planProposals.active;
    if (proposal == null || proposal.state != PlanProposalState.draft) {
      return null;
    }
    final items = [
      for (final item in proposal.items)
        item.taskId == taskId
            ? item.copyWith(proposedStartAt: start, selected: true)
            : item,
    ];
    return _saveRefinedProposal(proposal, items);
  }

  PlanProposal _saveRefinedProposal(
    PlanProposal proposal,
    List<PlanProposalItem> items,
  ) {
    final selected = items.where((item) => item.selected).toList();
    final projected = {
      for (final entry in store.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (final item in selected) {
      final record = projected[item.taskId];
      if (record == null) continue;
      record
        ..['scheduledStartAt'] = item.proposedStartAt.toIso8601String()
        ..['estimatedMinutes'] = item.estimatedMinutes
        ..['status'] = 'scheduled';
    }
    final conflicts = buildPlanProjection(
      projected,
      now,
      selectedDay: now,
    ).conflicts.length;
    final refined = proposal.copyWith(
      updatedAt: now,
      items: List.unmodifiable(items),
      scheduledMinutes: selected.fold<int>(
        0,
        (sum, item) => sum + item.estimatedMinutes,
      ),
      conflictsAfter: conflicts,
    );
    planProposals.save(refined);
    return refined;
  }

  PlanProposal? dismissPlanProposal() {
    final proposal = planProposals.active;
    if (proposal == null || proposal.state != PlanProposalState.draft) {
      return null;
    }
    final dismissed = proposal.copyWith(
      state: PlanProposalState.dismissed,
      updatedAt: now,
      message: 'Dismissed without changing the plan.',
    );
    planProposals.save(dismissed);
    return dismissed;
  }

  Future<ManualWrite> applyPlanProposal() async {
    final proposal = planProposals.active;
    if (proposal == null || proposal.state != PlanProposalState.draft) {
      return const ManualWrite.fail(
          'There is no active plan proposal to apply.');
    }
    final selected = proposal.items.where((item) => item.selected).toList();
    if (selected.isEmpty) {
      return const ManualWrite.fail(
          'Select at least one proposed change first.');
    }
    for (final item in selected) {
      final record = store[item.taskId];
      if (record == null ||
          taskPlanFingerprint(record) != item.baseFingerprint) {
        final stale = proposal.copyWith(
          state: PlanProposalState.stale,
          updatedAt: now,
          message: 'The plan changed after this proposal was made. Refresh it.',
        );
        planProposals.save(stale);
        return const ManualWrite.fail(
          'The plan changed after this proposal was made, so nothing was applied. Refresh the proposal.',
        );
      }
    }
    final result = await updateTaskPlans(
      [
        for (final item in selected)
          TaskPlanPatch(
            id: item.taskId,
            scheduledStartAt: item.proposedStartAt,
            estimatedMinutes: item.estimatedMinutes,
          ),
      ],
      origin: 'planner-proposal',
      description: 'applied ${selected.length} proposed plan changes',
      frozenInputs: {
        'proposalId': proposal.id,
        'recordIds': selected.map((item) => item.taskId).toList(),
      },
    );
    if (result.ok) {
      planProposals.save(proposal.copyWith(
        state: PlanProposalState.applied,
        updatedAt: now,
        message: 'Applied as one reversible plan change.',
      ));
    }
    return result;
  }

  Future<String?> _proposalCommand(String utterance, DateTime clock) async {
    if (_planWeekRe.hasMatch(utterance)) {
      final proposal = createWeeklyProposal();
      _outSource = 'plan-proposal';
      _outSkill = 'propose-week';
      return proposal.items.isEmpty
          ? 'Your open work is already scheduled, blocked, or outside this week’s capacity — no changes proposed.'
          : 'I drafted ${proposal.items.length} changes for this week without applying them. Review the proposal, adjust it, or say “apply the proposal.”';
    }
    final proposal = planProposals.active;
    if (proposal == null || proposal.state != PlanProposalState.draft) {
      return null;
    }
    if (_applyProposalRe.hasMatch(utterance)) {
      final result = await applyPlanProposal();
      _outSource = 'plan-proposal';
      _outSkill = 'apply-plan-proposal';
      _lastTurnWrote = result.ok;
      return result.message;
    }
    if (_dismissProposalRe.hasMatch(utterance)) {
      dismissPlanProposal();
      _outSource = 'plan-proposal';
      _outSkill = 'dismiss-plan-proposal';
      return 'Dismissed the proposal — your plan was not changed.';
    }
    const indexes = {
      'first': 0,
      'second': 1,
      'third': 2,
      'fourth': 3,
      'fifth': 4,
    };
    final exclude = _proposalExcludeRe.firstMatch(utterance);
    if (exclude != null) {
      final index = indexes[exclude.group(1)!.toLowerCase()]!;
      if (index >= proposal.items.length)
        return 'That proposal item is not visible.';
      final item = proposal.items[index];
      setProposalItemSelected(item.taskId, false);
      _outSource = 'plan-proposal';
      _outSkill = 'refine-plan-proposal';
      return 'Removed “${item.title}” from the proposed changes. Nothing has been applied yet.';
    }
    final move = _proposalMoveRe.firstMatch(utterance);
    if (move != null) {
      final index = indexes[move.group(1)!.toLowerCase()]!;
      if (index >= proposal.items.length)
        return 'That proposal item is not visible.';
      final resolved = router.resolveDateTime(move.group(2)!, clock);
      final start = resolved == null ? null : DateTime.tryParse(resolved);
      if (start == null) return 'I found the proposal item, but not the time.';
      final item = proposal.items[index];
      moveProposalItem(item.taskId, start);
      _outSource = 'plan-proposal';
      _outSkill = 'refine-plan-proposal';
      return 'Moved “${item.title}” in the proposal. Nothing has been applied yet.';
    }
    return null;
  }

  String _startDetachedSynthesis(
    String kind,
    String title,
    Future<String> Function(Map<String, Map<String, dynamic>> snapshot) work,
  ) {
    final snapshot = {
      for (final entry in store.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    late String operationId;
    final operation = operations.start(
      kind: kind,
      title: title,
      input: {'recordCount': snapshot.length},
      run: (_) => _runDetachedLogged(
        operationId,
        kind,
        () => work(snapshot),
      ),
    );
    operationId = operation.id;
    _outSource = 'operation';
    _outSkill = kind;
    return 'Started $title in the background (${operation.id}). You can keep capturing and planning; I’ll show the result when it finishes.';
  }

  Future<String> _runDetachedLogged(
    String operationId,
    String kind,
    Future<String> Function() work,
  ) async {
    final startedAt = DateTime.now();
    final client = claude;
    final in0 = client is ClaudeClient ? client.inTokens : 0;
    final out0 = client is ClaudeClient ? client.outTokens : 0;
    final sonnetIn0 = client is ClaudeClient ? client.sonnetInTokens : 0;
    final sonnetOut0 = client is ClaudeClient ? client.sonnetOutTokens : 0;
    try {
      final result = await work();
      _logDetachedCompletion(
        operationId,
        kind,
        startedAt,
        result: result,
        in0: in0,
        out0: out0,
        sonnetIn0: sonnetIn0,
        sonnetOut0: sonnetOut0,
      );
      return result;
    } catch (error, stack) {
      _logDetachedCompletion(
        operationId,
        kind,
        startedAt,
        error: '$error\n$stack',
        in0: in0,
        out0: out0,
        sonnetIn0: sonnetIn0,
        sonnetOut0: sonnetOut0,
      );
      rethrow;
    }
  }

  void _logDetachedCompletion(
    String operationId,
    String kind,
    DateTime startedAt, {
    String? result,
    String? error,
    required int in0,
    required int out0,
    required int sonnetIn0,
    required int sonnetOut0,
  }) {
    final client = claude;
    final input = client is ClaudeClient
        ? (client.inTokens - in0) + (client.sonnetInTokens - sonnetIn0)
        : 0;
    final output = client is ClaudeClient
        ? (client.outTokens - out0) + (client.sonnetOutTokens - sonnetOut0)
        : 0;
    try {
      repo.logTurn({
        'at': startedAt.toIso8601String(),
        'ms': DateTime.now().difference(startedAt).inMilliseconds,
        'source': 'operation-completion',
        'operationId': operationId,
        'operationKind': kind,
        if (client is ClaudeClient && (input > 0 || output > 0))
          'cost': {
            'in': input,
            'out': output,
            'usd': ClaudeClient.costUsd(
                  client.inTokens - in0,
                  client.outTokens - out0,
                ) +
                ClaudeClient.sonnetCostUsd(
                  client.sonnetInTokens - sonnetIn0,
                  client.sonnetOutTokens - sonnetOut0,
                ),
          },
        if (result != null)
          'response':
              result.length > 240 ? '${result.substring(0, 240)}…' : result,
        if (error != null) 'error': error,
      });
    } catch (_) {
      // Diagnostic persistence must never convert successful cloud work into a
      // failed operation; the result remains durable in OperationCenter.
    }
  }

  void setPlannerContext(PlannerContext context) {
    _plannerContext = PlannerContext(
      visibleStart: context.visibleStart,
      visibleEnd: context.visibleEnd,
      selectedDay: context.selectedDay,
      selectedRecordIds: List.unmodifiable(context.selectedRecordIds),
      visibleRecordIds: List.unmodifiable(context.visibleRecordIds),
    );
  }

  List<String>? _plannerTargetIds(String phrase) {
    final target = phrase
        .toLowerCase()
        .replaceAll(RegExp(r'^(?:the|my)\s+'), '')
        .replaceAll(RegExp(r'\s+(?:tasks?|items?)$'), '')
        .trim();
    if (const {
      'these',
      'them',
      'selected',
      'the selected',
      'all these',
      'all of these',
    }.contains(target)) {
      return _plannerContext.selectedRecordIds.isEmpty
          ? null
          : List<String>.from(_plannerContext.selectedRecordIds);
    }
    if (const {'it', 'this', 'this one', 'selected one'}.contains(target)) {
      return _plannerContext.selectedRecordIds.length == 1
          ? [_plannerContext.selectedRecordIds.single]
          : null;
    }
    const positions = {
      'first': 0,
      'first one': 0,
      'one': 0,
      'second': 1,
      'second one': 1,
      'two': 1,
      'third': 2,
      'third one': 2,
      'three': 2,
      'fourth': 3,
      'fourth one': 3,
      'four': 3,
      'fifth': 4,
      'fifth one': 4,
      'five': 4,
    };
    final position = positions[target];
    if (position != null &&
        position < _plannerContext.visibleRecordIds.length) {
      return [_plannerContext.visibleRecordIds[position]];
    }
    return null;
  }

  Future<String?> _plannerContextCommand(
      String utterance, DateTime clock) async {
    Future<String> finish(
      Future<ManualWrite> operation, {
      required String skill,
    }) async {
      final result = await operation;
      _outSource = 'planner-context';
      _outSkill = skill;
      _lastTurnWrote = result.ok;
      return result.message;
    }

    final defer = _plannerDeferRe.firstMatch(utterance);
    if (defer != null) {
      final ids = _plannerTargetIds(defer.group(1)!);
      if (ids != null) {
        return finish(deferTasks(ids), skill: 'defer-task');
      }
    }

    final estimate = _plannerEstimateRe.firstMatch(utterance);
    if (estimate != null) {
      final ids = _plannerTargetIds(estimate.group(1)!);
      if (ids != null) {
        var minutes = int.parse(estimate.group(2)!);
        if (estimate.group(3)!.toLowerCase().startsWith('h')) minutes *= 60;
        return finish(
          updateTaskPlans([
            for (final id in ids)
              TaskPlanPatch(id: id, estimatedMinutes: minutes),
          ]),
          skill: 'estimate-task',
        );
      }
    }

    final complete = _plannerCompleteRe.firstMatch(utterance);
    if (complete != null) {
      final ids = _plannerTargetIds(complete.group(1)!);
      if (ids != null) {
        return finish(completeTasks(ids), skill: 'complete-task');
      }
    }

    final schedule = _plannerScheduleRe.firstMatch(utterance);
    if (schedule != null) {
      final ids = _plannerTargetIds(schedule.group(1)!);
      if (ids != null) {
        final phrase = schedule.group(2)!.trim();
        final resolved = router.resolveDateTime(phrase, clock);
        DateTime? start = resolved == null ? null : DateTime.tryParse(resolved);
        if (start == null) {
          final date = router.resolveFutureDate(phrase, clock);
          final day = date == null ? null : DateTime.tryParse(date);
          if (day != null) {
            start = DateTime(day.year, day.month, day.day, 9);
          }
        }
        if (start == null) {
          _outSource = 'clarify';
          return 'I found the tasks, but not the time. Try “tomorrow at 10am.”';
        }
        return finish(scheduleTasks(ids, start), skill: 'schedule-task');
      }
    }
    return null;
  }

  /// Direct planner completion. It shares the exact mutation/undo path used by
  /// voice, without synthesizing an utterance inside UI code.
  Future<ManualWrite> completeTask(String id) async {
    final record = store[id];
    if (record == null || record['typeId'] != 'task') {
      return const ManualWrite.fail('That task no longer exists.');
    }
    if (record['completed'] == true || record['status'] == 'done') {
      return const ManualWrite.fail('That task is already done.');
    }
    final updated = Map<String, dynamic>.from(record)
      ..['completed'] = true
      ..['status'] = 'done'
      ..['completedAt'] = now.toIso8601String();
    final result = _executeMutation(
      writes: [updated],
      deletes: const [],
      origin: 'planner-direct',
      description: 'completed "${record['description']}"',
      frozenInputs: {'recordId': id},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite ||
        result.record == null) {
      return const ManualWrite.fail(
          "Couldn't start that completion safely, so nothing changed.");
    }
    await _reconcileReminders();
    try {
      automations.notifyWrites([updated]);
    } catch (_) {
      // Automation containment is part of the mutation boundary: the user's
      // completion remains durable even if an automation definition is bad.
    }
    try {
      repo.logTurn({
        'source': 'planner-direct',
        'op': 'complete',
        'typeId': 'task',
        'recordId': id,
      });
    } catch (_) {
      // Internal diagnostics must never make a completed action fail.
    }
    return ManualWrite.ok(
      result.state == ExecutionResultState.appliedInMemory
          ? "Completed here, but couldn't finish saving it. I'll recover it next launch."
          : 'Completed — ${record['description']}.',
      undoId: result.record!.id,
    );
  }

  /// Apply one or more structured planner edits as a single durable execution.
  /// Voice context and direct manipulation call this same method; UI code never
  /// synthesizes English and a multi-select change produces one targeted undo.
  Future<ManualWrite> updateTaskPlans(
    List<TaskPlanPatch> patches, {
    String origin = 'planner-direct',
    String? description,
    Map<String, dynamic> frozenInputs = const {},
  }) async {
    if (patches.isEmpty) {
      return const ManualWrite.fail('No tasks were selected.');
    }
    if (patches.map((patch) => patch.id).toSet().length != patches.length) {
      return const ManualWrite.fail('A task was selected more than once.');
    }
    final updated = <Map<String, dynamic>>[];
    for (final patch in patches) {
      final record = store[patch.id];
      if (record == null || record['typeId'] != 'task') {
        return const ManualWrite.fail(
          'One of those tasks no longer exists, so nothing changed.',
        );
      }
      if (record['completed'] == true || record['status'] == 'done') {
        return ManualWrite.fail(
          '“${record['description']}” is already done, so nothing changed.',
        );
      }
      if (patch.estimatedMinutes != null &&
          (patch.estimatedMinutes! < 1 || patch.estimatedMinutes! > 24 * 60)) {
        return const ManualWrite.fail(
          'An estimate must be between 1 minute and 24 hours.',
        );
      }
      final next = Map<String, dynamic>.from(record);
      if (patch.clearSchedule) {
        next.remove('scheduledStartAt');
        if (next['status'] == 'scheduled' && patch.status == null) {
          next['status'] = 'inbox';
        }
      }
      if (patch.scheduledStartAt != null) {
        next['scheduledStartAt'] = patch.scheduledStartAt!.toIso8601String();
        next['status'] = patch.status ?? 'scheduled';
      } else if (patch.status != null) {
        next['status'] = patch.status;
      }
      if (patch.estimatedMinutes != null) {
        next['estimatedMinutes'] = patch.estimatedMinutes;
      }
      if (patch.description != null) {
        final description = patch.description!.trim();
        if (description.isEmpty) {
          return const ManualWrite.fail('A task description cannot be empty.');
        }
        next['description'] = description;
      }
      if (patch.complete) {
        next['completed'] = true;
        next['status'] = 'done';
        next['completedAt'] = now.toIso8601String();
      }
      if (patch.reviewDecision != null) {
        next['reviewDecision'] = patch.reviewDecision;
        if (patch.reviewDecision == 'defer') {
          next.remove('scheduledStartAt');
          next['status'] = 'someday';
        } else if (patch.reviewDecision == 'drop') {
          next['completed'] = true;
          next['status'] = 'done';
          next['completedAt'] = now.toIso8601String();
        }
      }
      updated.add(next);
    }

    final prospective = <String, Map<String, dynamic>>{
      ...store,
      for (final record in updated) '${record['id']}': record,
    };
    final validated = <Map<String, dynamic>>[];
    try {
      for (final record in updated) {
        validated.add(
          const ValueCodec().validateRecord(
            types['task']!,
            record,
            records: prospective,
            dataRoot: dataDir,
          ),
        );
      }
    } on ValueCodecError catch (error) {
      return ManualWrite.fail(error.message);
    }

    final count = validated.length;
    final result = _executeMutation(
      writes: validated,
      deletes: const [],
      origin: origin,
      description: description ??
          (count == 1
              ? 'updated “${validated.single['description']}” in the plan'
              : 'updated $count tasks in the plan'),
      frozenInputs: {
        ...frozenInputs,
        'recordIds': validated.map((record) => record['id']).toList(),
      },
    );
    if (result.state == ExecutionResultState.failedBeforeWrite ||
        result.record == null) {
      return const ManualWrite.fail(
        "Couldn't start that plan change safely, so nothing changed.",
      );
    }
    _clearSpokenCorrectionContext();
    try {
      automations.notifyWrites(validated);
    } catch (_) {
      // A planner edit remains durable even if an automation is malformed.
    }
    try {
      repo.logTurn({
        'source': origin,
        'op': 'update-plan',
        'count': count,
        'executionId': result.record!.id,
      });
    } catch (_) {
      // Internal diagnostics never determine whether the user action succeeds.
    }
    return ManualWrite.ok(
      result.state == ExecutionResultState.appliedInMemory
          ? "Updated here, but couldn't finish saving it. I'll recover it next launch."
          : count == 1
              ? 'Updated — ${validated.single['description']}.'
              : 'Updated $count tasks together.',
      undoId: result.record!.id,
    );
  }

  Future<ManualWrite> scheduleTasks(List<String> ids, DateTime firstStart) {
    var cursor = firstStart;
    final patches = <TaskPlanPatch>[];
    for (final id in ids) {
      patches.add(TaskPlanPatch(id: id, scheduledStartAt: cursor));
      final estimate =
          num.tryParse('${store[id]?['estimatedMinutes'] ?? ''}')?.round() ??
              30;
      cursor = cursor.add(Duration(minutes: estimate.clamp(1, 24 * 60)));
    }
    return updateTaskPlans(patches);
  }

  Future<ManualWrite> deferTasks(List<String> ids) => updateTaskPlans([
        for (final id in ids)
          TaskPlanPatch(id: id, clearSchedule: true, status: 'someday'),
      ]);

  Future<ManualWrite> resizeTask(String id, int estimatedMinutes) =>
      updateTaskPlans([
        TaskPlanPatch(id: id, estimatedMinutes: estimatedMinutes),
      ]);

  Future<ManualWrite> completeTasks(List<String> ids) => updateTaskPlans([
        for (final id in ids) TaskPlanPatch(id: id, complete: true),
      ]);

  ExecutionResult _executeMutation({
    required List<Map<String, dynamic>> writes,
    required List<String> deletes,
    required String origin,
    String? description,
    Map<String, dynamic> frozenInputs = const {},
    bool visible = true,
  }) {
    final result = executions.execute(
      writes: writes,
      deletes: deletes,
      origin: origin,
      description: description,
      frozenInputs: frozenInputs,
      visible: visible,
    );
    final record = result.record;
    if (record != null && visible) {
      _lastTurnExecutionId = record.id;
      _journal.add(_JournalEntry(record.description, id: record.id));
      if (_journal.length > _journalMax) _journal.removeAt(0);
    }
    return result;
  }

  // ---- Reference-by-number handlers (resolve N against the last numbered readback) -----------
  // All three journal a before-image and set _lastTurnWrote, so a following "undo that" reverses
  // them exactly like a spoken write. They label with the LIVE record value, so a corrected/undone
  // item self-heals. Diagnostics: source 'enumref', skill 'ref-{delete,complete,correct}'.

  /// True if [u] is a reference-by-number command against the live list — used by the pending-fill /
  /// pending-gen guards so "delete 2" mid-follow-up isn't swallowed as a slot value or a contact name.
  bool _looksLikeRefCommand(String u) =>
      _enumCtx != null &&
      (_refDeleteRe.hasMatch(u) ||
          _refCompleteRe.hasMatch(u) ||
          _refCorrectRe.hasMatch(u) ||
          _refCorrectInlineRe.hasMatch(u));

  /// Resolve a 1-based position (or -1 = "last") against the live enumeration context.
  ({
    Map<String, dynamic>? rec,
    _EnumItem? item,
    String label,
    int pos,
    String? fail
  }) _refResolve(int n) {
    final ctx = _enumCtx!;
    final count = ctx.items.length;
    final idx = n < 0 ? count - 1 : n - 1;
    if (idx < 0 || idx >= count) {
      final asked = n < 0 ? count : n;
      return (
        rec: null,
        item: null,
        label: '',
        pos: asked,
        fail:
            'That list only had $count item${count == 1 ? '' : 's'} — there\'s no number $asked.'
      );
    }
    final it = ctx.items[idx];
    final rec = store[it.id];
    if (rec == null) {
      return (
        rec: null,
        item: it,
        label: it.spokenLabel,
        pos: idx + 1,
        fail:
            'Number ${idx + 1} — "${it.spokenLabel}" — isn\'t there any more; '
            'it may have been deleted since I read the list.'
      );
    }
    return (
      rec: rec,
      item: it,
      label: '${rec[it.labelField] ?? it.spokenLabel}',
      pos: idx + 1,
      fail: null
    );
  }

  String _refDelete(int n) {
    _outSource = 'enumref';
    final r = _refResolve(n);
    if (r.fail != null) return r.fail!;
    final id = r.rec!['id'] as String;
    final result = _executeMutation(
      writes: const [],
      deletes: [id],
      origin: 'reference',
      description: 'deleted "${r.label}"',
      frozenInputs: {'position': r.pos, 'recordId': id},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return "I couldn't start that delete safely, so nothing changed.";
    }
    _lastTurnWrote = true;
    _outSkill = 'ref-delete';
    if (result.state == ExecutionResultState.appliedInMemory) {
      return 'Deleted number ${r.pos} here, but could not finish saving it. '
          "I'll recover it next launch.";
    }
    return 'Deleted number ${r.pos} — "${r.label}". (Say "undo that" to restore it.)';
  }

  String _refComplete(int n, DateTime now) {
    _outSource = 'enumref';
    final r = _refResolve(n);
    if (r.fail != null) return r.fail!;
    final typeId =
        r.item!.typeId; // this item's own type (a readback may mix types)
    final td = types[typeId];
    final doneField = _doneFieldOf(td);
    if (doneField == null) {
      return 'A ${_typeDisplayName(typeId)} isn\'t something I mark done — '
          'I can delete number ${r.pos}, or correct it.';
    }
    if (r.rec![doneField] == true)
      return 'Number ${r.pos} — "${r.label}" — was already done.';
    final id = r.rec!['id'] as String;
    final updated = Map<String, dynamic>.from(r.rec!)..[doneField] = true;
    final stampField = _attrNamed(td, 'completedAt', 'datetime');
    if (stampField != null) updated[stampField] = now.toIso8601String();
    if (_attrNamed(td, 'status', 'enum') != null) updated['status'] = 'done';
    final result = _executeMutation(
      writes: [updated],
      deletes: const [],
      origin: 'reference',
      description: 'completed "${r.label}"',
      frozenInputs: {'position': r.pos, 'recordId': id},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return "I couldn't start that completion safely, so nothing changed.";
    }
    _lastTurnWrote = true;
    _outSkill = 'ref-complete';
    if (result.state == ExecutionResultState.appliedInMemory) {
      return 'Marked number ${r.pos} done here, but could not finish saving it. '
          "I'll recover it next launch.";
    }
    return 'Marked number ${r.pos} done — "${r.label}".';
  }

  /// "correct N" — start the two-turn re-speak flow (pause for the new wording).
  String _refCorrectStart(int n) {
    _outSource = 'enumref';
    final r = _refResolve(n);
    if (r.fail != null) return r.fail!;
    _pendingCorrection = {
      'id': r.item!.id,
      'typeId': r.item!.typeId,
      'labelField': r.item!.labelField,
      'oldLabel': r.label,
      'n': r.pos,
    };
    _outSkill = 'ref-correct';
    return 'Number ${r.pos} says "${r.label}" — what should it say instead?';
  }

  /// "change N to X" — the one-turn form (no round-trip when the user already dictated).
  String _refCorrectInline(int n, String newText, DateTime now) {
    _outSource = 'enumref';
    final r = _refResolve(n);
    if (r.fail != null) return r.fail!;
    return _applyCorrection(r.item!.id, r.item!.typeId, r.item!.labelField,
        r.label, newText, r.pos, now);
  }

  String _applyCorrection(String id, String typeId, String labelField,
      String oldLabel, String newText, dynamic n, DateTime now) {
    _outSource = 'enumref';
    final rec = store[id];
    if (rec == null) {
      return 'That item — "$oldLabel" — isn\'t there any more; it may have been deleted since I read the list.';
    }
    // Coerce to the label field's declared type so "change 2 to 8" on a numeric field stores a
    // number, not a string (schema drift). Text fields (the common case) pass through unchanged.
    final attr = _attributeOf(typeId, labelField);
    if (attr == null) return 'That field is no longer editable.';
    final Object? coerced;
    try {
      coerced = const ValueCodec().coerce(
        attr,
        newText,
        records: store,
        dataRoot: dataDir,
      );
    } on ValueCodecError catch (error) {
      return "I couldn't use that correction: ${error.message}";
    }
    final updated = Map<String, dynamic>.from(rec)..[labelField] = coerced;
    final result = _executeMutation(
      writes: [updated],
      deletes: const [],
      origin: 'reference',
      description: 'changed "$oldLabel" to "$newText"',
      frozenInputs: {'position': n, 'recordId': id, 'newValue': newText},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return "I couldn't start that correction safely, so nothing changed.";
    }
    _lastTurnWrote = true;
    _outSkill = 'ref-correct';
    if (result.state == ExecutionResultState.appliedInMemory) {
      return 'Changed number $n here, but could not finish saving it. '
          "I'll recover it next launch.";
    }
    return 'Changed number $n to "$newText".';
  }

  Map<String, dynamic>? _attributeOf(String typeId, String field) {
    for (final raw in ((types[typeId]?['attributes'] as List?) ?? const [])) {
      if (raw is Map && raw['name'] == field) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  /// The first boolean attribute named `completed`/`done` on a type, or null (no done concept).
  String? _doneFieldOf(Map<String, dynamic>? td) {
    for (final a
        in ((td?['attributes'] as List?) ?? const []).whereType<Map>()) {
      if (a['valueType'] == 'boolean' &&
          (a['name'] == 'completed' || a['name'] == 'done')) {
        return a['name'] as String;
      }
    }
    return null;
  }

  /// A named attribute of a given valueType, or null.
  String? _attrNamed(Map<String, dynamic>? td, String name, String valueType) {
    for (final a
        in ((td?['attributes'] as List?) ?? const []).whereType<Map>()) {
      if (a['name'] == name && a['valueType'] == valueType) return name;
    }
    return null;
  }

  String _typeDisplayName(String typeId) =>
      (types[typeId]?['displayName'] as String?)?.toLowerCase() ?? typeId;

  String _undoLastInternal() {
    if (_journal.isEmpty) return 'Nothing to undo.';
    final entry = _journal.last; // walk back the ring, most-recent first
    final result = executions.undo(entry.id);
    if (result.state == ExecutionResultState.conflict) {
      return "I didn't undo that because the record changed afterward.";
    }
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return "I couldn't start that undo safely, so nothing changed.";
    }
    _journal.removeLast();
    if (result.state == ExecutionResultState.appliedInMemory) {
      return "I undid that here, but couldn't finish saving the undo. I'll recover it next launch.";
    }
    // say WHAT was reversed — a silent "Undone." can't be trusted as the safety net
    return entry.desc == null
        ? 'Undone.'
        : 'Undone — reversed: "${entry.desc}"';
  }

  // ---- Manual Library facade (Spec 07 §5.5 — editable records, G-49) --------------------------
  // Edits/deletes ride the SAME journal ring as spoken writes, so a following "undo that" reverses
  // a manual edit, and the view's snackbar UNDO is just a button on that ring (one undo system).

  String? _oneLineSummary(Map<String, dynamic> rec) {
    final td = types[rec['typeId']];
    for (final a
        in ((td?['attributes'] as List?) ?? const []).whereType<Map>()) {
      if (a['valueType'] == 'text' && rec[a['name']] is String)
        return rec[a['name']] as String;
    }
    return (rec['displayName'] ?? rec['description'] ?? rec['id'])?.toString();
  }

  /// Edit one schema-attribute value of a record in place (Spec 07 §5.5 tap-to-edit). Validates
  /// against the attribute's valueType, journals a before-image (undoable), persists, and keeps
  /// the reminder toast set + automations in sync — mirroring the F-15 correction path.
  Future<ManualWrite> editField(String id, String field, Object? value) async {
    final rec = store[id];
    if (rec == null)
      return const ManualWrite.fail('That record no longer exists.');
    final typeId = rec['typeId'] as String;
    final attr = ((types[typeId]?['attributes'] as List?) ?? const [])
        .whereType<Map>()
        .cast<Map<String, dynamic>>()
        .where((a) => a['name'] == field)
        .firstOrNull;
    if (attr == null)
      return ManualWrite.fail(
          '"$field" isn\'t an editable field of a ${_typeDisplayName(typeId)}.');
    final valueType = attr['valueType'] as String? ?? 'text';
    final required = attr['required'] == true;
    // enum: only a declared value is allowed (no free-typing an out-of-set value).
    if (valueType == 'enum') {
      final allowed =
          ((attr['enumValues'] as List?) ?? const []).map((e) => '$e').toList();
      if (!allowed.contains('$value')) {
        return ManualWrite.fail(
            '"$field" must be one of: ${allowed.join(', ')}.');
      }
    }
    final Object? coerced;
    try {
      coerced = const ValueCodec().coerce(
        attr,
        value,
        records: store,
        dataRoot: dataDir,
      );
    } on ValueCodecError catch (error) {
      return ManualWrite.fail(error.message);
    }
    final isEmpty = coerced == null ||
        (coerced is String && coerced.trim().isEmpty) ||
        (coerced is List && coerced.isEmpty);
    if (required && isEmpty) {
      return ManualWrite.fail(
          '"$field" is required for a ${_typeDisplayName(typeId)}.');
    }
    final updated = Map<String, dynamic>.from(rec);
    if (isEmpty && !required) {
      updated.remove(field);
    } else {
      updated[field] = coerced;
    }
    final result = _executeMutation(
      writes: [updated],
      deletes: const [],
      origin: 'manual-edit',
      description: 'edited ${_typeDisplayName(typeId)} — $field',
      frozenInputs: {'recordId': id, 'field': field, 'value': coerced},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite ||
        result.record == null) {
      return const ManualWrite.fail(
          "Couldn't start that edit safely, so nothing changed.");
    }
    _clearSpokenCorrectionContext();
    final undoId = result.record!.id;
    await _reconcileReminders(); // idempotent — re-arms/disarms an OS toast if a reminder time moved
    try {
      automations.notifyWrites([
        updated
      ]); // a manual edit is a user-origin write, same as a spoken one
    } catch (_) {/* contained — an automation must never break an edit */}
    repo.logTurn({
      'source': 'manual-edit',
      'op': 'edit',
      'typeId': typeId,
      'field': field
    });
    return ManualWrite.ok(
      result.state == ExecutionResultState.appliedInMemory
          ? "Updated here, but couldn't finish saving it. I'll recover it next launch."
          : 'Updated — $field.',
      undoId: undoId,
    );
  }

  /// Delete a record from the data view — journaled + a storage tombstone, so it's doubly
  /// reversible (the snackbar UNDO, or a later spoken "undo that").
  Future<ManualWrite> deleteRecord(String id) async {
    final rec = store[id];
    if (rec == null)
      return const ManualWrite.fail('That record no longer exists.');
    final summary = _oneLineSummary(rec) ?? 'that record';
    final typeId = rec['typeId']; // read before the store entry goes
    final result = _executeMutation(
      writes: const [],
      deletes: [id],
      origin: 'manual-edit',
      description: 'deleted "$summary"',
      frozenInputs: {'recordId': id},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite ||
        result.record == null) {
      return const ManualWrite.fail(
          "Couldn't start that delete safely, so nothing changed.");
    }
    _clearSpokenCorrectionContext();
    final undoId = result.record!.id;
    await _reconcileReminders();
    repo.logTurn({'source': 'manual-edit', 'op': 'delete', 'typeId': typeId});
    return ManualWrite.ok(
      result.state == ExecutionResultState.appliedInMemory
          ? "Deleted here, but couldn't finish saving it. I'll recover it next launch."
          : 'Deleted — $summary.',
      undoId: undoId,
    );
  }

  void _clearSpokenCorrectionContext() {
    _lastTurnWrote = false;
    _lastDispatch = null;
    _lastTurnTemplate = null;
  }

  // ---- Routines (Spec 16) ---------------------------------------------------------------------

  /// Is this a TRACKER ask rather than a routine ask? Decided by which word comes first: "create a
  /// workout LOG" asks for a tracker, while "create a stretching ROUTINE and track my flexibility"
  /// asks for a routine with a coda. A flat "contains a tracker word" veto flipped the second into
  /// paid tracker authoring — and, with the confirm now off by default, silently.
  static bool _isTrackerAsk(String u) {
    final t = _trackerWordRe.firstMatch(u);
    if (t == null) return false;
    final r = _routineNounRe.firstMatch(u);
    if (r == null)
      return true; // "create a stretch tracker" — no routine noun at all
    if (t.start < r.start) return true; // "create a log of my workouts"
    // The tracker word comes AFTER the routine noun. Adjacent, it is a compound noun and names the
    // thing wanted ("a workout log"). Separated by a conjunction, it is a coda on a routine request
    // ("a stretching routine AND track my flexibility") — which a flat contains-check flipped into
    // paid tracker authoring.
    final between = u.substring(r.end, t.start);
    return !RegExp(r'\b(and|then|also|plus)\b|,').hasMatch(between);
  }

  /// True when an utterance is a real command / system word rather than a plain answer to a
  /// pending question. Pending states use this so a question can never swallow a command.
  bool _isFreshCommand(String u) =>
      router.route(u, clock: now, contacts: _knownContactTokens()) != null ||
      _helpRe.hasMatch(u) ||
      _undoRe.hasMatch(u) ||
      _corrRe.hasMatch(u) ||
      _cancelRe.hasMatch(u) ||
      _tourNextRe.hasMatch(u) ||
      _tourDoneRe.hasMatch(u) ||
      _routineDoRe.hasMatch(u) ||
      _routineCreateRe.hasMatch(u) ||
      _routineNextRe.hasMatch(u) ||
      _routineSkipRe.hasMatch(u) ||
      _routineStopRe.hasMatch(u) ||
      _looksLikeRefCommand(u);

  /// Find a routine by (partial, case-insensitive) title — how "do my low back routine" resolves.
  Map<String, dynamic>? _findRoutine(String name) {
    final n = name.toLowerCase().trim();
    if (n.isEmpty) return null;
    final routines =
        store.values.where((r) => r['typeId'] == 'routine').toList();
    for (final r in routines) {
      if ('${r['title']}'.toLowerCase() == n) return r;
    }
    final partial = routines.where((r) {
      final t = '${r['title']}'.toLowerCase();
      return t.contains(n) || n.contains(t);
    }).toList();
    return partial.length == 1 ? partial.first : null;
  }

  /// Author a routine: Layer-1 safety gate → deterministic catalogue shortlist → one cloud call →
  /// deterministic validation → records. Act-then-describe: it writes and says what it did, and
  /// "undo that" reverses the whole routine in one go (all records ride one journal entry).
  Future<String> _createRoutine(
      String utterance, String focus, String? kindWord, DateTime now,
      {bool confirmed = false}) async {
    _outSource = 'routine-author';
    _outSkill = 'author-routine';
    // LAYER 1, before spending anything.
    //
    // The HARM floor first. Exercise-as-treatment for a self-harm or disordered-eating framing is
    // the single worst thing this feature could emit, and the generic floor that catches it lives
    // on the tracker-authoring path only — so it has to be checked here explicitly. (An earlier
    // version of this method reached neither this nor the medical floor: the routine block sat
    // ABOVE them. Order of checks is a safety property.)
    if (_harmfulRe.hasMatch(utterance)) {
      _outSource = 'refused';
      return "I won't build that. If you're struggling with how you're eating or with hurting "
          "yourself, please talk to someone you trust or a professional — I'm not the right help "
          'for it, and I could make it worse.';
    }
    // Then injury/medical framing: no treatment plan, but the redirect still offers something real.
    //
    // NOTE ON WHAT LEAVES THE DEVICE: this gate REFUSES — it does not sanitise. When it fires,
    // nothing at all is sent. When it MISSES, the utterance goes to the cloud verbatim (and is
    // persisted as `intent`). So the privacy property here is exactly the recall of this regex,
    // not a stripping step. Earlier comments claimed the condition was "stripped from the prompt";
    // no such code ever existed, and pretending otherwise hid where the real risk sits.
    if (looksLikeInjuryRequest(utterance)) {
      _outSource = 'refused';
      return "I can't build something around an injury or a condition — that's physio territory, "
          'and I\'d be guessing. I can put together a gentle, general mobility routine you could '
          'run past them first — say "create a gentle mobility routine" if you\'d like that.';
    }
    if (exercises.isEmpty) {
      return "I can't build routines right now — my exercise catalogue didn't load.";
    }
    if (claude is! RoutineAuthor) {
      return 'Building a routine needs the cloud, and I don\'t have a key set up for that yet.';
    }
    // The confirm preference has to cover THIS too. It previously gated only tracker authoring —
    // the cheapest call — while routine and figure authoring (both Sonnet, and the largest spend in
    // the app) went unasked, which made the Settings copy a false promise.
    if (confirmCloudSpend && !confirmed) {
      _pendingRoutineBuild = {
        'utterance': utterance,
        'focus': focus,
        'kind': kindWord
      };
      _outSource = 'author-offer';
      return 'Building that routine uses your Claude credits (and a second call to draw the '
          'movements the catalogue has no picture for). Want me to go ahead?';
    }
    final author = claude as RoutineAuthor;
    final kind = switch (kindWord?.toLowerCase()) {
      'strength' || 'workout' => 'strength',
      'mobility' => 'mobility',
      _ => 'stretch',
    };
    final shortlist = exercises.candidates(focus, kind: kind);
    final cat = ExerciseCatalogue.promptCatalogue(shortlist);

    AuthoredRoutine? routine;
    String? lastError;
    // ONE gated retry, fed the deterministic validation error — the same posture as capability
    // authoring. A second failure registers nothing: a half-routine is worse than none.
    for (var attempt = 0; attempt < 2 && routine == null; attempt++) {
      final res = await author.authorRoutine(utterance, cat,
          kind: kind, priorError: lastError);
      switch (res) {
        case CloudError(:final kind):
          return "I couldn't build that routine — ${cloudReason(kind)}";
        case CloudOk(:final value):
          try {
            routine = validateRoutine(value, exercises);
          } on RoutineInvalid catch (e) {
            lastError = e.message;
          }
      }
    }
    if (routine == null) {
      return "I couldn't put that together cleanly — try describing it a different way.";
    }
    final line = _writeRoutine(routine, utterance, now);
    // Figures LAST, separately, and NOT on the critical path. ~2/3 of catalogue exercises have no
    // illustration and a drawn figure beats nothing — but drawing six of them takes tens of
    // seconds, and making the user stare at nothing until it finishes is indistinguishable from a
    // hang. The routine is already written and usable; figures arrive when they arrive.
    pendingFigureFill = _fillMissingFigures(author, _lastRoutineId!);
    unawaited(pendingFigureFill!
        .catchError((_) {/* presentation only — never surfaces */}));
    return line;
  }

  /// Write a validated routine + its steps as ONE journaled turn, so "undo that" removes the whole
  /// thing rather than leaving orphan steps behind.
  String _writeRoutine(AuthoredRoutine r, String utterance, DateTime now) {
    // A pinned clock (tests, and the demo) makes microsecondsSinceEpoch repeat, which would
    // overwrite the first routine, graft its orphan steps onto the second, and make undo delete a
    // record its before-image claims never existed. Take the next free id instead.
    var rid = 'routine-${now.microsecondsSinceEpoch}';
    for (var n = 2; store.containsKey(rid); n++) {
      rid = 'routine-${now.microsecondsSinceEpoch}-$n';
    }
    final written = <Map<String, dynamic>>[];
    final routineRec = <String, dynamic>{
      'id': rid,
      'typeId': 'routine',
      'title': r.title,
      'focusArea': r.focusArea,
      'kind': r.kind,
      'intent': utterance,
      'estMinutes': r.estMinutes,
      'safetyNote': r.safetyNote,
      'status': 'active',
      'createdAt': now.toIso8601String().split('T').first,
    };
    written.add(routineRec);
    for (final s in r.steps) {
      final sid = '$rid-step-${s.order}';
      final rec = <String, dynamic>{
        'id': sid,
        'typeId': 'routine_step',
        'routine': rid,
        'order': s.order,
        'name': s.name,
        'instruction': s.instruction,
        'side': s.side,
        if (s.exerciseKey != null) 'exerciseKey': s.exerciseKey,
        if (s.durationSeconds != null) 'durationSeconds': s.durationSeconds,
        if (s.reps != null) 'reps': s.reps,
      };
      written.add(rec);
    }
    final result = _executeMutation(
      writes: written,
      deletes: const [],
      origin: 'routine-authoring',
      description: 'created the "${r.title}" routine',
      frozenInputs: {'utterance': utterance, 'routineId': rid},
    );
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return 'I built the routine draft, but could not start saving it safely, so nothing changed.';
    }
    _lastTurnWrote = true;
    _lastRoutineId = rid;
    if (result.state == ExecutionResultState.appliedInMemory) {
      return 'I built "${r.title}" here, but could not finish saving it. '
          "I'll recover it next launch — say \"undo that\" to drop it now.";
    }
    final illustrated = r.steps
        .where((s) =>
            s.exerciseKey != null &&
            exercises.byKey[s.exerciseKey]?.image != null)
        .length;
    _outSkill = 'author-routine';
    return 'Made "${r.title}" — ${r.steps.length} steps, about ${r.estMinutes} minutes'
        '${illustrated < r.steps.length ? ' ($illustrated with pictures)' : ''}. '
        'Say "let\'s do ${r.title}" when you\'re ready.';
  }

  /// Draw stick figures for the steps the shipped catalogue couldn't illustrate (Spec 16 §2).
  /// Best-effort by construction: a cloud failure, a malformed frame, or a figure that fails the
  /// render-only subset simply leaves that step as it already was — text-only, which is a
  /// first-class rendering because every instruction has to stand alone for the ear anyway.
  Future<void> _fillMissingFigures(
      RoutineAuthor author, String routineId) async {
    // Scoped to the routine JUST created. Scanning the whole store meant an older routine whose
    // figures had failed would fill the (capped) batch every time, so a new routine could be
    // starved of figures forever — while re-spending tokens redrawing the same rejected steps. It
    // also wrote figure fields onto OLD routines' steps inside this turn, outside its journal
    // entry, making those writes un-undoable.
    final needy = store.values
        .where((r) =>
            r['typeId'] == 'routine_step' &&
            r['routine'] == routineId &&
            r['figureA'] == null &&
            (r['exerciseKey'] == null ||
                exercises.byKey['${r['exerciseKey']}']?.image == null))
        .toList();
    if (needy.isEmpty) return;
    // De-duplicate by movement name: a routine that bookends with the same stretch should cost one
    // drawing, not two.
    final names = <String>{for (final r in needy) '${r['name']}'}.toList();
    final res = await author.authorFigures(names);
    if (res is! CloudOk<Map<String, dynamic>>)
      return; // no figures this time; steps stay text-only
    final byName = <String, StepFigure>{};
    for (final raw in (res.value['figures'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final fig = validateFigure(raw);
      if (fig != null) byName['${raw['name']}'.toLowerCase().trim()] = fig;
    }
    if (byName.isEmpty) return;
    final writes = <Map<String, dynamic>>[];
    for (final r in needy) {
      final fig = byName['${r['name']}'.toLowerCase().trim()];
      if (fig == null) continue;
      writes.add(Map<String, dynamic>.from(r)
        ..['figureA'] = fig.frameA
        ..['figureB'] = fig.frameB
        ..['figureTween'] = fig.tweenable);
    }
    if (writes.isEmpty) return;
    final result = _executeMutation(
      writes: writes,
      deletes: const [],
      origin: 'routine-figure-fill',
      description: 'filled routine figures',
      frozenInputs: {'routineId': routineId},
      visible: false,
    );
    if (result.state == ExecutionResultState.persisted) {
      _outWrites.add({'op': 'figures', 'n': writes.length});
    }
  }

  /// Control words recognised while a run is live. Returns the reply, or null to let the utterance
  /// fall through to normal routing (the run stays live — see the sticky note at the call site).
  Future<String?> _routineControl(String u, DateTime now) async {
    final run = _run!;
    final priorSource = _outSource, priorSkill = _outSkill;
    _outSource = 'routine';
    _outSkill = 'routine-player';
    // Resume is checked BEFORE next: "ready" is far more naturally "I'm back" than "I'm finished",
    // and when it was a next-word a paused user saying it marked the held step COMPLETE (the logged
    // session then over-counted) and left `paused` set, which killed the cadence for the rest of
    // the run.
    if (run.paused && _routineResumeRe.hasMatch(u)) {
      run.paused = false;
      return 'Back to it. ${run.announce()}';
    }
    if (_routineNextRe.hasMatch(u)) {
      run.paused = false; // moving on always un-pauses
      run.markDone();
      return await _advance(now);
    }
    if (_routineSkipRe.hasMatch(u)) {
      run.paused = false;
      run.markSkipped();
      return await _advance(now);
    }
    if (_routineBackRe.hasMatch(u)) {
      run.paused = false;
      if (!run.back()) return 'We\'re at the first step. ${run.announce()}';
      return run.announce();
    }
    if (_routineRepeatRe.hasMatch(u)) {
      // Answered from the STORED instruction — never a model call mid-run (offline, instant, and
      // it cannot drift from what was authored).
      return run.announce();
    }
    if (_routinePauseRe.hasMatch(u)) {
      run.paused = true;
      return 'Paused — say "go on" when you\'re ready.';
    }
    if (_routineStopRe.hasMatch(u)) return await _endRun(now, quit: true);
    // Not a control word: restore the telemetry fields we speculatively set, and let the utterance
    // route normally. The run stays live.
    _outSource = priorSource;
    _outSkill = priorSkill;
    return null;
  }

  /// Move to the next step, or finish. The spoken line IS the step announcement, so a run works
  /// with the screen off — the figure is never the sole carrier of the movement.
  Future<String> _advance(DateTime now) async {
    final run = _run!;
    if (run.isDone) return await _endRun(now);
    return run.announce();
  }

  /// Finish a run. A completed (or partly completed) run writes a routine_session through the
  /// ordinary skill dispatch, so it is journaled, undoable and visible to automations. An abandoned
  /// run writes NOTHING — a fabricated session would corrupt the record (DP-05).
  Future<String> _endRun(DateTime now, {bool quit = false}) async {
    final run = _run!;
    _run = null;
    final done = run.completed.length;
    if (done == 0) {
      return quit ? 'Stopped — nothing logged.' : 'Stopped.';
    }
    // The write is AWAITED and its outcome checked. Fire-and-forget meant the reply claimed
    // "logged" while the write could have silently failed (duplicate titles made read_one raise an
    // ambiguity; a rename or delete mid-run stranded it) — telling the user a session exists when
    // it doesn't is exactly the silent failure principle #7 forbids, and it quietly corrupts
    // streaks and "when did I last do X".
    await dispatchSkill(
        'log-routine-session',
        {
          'routineId': run.routineId,
          'stepsCompleted': done,
          'stepsTotal': run.total,
        },
        source: 'routine');
    final logged = store.values.any((r) =>
        r['typeId'] == 'routine_session' &&
        r['routine'] == run.routineId &&
        r['date'] == now.toIso8601String().split('T').first);
    final mins = now.difference(run.startedAt).inMinutes;
    if (!logged) {
      return "You did $done of ${run.total} — but I couldn't save that session. "
          'Nothing was lost from the routine itself.';
    }
    return quit
        ? 'Stopped there — logged ${run.title}, $done of ${run.total}.'
        : 'Nice — ${run.title} done, $done of ${run.total}'
            '${mins > 0 ? ', $mins minute${mins == 1 ? '' : 's'}' : ''}.';
  }

  /// Start a run for a routine record. Returns the opening line (safety note first time, then the
  /// first step), or an honest reason it can't start.
  String startRoutineRun(String routineId, DateTime now) {
    final r = store[routineId];
    if (r == null) return "I can't find that routine any more.";
    final steps = store.values
        .where(
            (s) => s['typeId'] == 'routine_step' && s['routine'] == routineId)
        .toList()
      ..sort((a, b) => (num.tryParse('${a['order']}') ?? 0)
          .compareTo(num.tryParse('${b['order']}') ?? 0));
    if (steps.isEmpty) return '"${r['title']}" has no steps yet.';
    _run = RoutineRun(
      routineId: routineId,
      title: '${r['title']}',
      steps: steps.cast<Map<String, dynamic>>(),
      startedAt: now,
    );
    _outSource = 'routine';
    _outSkill = 'routine-player';
    // The safety line is spoken ONCE per routine, on its first run — repeated warnings are
    // themselves a safety failure (they stop being heard).
    final firstRun = !store.values.any(
        (s) => s['typeId'] == 'routine_session' && s['routine'] == routineId);
    final note = firstRun ? '${r['safetyNote'] ?? standingSafetyNote} ' : '';
    return '$note${_run!.announce()}';
  }

  /// Run a skill directly by id with already-resolved slots — the seam the routine player uses to
  /// log a finished run (Spec 16). It goes through the SAME `_dispatch` path as a spoken turn on
  /// purpose: completing a routine is an ordinary act-then-describe write, so it must be journaled
  /// (hence undoable), visible to automations, and present in the turn log — not a side channel
  /// that quietly bypasses the safety net. Returns the confirmation line.
  Future<String> dispatchSkill(String skillId, Map<String, dynamic> slots,
      {String source = 'player'}) async {
    if (!skills.containsKey(skillId)) return "I don't know how to do that yet.";
    _outWrites.clear();
    final msg = await _dispatch(skillId, slots, source, now);
    await _reconcileReminders();
    repo.logTurn({
      'source': source,
      'skill': skillId,
      'at': now.toIso8601String(),
      if (_outWrites.isNotEmpty)
        'writes': List<Map<String, dynamic>>.from(_outWrites),
    });
    return msg;
  }

  /// Reverse the most recent journaled write (powers a spoken "undo that" from outside a turn).
  Future<String> undoLast() async {
    final msg = _undoLastInternal();
    await _reconcileReminders();
    return msg;
  }

  /// Reverse a SPECIFIC journaled write by its id (the data-view snackbar UNDO). Targets that exact
  /// entry wherever it sits in the ring — so a later unrelated write doesn't make UNDO hit the wrong
  /// thing. No-op (with an honest message) if it already rolled off or was undone.
  Future<String> undoById(int undoId) async {
    final i = _journal.indexWhere((e) => e.id == undoId);
    if (i < 0) return 'That change is no longer undoable here.';
    final entry = _journal[i];
    final result = executions.undo(entry.id);
    if (result.state == ExecutionResultState.conflict) {
      return "I didn't undo that because the record changed afterward.";
    }
    if (result.state == ExecutionResultState.failedBeforeWrite) {
      return "I couldn't start that undo safely, so nothing changed.";
    }
    _journal.removeAt(i);
    if (result.state == ExecutionResultState.appliedInMemory) {
      await _reconcileReminders();
      return "I undid that here, but couldn't finish saving the undo. I'll recover it next launch.";
    }
    await _reconcileReminders();
    return entry.desc == null
        ? 'Undone.'
        : 'Undone — reversed: "${entry.desc}"';
  }

  /// The learned NLU flows, shaped for the "Learned phrases" showcase (most-recent first — learn()
  /// inserts at 0). Seed corpus entries are excluded (product vocabulary, not learned-from-you).
  List<LearnedFlow> get learnedFlows => [
        for (final e in router.corpus)
          if (router.isLearned(e.template))
            LearnedFlow(
              e.template,
              e.generativeKind != null
                  ? _humanizeKind(e.generativeKind!)
                  : (skills[e.skillId]?['displayName'] as String? ?? e.skillId),
              e.generativeKind != null,
            ),
      ];

  static String _humanizeKind(String kind) {
    final words = kind.replaceAll('_', ' ');
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  /// Forget a learned flow (data-view "×"). Returns the raw map as an undo token, or null if it
  /// wasn't a learned entry (seed entries can't be forgotten). If the entry is learned in-memory but
  /// missing from the persisted file (a persist race), synthesize a minimal token from the router
  /// entry so the user still gets a working undo (never forget without an undo path).
  Map<String, dynamic>? forgetLearnedFlow(String template) {
    var raw = repo
        .loadCorpusLearned()
        .whereType<Map>()
        .cast<Map<String, dynamic>>()
        .where((m) => m['template'] == template)
        .firstOrNull;
    final entry =
        router.corpus.where((c) => c.template == template).firstOrNull;
    if (!router.forget(template))
      return null; // wasn't learned (a seed / unknown) — nothing to undo
    repo.removeCorpusLearned(template);
    raw ??= entry == null
        ? {'template': template}
        : {
            'template': template,
            if (entry.generativeKind != null)
              'generativeKind': entry.generativeKind
            else
              'skillId': entry.skillId,
          };
    return raw;
  }

  /// Re-learn a forgotten flow (snackbar UNDO of forget). Guards against a double-restore appending
  /// a duplicate persisted line (which would show the flow twice after the next launch).
  void restoreLearnedFlow(Map<String, dynamic> raw) {
    final t = raw['template'];
    if (router.corpus.any((c) => c.template == t))
      return; // already back — don't duplicate-persist
    router.restore(raw);
    repo.appendCorpusLearned(raw);
  }

  /// Public entry: a catch-all boundary so NO exception (ResolveError or a raw
  /// TypeError/RangeError from model-shaped input) ever escapes into the UI or
  /// console. A crash becomes a visible, non-destructive message (no silent
  /// failure, P7) rather than a bricked input box.
  Future<String> handle(String u) async {
    _turnInProgress = true;
    u = u.trim();
    _outSource = 'clarify';
    _outSkill = null;
    _tourSpokeThisTurn =
        false; // set true by the tour helpers if THIS turn navigates the tour
    _enteredChapter =
        null; // set by _enterChapter when THIS turn opens a tour chapter (UI reads it)
    _cloudStatus = null;
    _outTemplate = null;
    _outSlots = null;
    _outWrites.clear();
    _outReads.clear();
    _outError = null;
    _outDiag = null;
    _lastTurnExecutionId = null;
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
    // Sonnet tokens are counted separately (different price). Snapshot them too, or the most
    // EXPENSIVE turns in the app — routine authoring and figure drawing, which never touch Haiku —
    // log no cost at all, don't light the cloud indicator, and make the turnlog's running total a
    // lie exactly where it matters most.
    final sIn0 = c is ClaudeClient ? c.sonnetInTokens : 0;
    final sOut0 = c is ClaudeClient ? c.sonnetOutTokens : 0;
    String resp;
    try {
      resp = await _handle(u);
    } catch (e, st) {
      _outSource = 'error';
      _outError =
          '${e.runtimeType}: $e\n$st'; // full detail to the trace, never to the user
      resp =
          "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
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
      final inDomain =
          ch != null && skill != null && ch.domainKeywords.any(skill.contains);
      if (inDomain) {
        final codaGiven = liveTour['codaGiven'] as Set;
        if (_lastTurnWrote &&
            _outSource != 'error' &&
            !codaGiven.contains(chapter)) {
          codaGiven.add(chapter);
          resp = '$resp ${ch.coda}';
          if (_availableChapters()
              .every((c) => (liveTour['visited'] as Set).contains(c.id))) {
            _pendingTour = null;
            resp = '$resp\n\n${_tourClosing()}';
          }
        }
      } else if (skill != null && !skill.startsWith('ref-')) {
        _pendingTour =
            null; // a skill ran outside this chapter's domain → moved on → end silently
      }
      // else (no skill dispatched — clarify/undo/error/template — OR a reference-by-number action,
      // which is engagement with the list just read, like undo) → keep the tour alive.
    }
    // Did this turn actually spend cloud tokens? (drives the per-response cloud dot — accurate
    // even when a cloud/generative call failed to an offline reply, which spends nothing.)
    _lastTurnSpentCloud = c is ClaudeClient &&
        (c.inTokens - inTok0 > 0 ||
            c.outTokens - outTok0 > 0 ||
            c.sonnetInTokens - sIn0 > 0 ||
            c.sonnetOutTokens - sOut0 > 0);
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
        if (c is ClaudeClient &&
            (c.inTokens - inTok0 > 0 ||
                c.outTokens - outTok0 > 0 ||
                c.sonnetInTokens - sIn0 > 0 ||
                c.sonnetOutTokens - sOut0 > 0))
          'cost': {
            'in': (c.inTokens - inTok0) + (c.sonnetInTokens - sIn0),
            'out': (c.outTokens - outTok0) + (c.sonnetOutTokens - sOut0),
            // priced per MODEL — a Sonnet turn costs several times a Haiku one
            'usd': ClaudeClient.costUsd(
                    c.inTokens - inTok0, c.outTokens - outTok0) +
                ClaudeClient.sonnetCostUsd(
                    c.sonnetInTokens - sIn0, c.sonnetOutTokens - sOut0),
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
            if (automations.deliveries.length > autoDelivered0)
              'delivered': automations.deliveries.length - autoDelivered0,
            if (automations.pendingReview.length > autoHeld0)
              'held': automations.pendingReview.length - autoHeld0,
            if (automations.refusals.length > autoRefused0)
              'refused': automations.refusals.sublist(autoRefused0),
          },
      });
    } catch (_) {/* housekeeping/logging failure must not break the turn */}
    try {
      conversationLedger.append(
        utterance: u,
        reply: resp,
        source: _outSource,
        at: startedAt,
        executionId: _lastTurnExecutionId,
      );
    } catch (_) {
      /* ledger failure is surfaced at next hydration, not as a lost reply */
    }
    _turnInProgress = false;
    if (_storageRefreshPending) await _refreshExternalStorage();
    return resp;
  }

  /// A short, honest, user-facing reason a cloud call failed — so a miss names the
  /// cause instead of always blaming the user's phrasing (no silent degradation).
  static String cloudReason(CloudErrorKind k) => switch (k) {
        CloudErrorKind.noKey =>
          "I don't have an API key set — add one in Settings.",
        CloudErrorKind.badKey =>
          "my API key was rejected — update it in Settings.",
        CloudErrorKind.insufficientCredits =>
          "your Anthropic account has no credits — add a payment method or credits at console.anthropic.com (Settings → Billing). Your key is fine.",
        CloudErrorKind.offline => "I'm offline right now.",
        CloudErrorKind.timeout => "the cloud didn't respond in time.",
        CloudErrorKind.rateLimited =>
          "Claude use is rate-limited right now — check the local counters in Settings.",
        CloudErrorKind.serverError => "the cloud had a server error.",
        CloudErrorKind.malformed =>
          "I got an unexpected response from the cloud.",
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

    // "Is that what you wanted?" after a capability was learned. Answered here so a "no" actually
    // removes it rather than leaving the user with a thing they didn't ask for.
    final check = _pendingCapabilityCheck;
    if (check != null) {
      _pendingCapabilityCheck = null;
      // "undo that" / "never mind" are the natural ways to say no here. Left unhandled they fell
      // through to the JOURNAL and reversed an unrelated earlier data write, while the unwanted
      // capability survived — the worst of both.
      if (_noRe.hasMatch(u) || _cancelRe.hasMatch(u) || _undoRe.hasMatch(u)) {
        _outSource = 'authored';
        return _forgetCapability(check);
      }
      if (_yesRe.hasMatch(u)) {
        _outSource = 'authored';
        return 'Good — it\'s yours now.';
      }
      // anything else: they've moved on. Keep the capability and handle the input normally.
    }

    // A routine build is waiting on a yes (the confirm preference is on).
    final pendingBuild = _pendingRoutineBuild;
    if (pendingBuild != null) {
      _pendingRoutineBuild = null;
      if (_activateRe.hasMatch(u) || _yesRe.hasMatch(u)) {
        return await _createRoutine(
            pendingBuild['utterance'] as String,
            pendingBuild['focus'] as String,
            pendingBuild['kind'] as String?,
            now,
            confirmed: true);
      }
      if (_cancelRe.hasMatch(u) || _noRe.hasMatch(u)) {
        _outSource = 'clarify';
        return "No problem — I won't build it.";
      }
      // anything else: they moved on; nothing was built and nothing was spent.
    }

    // A routine was asked for with no focus and we asked what it should target — THIS utterance is
    // the answer. Checked early, before routing, so "my lower back" isn't read as a fresh command.
    final pendingKind = _pendingRoutineKind;
    if (pendingKind != null) {
      _pendingRoutineKind = null;
      if (_cancelRe.hasMatch(u) || _undoRe.hasMatch(u)) {
        _outSource = 'clarify';
        return 'No problem — no routine made.';
      }
      // A pending question must NOT swallow a real command. Without this guard "let's do low back",
      // "remind me to buy milk", "help", "next" and "skip" all became the FOCUS of a paid build —
      // money spent on a junk routine, and the command the user actually gave, lost. This is the
      // same guard _pendingFill and _pendingGen already carry, for the same reason.
      final focus = u
          .replaceFirst(
              RegExp(r'^(?:my|the|for|on)\s+', caseSensitive: false), '')
          .trim();
      if (focus.isNotEmpty && focus.length < 60 && !_isFreshCommand(u)) {
        return await _createRoutine(
            '$pendingKind routine for $focus', focus, pendingKind, now);
      }
      // Not a usable focus: fall through and route it normally rather than building something
      // random. The question is simply dropped — asking again would trap the user in a loop.
    }

    // A LIVE ROUTINE RUN intercepts its own control words first (Spec 16). Unlike the Tour, the run
    // is STICKY: an unrelated command mid-workout ("remind me to buy milk") executes normally and
    // the run stays live — there is sunk physical effort here, and silently dropping it because the
    // user asked one side question would be worse than any tidiness gained.
    if (_run != null) {
      final handled = await _routineControl(u, now);
      if (handled != null) return handled;
    }

    // A correction paused for the re-spoken text ("correct 1" -> "what should it say?"). This input
    // IS the replacement, dictated — so, unlike ProvideSlot, we deliberately do NOT bail on a
    // command-shaped answer ("call mom" is a legitimate task text). Only an explicit cancel or a
    // system command (undo/help) abandons the pause; the echo + undo cover a misheard replacement.
    final pendingCorr = _pendingCorrection;
    if (pendingCorr != null) {
      _pendingCorrection = null;
      final oldLabel = pendingCorr['oldLabel'] as String;
      final n = pendingCorr['n'];
      if (_cancelRe.hasMatch(u) || _undoRe.hasMatch(u)) {
        _outSource = 'clarify';
        return 'Okay — number $n stays "$oldLabel".';
      }
      if (_helpRe.hasMatch(u)) {
        /* let help win; fall through with the pause abandoned */
      } else {
        // strip a light dictation lead-in ("it should say…", "make it…", "change it to…")
        final newText = u
            .replaceFirst(
                RegExp(
                    r"^(?:it should (?:say|be)|make it|change it to|call it|say|it'?s)\s+",
                    caseSensitive: false),
                '')
            .trim();
        if (newText.isEmpty) {
          _pendingCorrection = pendingCorr; // nothing usable — re-ask once
          _outSource = 'clarify';
          return 'I didn\'t catch the new wording — what should number $n say?';
        }
        return _applyCorrection(
            pendingCorr['id'] as String,
            pendingCorr['typeId'] as String,
            pendingCorr['labelField'] as String,
            oldLabel,
            newText,
            n,
            now);
      }
    }

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
      final genIsSystemCmd = _undoRe.hasMatch(u) ||
          _helpRe.hasMatch(u) ||
          _corrRe.hasMatch(u) ||
          _fabricationRe.hasMatch(u);
      final genLooksLikeCommand =
          router.route(u, clock: now, contacts: _knownContactTokens()) !=
                  null ||
              _searchNoteRe.hasMatch(u) ||
              _searchForRe.hasMatch(u) ||
              _looksLikeRefCommand(u);
      if (!genIsSystemCmd && !genLooksLikeCommand) {
        return _dispatchGenerative(
            pendingGen['kind'] as String,
            {'contact': u.trim()},
            pendingGen['template'] as String?,
            'cloud',
            u,
            now);
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
      final isSystemCmd = _undoRe.hasMatch(u) ||
          _helpRe.hasMatch(u) ||
          _corrRe.hasMatch(u) ||
          _fabricationRe.hasMatch(u);
      if (!isSystemCmd) {
        final skillId = pending['skillId'] as String;
        final skill = skills[skillId];
        final slots = Map<String, dynamic>.from(pending['slots'] as Map);
        final missing = List<String>.from(pending['missing'] as List);
        // A reply that is itself a NEW command — it routes to a skill, or is a search/query intent —
        // must NOT be swallowed as the slot value (a TEXT slot coerces ANY string, so without this
        // "what are my reminders" would be written as a meal's food). Treat it as null so the
        // abandon-and-fall-through path below runs. (Fable review, major.)
        final looksLikeNewCommand = router.route(u,
                    clock: now, contacts: _knownContactTokens()) !=
                null ||
            _searchNoteRe.hasMatch(u) ||
            _searchForRe.hasMatch(u) ||
            _looksLikeRefCommand(
                u); // "delete 2" mid-fill is a reference command, not the slot value
        final coerced = looksLikeNewCommand
            ? null
            : _coerceSlot(skill, missing.first, u, now);
        if (coerced != null) {
          _pendingFill = null; // got the answer
          slots[missing.first] = coerced;
          final stillMissing = _missingRequired(skill, slots);
          if (stillMissing.isNotEmpty) {
            _pendingFill = {
              'skillId': skillId,
              'slots': slots,
              'missing': stillMissing
            };
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
        _pendingFill =
            null; // interrupted by a system command — handle it normally
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
        capabilityDrafts.clear();
        return _activateCapability(draft);
      }
      if (_cancelRe.hasMatch(u)) {
        _pendingActivation = null;
        capabilityDrafts.clear();
        _outSource = 'clarify';
        return "Okay — I won't add that.";
      }
      _pendingActivation =
          null; // moved on — drop the draft, handle this input normally
      capabilityDrafts.clear();
    }

    // Authoring OFFER (DF-01): a "start tracking X" with no built-in tracker and no template
    // was offered a paid custom build. A yes spends the cloud call; a decline drops it; any
    // other input abandons the offer and is handled normally (nothing was built).
    final offer = _pendingAuthorOffer;
    if (offer != null) {
      _pendingAuthorOffer = null;
      if (_activateRe.hasMatch(u)) {
        return _startDetachedAuthoring(offer, now);
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
      final isCommand =
          router.route(u, clock: now, contacts: _knownContactTokens()) != null;
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
        final res = automations.prepareApproval(item.id);
        _outSource = 'automation-review';
        _outSkill = item.skillId;
        if (res.kind == 'prepared' && res.plan != null) {
          final result = _executeMutation(
            writes: res.plan!.writes,
            deletes: res.plan!.deletes,
            origin: 'automation-approval',
            description: 'applied "${item.description}"',
            frozenInputs: {
              'reviewId': item.id,
              'automationId': item.automationId,
              'slots': item.slots,
            },
          );
          if (result.state == ExecutionResultState.failedBeforeWrite) {
            return "I couldn't start that approval safely, so nothing changed.";
          }
          automations.completePreparedApproval(item.id, res.plan!.writes);
          _lastTurnWrote = true;
          if (result.state == ExecutionResultState.appliedInMemory) {
            return "Applied it here, but couldn't finish saving it. I'll recover it next launch.";
          }
          return 'Done — applied "${item.description}".';
        }
        return switch (res.kind) {
          'planChanged' =>
            "That automation's data changed since it queued — ${res.message ?? 'have a look and re-approve'}.",
          'refused' =>
            "I couldn't apply that — ${res.message ?? 'it was refused'}.",
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

    // ---- Routines (Spec 16) -------------------------------------------------------------------
    // "let's do my low back routine" — start the player. Checked BEFORE creation so "do X" never
    // spends a cloud call on a routine that already exists.
    final doRoutine = _routineDoRe.firstMatch(u);
    if (doRoutine != null && _run == null) {
      final name = doRoutine.group(1)!.trim();
      final match = _findRoutine(name);
      if (match != null) return startRoutineRun(match['id'] as String, now);
      // fall through: an unknown name may be a CREATE request phrased as "do a X routine"
    }
    // "create a stretching routine [for my low back]"
    final make = _routineCreateRe.firstMatch(u);
    if (make != null && !_isTrackerAsk(u)) {
      final focus = (make.group(3) ?? '').trim();
      final kindWord = make.group(1) ?? make.group(2);
      if (focus.isEmpty) {
        // No focus given. ASK rather than guess: "a stretching routine" for what is the difference
        // between a useful routine and a generic one, and guessing spends money on the wrong thing.
        _pendingRoutineKind = kindWord;
        _outSource = 'clarify';
        return 'Happy to. What should it focus on — your back, hips, shoulders, something else?';
      }
      return await _createRoutine(u, focus, kindWord, now);
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
      return _undoLastInternal();
    }

    // An active proposal owns its own numbered context. Refinement must happen
    // before current-plan pronouns, because proposed positions are not yet truth.
    final proposalCommand = await _proposalCommand(u, now);
    if (proposalCommand != null) return proposalCommand;

    // A planner surface publishes the exact records and order currently in view.
    // Resolve pronouns against that snapshot before generic routing; without a
    // visible context these patterns decline to match and normal voice routing wins.
    final plannerCommand = await _plannerContextCommand(u, now);
    if (plannerCommand != null) return plannerCommand;

    // Reference-by-number over the last numbered readback ("delete 2", "complete 1", "correct 3").
    // Only when a list is in front of us — otherwise these fall through so "delete the first task"
    // still reaches delete-task-at. Resolve by recordId, never a re-derived order (P: no drift).
    if (_enumCtx != null) {
      final del = _refDeleteRe.firstMatch(u);
      if (del != null) return _refDelete(_refPos(del.group(1)!));
      final comp = _refCompleteRe.firstMatch(u);
      if (comp != null) return _refComplete(_refPos(comp.group(1)!), now);
      final inl = _refCorrectInlineRe
          .firstMatch(u); // "change 2 to X" — check before the bare form
      if (inl != null)
        return _refCorrectInline(
            _refPos(inl.group(1)!), inl.group(2)!.trim(), now);
      final corrRef = _refCorrectRe.firstMatch(u);
      if (corrRef != null) return _refCorrectStart(_refPos(corrRef.group(1)!));
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
    if (recl != null &&
        prevWrote &&
        prevDispatch != null &&
        _journal.isNotEmpty) {
      final prevSkill = prevDispatch['skillId'] as String;
      final target = _activitySkill[recl.group(1)!.toLowerCase()];
      if (target != null &&
          _workoutSkills.contains(prevSkill) &&
          target != prevSkill) {
        final undone = _undoLastInternal();
        if (undone.startsWith("I couldn't")) return undone;
        final redo = await _dispatch(
            target,
            Map<String, dynamic>.from(prevDispatch['slots'] as Map),
            'corpus',
            now);
        _outSource = 'correction';
        return 'Fixed that — $redo';
      }
    }

    // Same-record slot correction (F-15): "actually, 28 minutes" / "make it 3k" updates a
    // field of the just-logged workout IN PLACE (distinguished from F-14: same record, not a
    // reverse-redispatch), journaled so undo restores the prior value.
    if (prevWrote &&
        prevDispatch != null &&
        _workoutSkills.contains(prevDispatch['skillId'])) {
      final dm = _durationCorrectRe.firstMatch(u);
      final km = _distanceCorrectRe.firstMatch(u);
      final id = prevDispatch['writtenId'] as String?;
      if ((dm != null || km != null) && id != null && store.containsKey(id)) {
        final field = dm != null ? 'duration' : 'distance';
        final value = num.tryParse((dm ?? km)!.group(1)!);
        if (value != null) {
          final rec = Map<String, dynamic>.from(store[id]!)..[field] = value;
          final result = _executeMutation(
            writes: [rec],
            deletes: const [],
            origin: 'correction',
            description: 'updated $field',
            frozenInputs: {'recordId': id, 'field': field, 'value': value},
          );
          if (result.state == ExecutionResultState.failedBeforeWrite) {
            return "I couldn't start that correction safely, so nothing changed.";
          }
          _lastTurnWrote = true;
          _lastDispatch =
              prevDispatch; // keep context so a further correction chains
          _outSource = 'correction';
          return result.state == ExecutionResultState.appliedInMemory
              ? "Updated here, but couldn't finish saving it. I'll recover it next launch."
              : 'Updated — that ${rec['activity']} was $value ${field == 'duration' ? 'minutes' : 'km'}.';
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
        final undone = _undoLastInternal();
        if (undone.startsWith("I couldn't")) return undone;
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
      final who =
          reconnect.group(1) ?? reconnect.group(2) ?? reconnect.group(3) ?? '';
      return _generative.reconnect(who.trim(), store, now);
    }
    if (_morningPlanRe.hasMatch(u)) {
      final artifact = createMorningPlan();
      _outSource = 'planning-artifact';
      _outSkill = 'morning-plan';
      return '${artifact.summary} I kept the morning plan on Today until you accept or dismiss it.';
    }
    final relationshipPrep = _relationshipPrepRe.firstMatch(u);
    if (relationshipPrep != null) {
      final name = relationshipPrep.group(1)!.trim();
      final artifact = createRelationshipPrep(name);
      _outSource = 'planning-artifact';
      _outSkill = 'relationship-prep';
      return artifact == null
          ? "I don't have $name as a contact yet, so I couldn't build a grounded prep card."
          : '${artifact.summary} I kept the prep card on Today until you accept or dismiss it.';
    }
    if (_weeklyReviewRe.hasMatch(u)) {
      final review = createWeeklyReview();
      final background = _startDetachedSynthesis(
        'weekly_review',
        'your weekly reflection',
        (snapshot) => _generative.weeklyReview(snapshot, now),
      );
      return 'Drafted ${review.items.length} editable keep/defer/drop recommendations from your current tasks and goals. $background';
    }
    if (_patternInsightRe.hasMatch(u)) {
      return _startDetachedSynthesis(
        'pattern_insight',
        'a pattern review',
        (snapshot) => _generative.patternInsight(snapshot, now),
      );
    }
    final draftMsg = _draftMessageRe.firstMatch(u);
    if (draftMsg != null) {
      _outSource = 'generative';
      _outSkill = 'draft_message';
      return _generative.draftMessage(draftMsg.group(1)!.trim(), store, now);
    }

    final def = _defRe.firstMatch(u);
    if (def != null &&
        router.route(u, clock: now, contacts: _knownContactTokens()) == null) {
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
      // DF-01: no built-in tracker and no template, so this needs a paid custom build.
      //
      // Whether to ASK first is a user preference, not a rule. Asking every time is friction: the
      // user just said what they wanted, and a second "are you sure?" on every custom capability
      // makes the app feel like it's haggling. Default is to just build it; Settings → "Ask before
      // paid builds" restores the per-invocation confirm for anyone who wants the brake.
      if (confirmCloudSpend) {
        _pendingAuthorOffer = desc;
        _outSource = 'author-offer';
        return "I don't have a built-in tracker for that yet. I can build you a custom one — "
            "that uses your Claude credits (a paid step). Want me to go ahead?";
      }
      return _startDetachedAuthoring(desc, now);
    }

    // Content search (F-12): "find that note about the cabin trip" / "search my notes for X".
    // Checked before corpus routing so it isn't mis-parsed; semantic when the embed index is up,
    // keyword otherwise — so it works offline too.
    final searchM = _searchNoteRe.firstMatch(u) ?? _searchForRe.firstMatch(u);
    if (searchM != null) return _searchContent(searchM.group(1) ?? '');

    var routed = router.route(u, clock: now, contacts: _knownContactTokens());
    // The production cold-start order is corpus → in-process retrieval → cloud.
    // Retrieval may act only when both its candidate margin and a deterministic
    // slot extractor succeed; otherwise it has made no decision and cloud keeps
    // responsibility for the genuine residual.
    if (routed == null && _retrievalEnabled) {
      routed = await router.retrievalRoute(u);
    }
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
          slots.updateAll((k, v) => (v is String &&
                  const {'none', 'null'}.contains(v.trim().toLowerCase()))
              ? null
              : v);
          replies.add(await _dispatch(
              p['skillId'] as String, slots, 'compound-part', now,
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
      switch (await claude.routeResidual(u, skills,
          knownContacts: _knownContactNames())) {
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
      return _dispatchGenerative(
          routed['generativeKind'] as String,
          (routed['params'] as Map?)?.cast<String, dynamic>() ?? const {},
          routed['template'] as String?,
          routed['source'] as String? ?? 'cloud',
          u,
          now);
    }
    if (routed == null) {
      // A reference-by-number command with NO list in front of us (the ref handlers above only fire
      // when _enumCtx is live). Point the user at the readback instead of a blank "didn't catch that".
      if (_refDeleteRe.hasMatch(u) ||
          _refCompleteRe.hasMatch(u) ||
          _refCorrectRe.hasMatch(u) ||
          _refCorrectInlineRe.hasMatch(u)) {
        _outSource = 'clarify';
        return 'There\'s no numbered list in front of us — say "list my tasks" (or people, or '
            'reminders) first, then "delete 2" or "correct 2".';
      }
      // A miss is corpus + (abstain | cloud error | no cloud). If the cloud FAILED,
      // say so honestly instead of only blaming the phrasing (no silent degradation).
      final sg = await router.retrievalSuggest(u);
      // Diagnose the miss in the trace: corpus didn't match; what the cloud did; and the
      // nearest skill + score (when retrieval is on) — so "why didn't it catch that?" is answerable.
      _outDiag = {
        'corpus': 'no-match',
        'cloud': cloudErr != null
            ? 'error:${cloudErr.name}'
            : (_cloudStatus == 'ok' ? 'abstained' : 'not-consulted'),
        if (sg != null) 'closest': sg['skillId'],
        if (sg != null) 'score': sg['s1'],
        if (sg != null) 'confident': sg['confident'],
      };
      // A retrieval suggestion can name a skill that no longer exists (a capability the user
      // forgot, or a corpus synced from a device with different capabilities). Null-asserting here
      // turned an honest miss into "something went wrong".
      final sgSkill = sg == null ? null : skills[sg['skillId']];
      final base = sg == null || sgSkill == null
          ? "I didn't catch that."
          : (() {
              final name = sgSkill['displayName'];
              final s1 = (sg['s1'] as double).toStringAsFixed(2);
              return sg['confident'] == true
                  ? 'I don\'t have that phrasing learned — did you mean to "$name"? Say it a known way and I\'ll learn it.'
                  : 'I\'m not sure what you meant — closest is "$name" ($s1), below my confidence bar, so I won\'t guess.';
            })();
      return cloudErr == null
          ? base
          : '$base (I also couldn\'t check with the cloud: ${cloudReason(cloudErr)})';
    }
    // Multi-record decomposition (cloud only): the router split a rich statement into
    // several records ("dinner with X and Y", or a relationship AND a fact). Execute each
    // fully-slotted action and compose the confirmations — like the F-13 compound path.
    // An action missing a required slot is skipped (no per-action ProvideSlot in a batch).
    if (routed['actions'] is List) {
      final accepted = <Map<String, dynamic>>[];
      var skipped = (routed['skippedGenerative'] as int?) ??
          0; // generative half(s) dropped from a batch (G-46)
      final seen =
          <String>{}; // dedup: a cloud split can emit the same record twice (reviewer a #8)
      for (final a in (routed['actions'] as List).cast<Map>()) {
        final sid = a['skillId'] as String?;
        final slots = (a['slots'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
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
        final key =
            '$sid|${(slots.entries.toList()..sort((x, y) => x.key.compareTo(y.key))).map((e) => '${e.key}=${e.value}').join('&')}';
        if (!seen.add(key))
          continue; // silent — a dedup'd duplicate isn't a "skipped" failure
        accepted.add({'skillId': sid, 'slots': slots});
      }
      if (accepted.isNotEmpty) {
        final batch = await _dispatchBatch(
          accepted,
          'cloud-multi',
          now,
          skipped: skipped,
        );
        _lastTurnWrote = batch.wrote;
        _outSource = 'cloud-multi'; // telemetry: one turn, several records
        _outSkill = batch.done.join('+');
        return batch.reply;
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
    // Cloud/replay maps may arrive with a runtime type such as Map<String, String>. Mutating that
    // map with a `(dynamic, dynamic)` callback throws before dispatch. Copy into the engine's owned
    // slot type while sanitizing so later resolvers can safely replace values with dates/nulls.
    final rawSlots = routed['slots'];
    routed['slots'] = rawSlots is Map
        ? <String, dynamic>{
            for (final entry in rawSlots.entries)
              entry.key.toString(): _sanitizeSlot(entry.value),
          }
        : <String, dynamic>{};
    // The corpus types its slots via the template; the cloud returns raw strings, so
    // normalize any date/datetime input the routed skill declares (Spec 03 §6.2).
    // A cloud "2026-07-08" for a datetime slot -> null (no midnight reminders); a raw
    // "tomorrow at 3pm" -> a real ISO datetime (no silently-dropped reminders).
    if (routed['source'] == 'cloud') {
      _normalizeTypedSlots(skills[routed['skillId']],
          routed['slots'] as Map<String, dynamic>, now);
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
    final template =
        routed['source'] == 'corpus' ? routed['template'] as String? : null;
    // A cloud route may carry a SUGGESTED template (surface-abstracted) to learn — distinct
    // from a matched corpus `template`. The router validates it by round-trip before adopting.
    final learnTemplate =
        routed['source'] == 'cloud' ? routed['template'] as String? : null;
    final reply = await _dispatch(
        skillId, slots, routed['source'] as String, now,
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
  Future<String> _dispatchGenerative(String kind, Map<String, dynamic> params,
      String? template, String source, String u, DateTime now) async {
    const contactKinds = {'gift_ideas', 'reconnect', 'draft_message'};
    _outSource = 'generative';
    _outSkill = kind;
    _outTemplate =
        template; // so a bad generative-template match is diagnosable in the turnlog
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
    if (template != null && router.isLearned(template))
      _lastTurnTemplate = template;
    _generative.lastDelivered =
        false; // reset; set true only by a real cloud synthesis
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
    if (source == 'cloud' &&
        _generative.lastDelivered &&
        contactKinds.contains(kind)) {
      final learned = router.learnGenerative(u, kind, contact,
          contacts: _knownContactTokens());
      if (learned != null) {
        repo.appendCorpusLearned({'generativeKind': kind, 'template': learned});
        _lastTurnTemplate = learned;
      }
    }
    return reply;
  }

  /// Resolve → execute → persist → journal → learn for a fully-slotted skill. Shared by
  /// the normal routing path and a completed ProvideSlot fill.
  Future<String> _dispatch(
      String skillId, Map<String, dynamic> slots, String source, DateTime now,
      {String? template, String? learnTemplate, String? utterance}) async {
    _outSkill = skillId; // debug trace
    _outSlots = slots;
    _outTemplate = template;
    final turnInterp = Interpreter(types, now,
        references: _references); // per-turn clock (Spec 03 §4)
    // A route can outlive its skill: a learned corpus template whose capability was removed here,
    // or a corpus file synced from a device that has a capability this one doesn't. `skills[id]!`
    // turned that into a null-check crash and a "something went wrong". Fail honestly instead, and
    // drop the dead template so the same phrase doesn't keep failing.
    final def = skills[skillId];
    if (def == null) {
      if (template != null) {
        router.forget(template);
        try {
          repo.removeCorpusLearned(template);
        } catch (_) {/* inert either way — routing already dropped it */}
      }
      _outSource = 'error';
      _outError = 'route pointed at missing skill "$skillId"';
      return "I used to know how to do that, but I don't any more — tell me again and I'll relearn it.";
    }
    try {
      final plan = turnInterp.resolve(def, slots, store);
      final wrote = plan.writes.isNotEmpty || plan.deletes.isNotEmpty;
      if (wrote) {
        final result = _executeMutation(
          writes: plan.writes,
          deletes: plan.deletes,
          origin: source,
          description: plan.confirmation,
          frozenInputs: {
            'skillId': skillId,
            'slots': Map<String, dynamic>.from(slots),
            if (utterance != null) 'utterance': utterance,
          },
        );
        final record = result.record;
        if (result.state == ExecutionResultState.failedBeforeWrite ||
            record == null) {
          _outSource = 'error';
          _outError = 'execution journal prepare failed: ${result.error}';
          _lastTurnWrote = false;
          return "I couldn't start that safely, so nothing changed.";
        }
        if (result.state == ExecutionResultState.appliedInMemory) {
          _outSource = 'error';
          _outError = 'durable execution interrupted: ${result.error}';
          _lastTurnWrote = true;
          return "I did that here, but couldn't save it completely. I'll recover it next launch — "
              'say "undo that" to take it back now.';
        }
        for (final operation in record.operations) {
          _outWrites.add({
            'op': operation.kind,
            'id': operation.id,
            if (operation.record case final value?) 'typeId': value['typeId'],
          });
        }
      }
      // Capture a numbered readback's ordered id/label list so a later "delete 2" / "correct 1"
      // resolves against EXACTLY what was spoken (Feature: numbered-list corrections). A skill that
      // didn't enumerate leaves the context alone; an empty readback clears it (no stale referent).
      final en = plan.enumeration;
      if (en != null) {
        final items = (en['items'] as List).cast<Map>();
        _enumCtx = items.isEmpty
            ? null
            : _EnumCtx([
                for (final it in items)
                  _EnumItem('${it['id']}', '${it['typeId']}', '${it['field']}',
                      '${it['label']}'),
              ], skillId);
      }
      // record the previous-turn state for a correction (every routed turn, write or read).
      // The journal push for this turn already happened above, before persisting.
      _lastTurnWrote = wrote;
      _lastTurnTemplate =
          (template != null && router.isLearned(template)) ? template : null;
      if (_lastTurnWrote) {
        // for re-classify (F-14) + same-record slot correction (F-15)
        _lastDispatch = {
          'skillId': skillId,
          'slots': slots,
          if (plan.writes.isNotEmpty) 'writtenId': plan.writes.first['id'],
        };
      }
      // onWrite automations (Spec 04 §4.8): the hook lives at the completion of
      // this turn's writes. Read-only results are delivered out-of-band; writing
      // plans are HELD in the review feed (Spec 02 §7.5) — the turn's response
      // is never changed by an automation, and a runner fault never fails the
      // turn (failures surface via automations.refusals, P2.8).
      if (plan.writes.isNotEmpty) {
        try {
          automations.notifyWrites(plan.writes);
        } catch (_) {
          /* contained — an automation must never break the user's turn */
        }
      }
      if (source == 'cloud' && utterance != null) {
        // Prefer the cloud's surface-abstracted suggestion (learns date/time phrasings the
        // verbatim reconstruction can't), validated by round-trip; fall back to the mechanical
        // abstraction when the cloud offered none or it failed a guard.
        var tmpl = learnTemplate == null
            ? null
            : router.learnSuggested(utterance, skillId, slots, learnTemplate,
                clock: now, contacts: _knownContactTokens());
        tmpl ??= router.learn(utterance, skillId, slots,
            contacts: _knownContactTokens());
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
        final shown = opts.length <= 5
            ? opts.join(', ')
            : '${opts.take(5).join(', ')}, …';
        return 'I know more than one match for that — $shown. Which one? (say the full name)';
      }
      return "I couldn't do that: ${e.message}";
    } finally {
      // capture the read-resolution trace even when resolve/execute THREW mid-plan — that's
      // exactly the turn you most want to diagnose from the log (review low).
      _outReads.addAll(turnInterp.lastPlan?.reads ?? const []);
    }
  }

  Future<({String reply, List<String> done, int skipped, bool wrote})>
      _dispatchBatch(
    List<Map<String, dynamic>> actions,
    String source,
    DateTime now, {
    int skipped = 0,
  }) async {
    final scratch = <String, Map<String, dynamic>>{
      for (final entry in store.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final writes = <Map<String, dynamic>>[];
    final deletes = <String>[];
    final replies = <String>[];
    final done = <String>[];
    for (final action in actions) {
      final skillId = action['skillId'] as String;
      final slots = Map<String, dynamic>.from(action['slots'] as Map);
      try {
        final interpreter = Interpreter(types, now, references: _references);
        final plan = interpreter.resolve(skills[skillId]!, slots, scratch);
        interpreter.execute(plan, scratch);
        writes.addAll(plan.writes);
        deletes.addAll(plan.deletes);
        replies.add(plan.confirmation ?? 'Done.');
        done.add(skillId);
        _outReads.addAll(plan.reads);
      } catch (_) {
        skipped++;
      }
    }
    if (done.isEmpty) {
      return (
        reply:
            "I understood a few things there but couldn't record them cleanly — try one at a time?",
        done: done,
        skipped: skipped,
        wrote: false,
      );
    }
    final wrote = writes.isNotEmpty || deletes.isNotEmpty;
    if (wrote) {
      final result = _executeMutation(
        writes: writes,
        deletes: deletes,
        origin: source,
        description: replies.join(' '),
        frozenInputs: {'actions': actions},
      );
      if (result.state == ExecutionResultState.failedBeforeWrite) {
        return (
          reply: "I couldn't start that safely, so nothing changed.",
          done: const <String>[],
          skipped: actions.length + skipped,
          wrote: false,
        );
      }
      if (result.state == ExecutionResultState.appliedInMemory) {
        return (
          reply:
              "I did that here, but couldn't save it completely. I'll recover it next launch.",
          done: done,
          skipped: skipped,
          wrote: true,
        );
      }
      for (final operation in result.record!.operations) {
        _outWrites.add({
          'op': operation.kind,
          'id': operation.id,
          if (operation.record case final value?) 'typeId': value['typeId'],
        });
      }
      if (writes.isNotEmpty) {
        try {
          automations.notifyWrites(writes);
        } catch (_) {/* contained */}
      }
    }
    final reply = replies.join(' ');
    return (
      reply: skipped > 0
          ? "$reply (I couldn't record $skipped part${skipped > 1 ? 's' : ''} of that — try rephrasing ${skipped > 1 ? 'them' : 'it'}.)"
          : reply,
      done: done,
      skipped: skipped,
      wrote: wrote,
    );
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
    for (final m
        in RegExp(r',?\s+and\s+', caseSensitive: false).allMatches(u)) {
      final left = u.substring(0, m.start).trim();
      final right = u.substring(m.end).trim();
      if (left.isEmpty || right.isEmpty) continue;
      final lr =
          router.route(left, clock: now, contacts: _knownContactTokens());
      if (lr == null) continue;
      final rr =
          router.route(right, clock: now, contacts: _knownContactTokens());
      if (rr == null) continue;
      // A generative half (learned {generativeKind} route) has no skillId/slots — it can't be a
      // batched skill dispatch (Spec 03 §7.3.2: no generative inside a compound). Skip the seam so a
      // generative-shaped half never reaches the skill dispatch code (which would throw after the
      // other half already wrote, then falsely claim nothing was done).
      if (lr['generativeKind'] != null || rr['generativeKind'] != null)
        continue;
      if (_missingRequired(skills[lr['skillId']],
                  (lr['slots'] as Map).cast<String, dynamic>())
              .isNotEmpty ||
          _missingRequired(skills[rr['skillId']],
                  (rr['slots'] as Map).cast<String, dynamic>())
              .isNotEmpty) {
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
    bool wordHit(String s) =>
        s.isNotEmpty && RegExp('\\b${RegExp.escape(s)}\\b').hasMatch(lu);
    for (final r in store.values) {
      if (r['typeId'] != 'contact') continue;
      if (wordHit((r['displayName'] as String?)?.toLowerCase() ?? ''))
        return true;
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
    if (ids.isEmpty)
      ids = ContentSearchIndex.keywordSearch(query, store.values);
    if (ids.isEmpty) return 'I couldn\'t find anything about "$query".';
    final byId = {for (final r in store.values) r['id']: r};
    final lines = <String>[];
    for (final id in ids) {
      final r = byId[id];
      final c = r == null ? null : ContentSearchIndex.contentOf(r);
      if (c != null) lines.add('• $c');
    }
    if (lines.isEmpty) return 'I couldn\'t find anything about "$query".';
    final head =
        lines.length == 1 ? 'Found 1 match:' : 'Found ${lines.length} matches:';
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

  void _validateTypeCandidate(Map<String, dynamic> type) {
    final id = type['typeId'] as String?;
    if (id == null) throw ResolveError('typeId is required');
    final candidate = SchemaRegistry.fromDefinitions(
      {...types, id: type},
      skills: skills,
    );
    final rejected = candidate.issues.where(
      (issue) =>
          issue.source == '$id.json' &&
          issue.severity == SchemaIssueSeverity.rejected,
    );
    if (rejected.isNotEmpty || !candidate.contains(id)) {
      throw ResolveError(rejected.isEmpty
          ? 'type "$id" was rejected by the schema registry'
          : rejected.map((issue) => issue.message).join('; '));
    }
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
      String?
          tempType; // temporarily registered so validateSkill sees the type; rolled back
      try {
        final type = Map<String, dynamic>.from(authored['type'] as Map)
          ..putIfAbsent('schemaVersion', () => 1);
        final skill = (authored['skill'] as Map).cast<String, dynamic>();
        final typeId = type['typeId'], skillId = skill['skillId'];
        if (typeId is! String || skillId is! String) {
          throw ResolveError(
              'authored capability is missing a string typeId/skillId');
        }
        if (!_idRe.hasMatch(typeId) || !_idRe.hasMatch(skillId)) {
          // model-controlled ids must never steer a file path or carry odd chars
          throw ResolveError('authored id must match [a-z0-9_-] (1-64 chars)');
        }
        if (types.containsKey(typeId) || skills.containsKey(skillId)) {
          // never overwrite a built-in / existing capability
          throw ResolveError(
              'a capability like "$skillId" already exists — nothing built');
        }
        // Validate WITHOUT committing (§6.5 / G-18): temporarily register the type so
        // validateSkill can resolve it, then roll it back — nothing is registered until
        // the user says "activate".
        _validateTypeCandidate(type);
        interp.validateType(type);
        types[typeId] = type;
        tempType = typeId;
        interp.validateSkill(skill);
        types.remove(tempType);
        tempType = null;
        final eg = (skill['examplePhrases'] as List?)?.cast<String>() ??
            const <String>[];
        _pendingActivation = {
          'type': type,
          'skill': skill,
          'typeId': typeId,
          'skillId': skillId,
          'displayName': skill['displayName'] ?? skillId,
          'examples': eg,
        };
        capabilityDrafts.save(_pendingActivation!);
        _outSource = 'authoring-preview';
        return 'I can build "${skill['displayName'] ?? skillId}" for you'
            '${eg.isNotEmpty ? ' — you\'d be able to say things like "${eg.first}"' : ''}. '
            'Say "activate" to add it, or "never mind" to skip.';
      } catch (e) {
        if (tempType != null) types.remove(tempType); // safe rollback
        priorError = e is ResolveError ? e.message : e.toString();
        if (attempt == 2)
          return 'I drafted that but it could not be validated — nothing was registered.';
      }
    }
    return "I couldn't build that right now."; // loop always returns; satisfies the analyzer
  }

  String _startDetachedAuthoring(String desc, DateTime requestedAt) {
    late String operationId;
    final operation = operations.start(
      kind: 'capability_authoring',
      title: 'your custom capability',
      input: {'description': desc},
      run: (_) => _runDetachedLogged(
        operationId,
        'capability_authoring',
        () => _authorAndPreview(desc, requestedAt),
      ),
    );
    operationId = operation.id;
    _outSource = 'operation';
    _outSkill = 'capability_authoring';
    return 'Started building your custom capability in the background '
        '(${operation.id}). You can keep using Plenara; I’ll show the validated '
        'preview when it finishes.';
  }

  Future<String?> _tryInstantiateTemplate(String desc, DateTime now) async {
    final d = desc.toLowerCase();
    // "track my water intake IN GLASSES" / "meals WITH CALORIES" carries a unit/field the shipped
    // template can't honor — don't let a keyword match pre-empt it; fall through to authoring.
    if (_customizationRe.hasMatch(d)) return null;
    for (final t in templates.values) {
      final keywords =
          (t['keywords'] as List?)?.cast<String>() ?? const <String>[];
      if (!keywords.any((k) => d.contains(k.toLowerCase()))) continue;
      final skillDefs = (t['skills'] as List)
          .map((s) => (s as Map).cast<String, dynamic>())
          .toList();
      final eg = t['example']?.toString() ?? 'logging one';
      _outSource = 'template';
      if (skillDefs.any((s) => skills.containsKey(s['skillId']))) {
        return 'You\'re already tracking that — try "$eg".';
      }
      try {
        for (final ty in (t['types'] as List)) {
          final type = Map<String, dynamic>.from(ty as Map)
            ..putIfAbsent('schemaVersion', () => 1);
          _validateTypeCandidate(type);
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
          final sid = (c as Map)['skillId'] as String,
              tmpl = c['template'] as String;
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
      _validateTypeCandidate(type);
      interp.validateType(type);
      types[typeId] = type;
      interp.validateSkill(skill);
      skills[skillId] = skill;
      repo.writeDef('types', 'typeId', type);
      repo.writeDef('skills', 'skillId', skill);
      if (_retrievalEnabled) await router.buildRetrievalIndex(skills);
      final eg = (draft['examples'] as List).cast<String>();
      // TEACH THE ROUTER THE NEW PHRASES. Without this an activated capability was only reachable
      // by asking the CLOUD to route to it — so the user says the very phrase Plena just suggested,
      // gets "I didn't catch that" (or pays for a residual call), and reasonably concludes nothing
      // was built. Learning the examples makes the new skill work OFFLINE, immediately.
      for (final phrase in eg.take(4)) {
        // NEVER steal a phrase that already routes. learn() inserts at index 0 (learned entries win)
        // and only rejects catch-alls and exact duplicates — so a model-chosen example colliding
        // with a shipped phrasing ("log my mood as tired") would permanently reassign it to the new
        // capability, and the user's own entries would start landing in the wrong record type with
        // nothing said about it.
        if (router.route(phrase, clock: now, contacts: _knownContactTokens()) !=
            null) continue;
        final t = router.learn(phrase, skillId, const {});
        if (t != null)
          repo.appendCorpusLearned({'skillId': skillId, 'template': t});
      }
      // SAY WHAT ACTUALLY CHANGED, then CHECK. "Added X. Try: …" was technically true and
      // practically useless: after two confirmations the user couldn't tell whether anything had
      // happened, because the thing built (a log) looks like something the app already does. So
      // name the phrase that now works, name what it records, and ask — a "no" un-builds it.
      _pendingCapabilityCheck = {
        'typeId': typeId,
        'skillId': skillId,
        'displayName': '${draft['displayName']}',
      };
      // Humanise the field names — "loggedAt" is an implementation detail; "logged at" is a
      // sentence. This line is the whole point of the change, so it has to read like speech.
      String human(String n) => n
          .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
          .replaceAll('_', ' ')
          .toLowerCase();
      final fields = ((type['attributes'] as List?) ?? const [])
          .whereType<Map>()
          .map((a) => human('${a['name']}'))
          .where((n) => n != 'id' && n != 'type id')
          .take(4)
          .join(', ');
      final tryLine = eg.isNotEmpty
          ? ' Say "${eg.first}" and I\'ll record it'
          : ' You can start logging it now';
      return 'Learned it — "${draft['displayName']}".$tryLine'
          '${fields.isEmpty ? '' : ', keeping: $fields'}. '
          'Is that what you wanted? (say no and I\'ll forget it)';
    } catch (e) {
      // Rollback must undo EVERYTHING this method did. Removing only the type left a routable
      // skill whose type was gone — erroring on every dispatch until restart — while telling the
      // user nothing had been added. The learn loop below the assignment widened that window.
      types.remove(typeId);
      skills.remove(skillId);
      for (final t in router.corpus
          .where((c) => c.skillId == skillId)
          .map((c) => c.template)
          .toList()) {
        router.forget(t);
        try {
          repo.removeCorpusLearned(t);
        } catch (_) {/* inert */}
      }
      try {
        repo.removeDef('skills', skillId);
        repo.removeDef('types', typeId);
      } catch (_) {/* best effort */}
      return "I couldn't add that after all: ${e is ResolveError ? e.message : e}";
    }
  }

  /// Undo a just-activated capability: unregister it and delete its definition files, so a "no"
  /// leaves no trace rather than an orphan the user has to hunt down later.
  String _forgetCapability(Map<String, dynamic> check) {
    final typeId = check['typeId'] as String,
        skillId = check['skillId'] as String;
    types.remove(typeId);
    skills.remove(skillId);
    // UNTEACH THE ROUTING TOO. Activation taught this skill's example phrases to the corpus, so
    // removing only the definition left templates pointing at a skill that no longer exists — the
    // phrase still routed, and _dispatch's `skills[skillId]!` blew up on null. Every capability
    // removal has to take its routing with it.
    for (final t in router.corpus
        .where((c) => c.skillId == skillId)
        .map((c) => c.template)
        .toList()) {
      router.forget(t);
      try {
        repo.removeCorpusLearned(t);
      } catch (_) {
        /* the in-memory forget is what routing uses; a stale line is inert */
      }
    }
    try {
      repo.removeDef('skills', skillId);
      repo.removeDef('types', typeId);
    } catch (_) {
      /* the in-memory removal is what the user sees; a stale file is harmless */
    }
    // The RETRIEVAL index still embeds the forgotten skill — activation built it. buildRetrievalIndex
    // only assigns, so a stale key survives until restart and retrievalSuggest can still return it.
    // Rebuild from the CURRENT skills so nothing points at a capability that no longer exists.
    if (_retrievalEnabled) unawaited(router.buildRetrievalIndex(skills));
    return 'Forgotten — "${check['displayName']}" is gone. '
        'Tell me again in your own words and I\'ll try for a closer fit.';
  }

  /// The required input slots a routed skill left null (candidates for ProvideSlot).
  List<String> _missingRequired(
      Map<String, dynamic>? skill, Map<String, dynamic> slots) {
    final inputs = skill?['inputs'] as List?;
    if (inputs == null) return const [];
    return [
      for (final i in inputs)
        if (i is Map && i['required'] == true && slots[i['name']] == null)
          i['name'] as String
    ];
  }

  String _askForSlot(Map<String, dynamic>? skill, String slotName) {
    final inputs = skill?['inputs'] as List?;
    final input = inputs?.cast<dynamic>().firstWhere(
        (i) => i is Map && i['name'] == slotName,
        orElse: () => null);
    final prompt = input is Map ? input['prompt'] as String? : null;
    return prompt ?? "What's the $slotName?";
  }

  /// Resolve a slot answer through its declared type (date/datetime) so a ProvideSlot
  /// reply like "tomorrow at 5pm" becomes a real ISO value, like the corpus path.
  dynamic _coerceSlot(
      Map<String, dynamic>? skill, String slotName, String raw, DateTime now) {
    final inputs = skill?['inputs'] as List?;
    final input = inputs?.cast<dynamic>().firstWhere(
        (i) => i is Map && i['name'] == slotName,
        orElse: () => null);
    final type = input is Map ? input['type'] : null;
    final r = raw.trim();
    if (type == 'datetime') return router.resolveDateTime(r, now);
    if (type == 'date') return router.resolveDate(r, now);
    return r;
  }
}
