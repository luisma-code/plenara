/// Plenara v0 — the canonical set of CLOUD-path inputs. Both the fixture
/// recorder (bin/record_fixtures.dart) and the cloud-path tests import this, so
/// every input a test replays is one the recorder captured (no drift). Add an
/// input here, re-run the recorder, commit the refreshed test/fixtures/cloud.json.
library;

/// Novel phrasings the corpus can't match -> exercised through Haiku residual
/// routing (Spec 03 §7.3 / findings §13 E4). Grouped by the skill they SHOULD
/// resolve to, so tests can assert routing correctness against recorded reality.
const residualBySkill = <String, List<String>>{
  'create-task': [
    'jot down that I need to buy milk',
    'make a note to email the accountant',
    'put picking up dry cleaning on my to-do list',
    'I have to renew the car registration, add that',
    'jot down that I need to water the plants',
    'stick booking flights on my list',
  ],
  'log-run': [
    'I did a 6k jog this morning',
    'just finished running 8 kilometers',
    'went for a 5k this afternoon',
    'clocked a quick 3k',
  ],
  'log-mood': [
    'feeling pretty anxious today',
    'I am in a great mood',
    'honestly kind of down right now',
  ],
  'recall-facts': [
    'refresh my memory on Sarah Mitchell',
    'what have I got on Mia',
  ],
  'list-tasks': [
    'run me through my open items',
    'what have I got to do',
  ],
  'count-runs-this-week': [
    'how much running have I done since Monday',
  ],
};

/// Utterances that are NOT app capabilities -> Haiku should abstain (return
/// none/null), and the app clarifies rather than mis-acting.
const outOfDomainUtterances = <String>[
  "what's the capital of France",
  'tell me a joke',
  'what time is it in Tokyo',
];

/// Capability descriptions for the authoring path (Spec 02 §6). Each should
/// author a valid type + logging skill that passes the static validators.
const authoringDescriptions = <String>[
  'water intake',
  'daily gratitude journal',
  'books I have finished reading',
  'my weight',
  'coffee cups per day',
];

/// A flat list of every residual utterance, for the recorder.
List<String> get allResidualUtterances =>
    [...residualBySkill.values.expand((e) => e), ...outOfDomainUtterances];
