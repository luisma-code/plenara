"""Build the labeled local-model routing eval dataset (Spec 05b §3 / G-20).

Mines the 05a corpus (05a-functional-examples.md, 05a-traces.md) — already
labeled utterance -> expected skill/route + slots — and adds paraphrase variants
(3-5 phrasings per base case) plus adversarial cases (class E) and the
records-vs-OOD boundary (class D, incl. the G-19 "what did I say about
<world-noun>" adversarials).

Unified task shape: every case is a candidate-discrimination problem. The
retrieval step has already narrowed to a <=5 candidate set; the small model
picks exactly one candidate id OR "none" (none fits -> escalate / author /
delegate), and extracts slots. This single shape scores A (routing), B (slots),
C (meta-intent -> expected "none"), D (OOD -> expected "none"; adversarial
personal -> expected search-records) and E (near-miss) uniformly.

Emits dataset.json in the rig root.
"""
import json
import os

RIG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- candidate pool: id -> (description, slot list) -------------------------
POOL = {
    "create-task":               ("Create a to-do item.", ["description", "dueDate?"]),
    "create-reminder":           ("Set a time-anchored reminder to do something (may be anchored to another record's date).", ["description", "dueAt?", "dateAnchor?", "dateOffset?"]),
    "create-recurring-reminder": ("Set a repeating reminder.", ["description", "recurrence"]),
    "log-interaction":           ("Record a dated note / interaction about a person.", ["contactName", "note", "date?"]),
    "query-last-interaction":    ("Look up when the user last interacted with a person.", ["contactName", "medium?"]),
    "add-contact-fact":          ("Store a fact/attribute about a person, optionally introducing a related person.", ["subjectName", "fact", "relatedToName?", "relationType?"]),
    "recall-contact-fact":       ("Retrieve a stored fact about a person.", ["subjectName", "query"]),
    "instantiate-template":      ("Start tracking something using a built-in tracker template.", ["templateName", "extraField?"]),
    "log-run":                   ("Log a completed run/workout.", ["distance", "duration?", "route?"]),
    "log-walk":                  ("Log a walk.", ["distance?", "steps?", "duration?"]),
    "log-meal":                  ("Log a meal / food eaten.", ["food", "calories?"]),
    "log-mood":                  ("Log a mood entry.", ["mood", "note?"]),
    "log-medication":            ("Log that medication was taken.", ["medName?", "time?"]),
    "show-streak":               ("Show a streak (current or longest) for a habit tracker.", ["tracker", "kind?"]),
    "search-records":            ("Semantic search across the user's OWN notes, journal and records.", ["query"]),
    "query-aggregate":           ("Compute an aggregate (sum/count) over the user's tracker records for a period.", ["tracker", "metric", "period"]),
    "undo":                      ("Undo the last action.", []),
}


def C(*ids):
    """Build a candidate list (subset of the pool) preserving given order."""
    return [{"skillId": i, "desc": POOL[i][0], "slots": POOL[i][1]} for i in ids]


cases = []


def add(cid, cls, utterance, cand_ids, exp_skill, exp_slots=None, note=""):
    cases.append({
        "id": cid,
        "class": cls,
        "utterance": utterance,
        "candidates": C(*cand_ids),
        "expected": {"skillId": exp_skill, "slots": exp_slots or {}},
        "note": note,
    })


# =============================================================================
# CLASS A — known-capability routing (utterance + <=5 candidates -> skill+slots)
# The core metric. Base cases mined from F-01..F-20, each with paraphrases.
# =============================================================================

# A1 task capture (F-01) — paraphrases
A_TASK = ["create-task", "create-recurring-reminder", "log-interaction", "search-records"]
add("A-task-1", "A", "Add call the plumber to my to-do list.", A_TASK, "create-task", {"description": "call the plumber"})
add("A-task-2", "A", "I need to call the plumber on Thursday.", A_TASK, "create-task", {"description": "call the plumber", "dueDate": "Thursday"})
add("A-task-3", "A", "Put pick up the dry cleaning on my tasks.", A_TASK, "create-task", {"description": "pick up the dry cleaning"})
add("A-task-4", "A", "Remind me to email the accountant tomorrow.", A_TASK, "create-task", {"description": "email the accountant", "dueDate": "tomorrow"}, "reminder/task twin absent here")

# A2 recurring reminder (F-03)
A_REC = ["create-recurring-reminder", "create-task", "create-reminder", "log-interaction"]
add("A-recur-1", "A", "Every second Tuesday, take the bins out.", A_REC, "create-recurring-reminder", {"description": "take the bins out", "recurrence": "every second Tuesday"})
add("A-recur-2", "A", "Remind me to water the plants every Monday morning.", A_REC, "create-recurring-reminder", {"description": "water the plants", "recurrence": "every Monday"})
add("A-recur-3", "A", "Set up a weekly reminder to back up my laptop.", A_REC, "create-recurring-reminder", {"description": "back up my laptop", "recurrence": "weekly"})

# A3 instantiate tracker template (F-04)
A_TMPL = ["instantiate-template", "log-run", "search-records", "create-task"]
add("A-tmpl-1", "A", "Start tracking my runs.", A_TMPL, "instantiate-template", {"templateName": "runs"})
add("A-tmpl-2", "A", "I want to start a mood tracker.", ["instantiate-template", "log-mood", "search-records", "create-task"], "instantiate-template", {"templateName": "mood"})
add("A-tmpl-3", "A", "Begin tracking my medications.", ["instantiate-template", "log-medication", "search-records"], "instantiate-template", {"templateName": "medications"})

# A4 log a run, multi-slot (F-05)
A_RUN = ["log-run", "log-walk", "log-meal", "instantiate-template"]
add("A-run-1", "A", "Ran 5k in 27 minutes on the river trail.", A_RUN, "log-run", {"distance": "5k", "duration": "27 minutes", "route": "river trail"})
add("A-run-2", "A", "Just finished a 10 kilometre run, took me 52 minutes.", A_RUN, "log-run", {"distance": "10 kilometre", "duration": "52 minutes"})
add("A-run-3", "A", "Logged an 8k run this morning.", A_RUN, "log-run", {"distance": "8k"})

# A5 last-interaction temporal query (F-09)
A_LAST = ["query-last-interaction", "log-interaction", "recall-contact-fact", "search-records"]
add("A-last-1", "A", "When did I last see Marco?", A_LAST, "query-last-interaction", {"contactName": "Marco"})
add("A-last-2", "A", "How long has it been since I caught up with Priya?", A_LAST, "query-last-interaction", {"contactName": "Priya"})
add("A-last-3", "A", "When did I last talk to my sister?", A_LAST, "query-last-interaction", {"contactName": "my sister"})

# A6 dated note on a person (F-02)
A_NOTE = ["log-interaction", "add-contact-fact", "create-task", "query-last-interaction"]
add("A-note-1", "A", "Note that Ana starts her new job Monday.", A_NOTE, "log-interaction", {"contactName": "Ana", "note": "starts her new job Monday", "date": "Monday"})
add("A-note-2", "A", "Write down that I had coffee with Tom yesterday.", A_NOTE, "log-interaction", {"contactName": "Tom", "note": "had coffee", "date": "yesterday"})

# A7 aggregate query (F-17)
A_AGG = ["query-aggregate", "show-streak", "query-last-interaction", "search-records"]
add("A-agg-1", "A", "How many steps did I do this week?", A_AGG, "query-aggregate", {"tracker": "steps", "metric": "sum", "period": "this week"})
add("A-agg-2", "A", "What's my total running distance this month?", A_AGG, "query-aggregate", {"tracker": "running", "metric": "sum", "period": "this month"})

# A8 streak (F-18)
add("A-streak-1", "A", "What's my longest reading streak?", ["show-streak", "query-aggregate", "search-records"], "show-streak", {"tracker": "reading", "kind": "longest"})
add("A-streak-2", "A", "How many days in a row have I meditated?", ["show-streak", "query-aggregate", "search-records"], "show-streak", {"tracker": "meditated", "kind": "current"})

# A9 derived-date reminder (F-19) — model extracts the EXPRESSION, code resolves
A_REM = ["create-reminder", "create-task", "create-recurring-reminder", "add-contact-fact"]
add("A-rem-1", "A", "Remind me to buy flowers the day before Sarah's birthday.", A_REM, "create-reminder", {"description": "buy flowers", "dateAnchor": "Sarah's birthday", "dateOffset": "-1 day"})
add("A-rem-2", "A", "Remind me to call Dad on his anniversary.", A_REM, "create-reminder", {"description": "call Dad", "dateAnchor": "Dad's anniversary"})

# A10 semantic search (F-12)
add("A-search-1", "A", "Find that note about the cabin trip.", ["search-records", "query-last-interaction", "recall-contact-fact"], "search-records", {"query": "cabin trip"})
add("A-search-2", "A", "Pull up what I wrote about the Lisbon conference.", ["search-records", "log-interaction", "recall-contact-fact"], "search-records", {"query": "Lisbon conference"})

# =============================================================================
# CLASS B — slot extraction focus, incl. multi-entity (F-07 nested people fact)
# =============================================================================
B_FACT = ["add-contact-fact", "log-interaction", "recall-contact-fact", "create-task"]
add("B-fact-1", "B", "Sarah's daughter Mia is allergic to peanuts.", B_FACT, "add-contact-fact",
    {"subjectName": "Mia", "fact": "allergic to peanuts", "relatedToName": "Sarah", "relationType": "daughter"}, "3 writes from one sentence")
add("B-fact-2", "B", "My boss Karen's husband is called Jo.", B_FACT, "add-contact-fact",
    {"subjectName": "Jo", "fact": "husband of Karen", "relatedToName": "Karen", "relationType": "husband"})
add("B-fact-3", "B", "Marco loves hiking and hates crowds.", B_FACT, "add-contact-fact",
    {"subjectName": "Marco", "fact": "loves hiking and hates crowds"})
add("B-fact-4", "B", "Note that Ana's son Leo just started school.", B_FACT, "add-contact-fact",
    {"subjectName": "Leo", "fact": "just started school", "relatedToName": "Ana", "relationType": "son"}, "fact-vs-interaction near miss")
# recall through the graph (F-08)
add("B-recall-1", "B", "What's Mia allergic to?", ["recall-contact-fact", "add-contact-fact", "search-records"], "recall-contact-fact",
    {"subjectName": "Mia", "query": "allergic to"})
add("B-recall-2", "B", "What does Marco like to do?", ["recall-contact-fact", "add-contact-fact", "search-records"], "recall-contact-fact",
    {"subjectName": "Marco", "query": "like to do"})
# medium-filtered query (F-10) — role alias + filter slot
add("B-medium-1", "B", "How long since I called Mum?", ["query-last-interaction", "log-interaction", "recall-contact-fact"], "query-last-interaction",
    {"contactName": "Mum", "medium": "phone"}, "role alias + medium filter slot")

# =============================================================================
# CLASS C — meta-intent: needed capability NOT in candidate set -> expect "none"
# Measured to confirm meta-intent should be retrieval-owned, not model-owned.
# =============================================================================
add("C-meta-1", "C", "I want to track my daughter's mood and what preceded her good and bad days.",
    ["log-mood", "log-interaction", "add-contact-fact", "create-task"], "none", {}, "P-01 novel authoring need")
add("C-meta-2", "C", "Track the gifts I give each person.",
    ["instantiate-template", "log-interaction", "add-contact-fact", "search-records"], "none", {}, "P-03 authored type w/ relation")
add("C-meta-3", "C", "When I log a workout, also add the distance to my weekly mileage total.",
    ["log-run", "create-task", "instantiate-template", "query-aggregate"], "none", {}, "P-05 define_skill")
add("C-meta-4", "C", "Track my expenses by category and show me a monthly breakdown.",
    ["instantiate-template", "query-aggregate", "log-meal", "create-task"], "none", {}, "P-16 authoring aggregation view")
add("C-meta-5", "C", "Start tracking which restaurants I visit.",
    ["instantiate-template", "log-meal", "log-interaction", "search-records"], "none", {}, "DF-01 no built-in template")
add("C-meta-6", "C", "Log my car's mileage.",
    ["instantiate-template", "log-walk", "create-task", "search-records"], "none", {}, "DF-09 no type")

# =============================================================================
# CLASS D — out-of-domain boundary (records-vs-OOD). Unified framing:
#   true OOD (world knowledge, no candidate fits) -> expect "none"
#   adversarial personal ("what did I say about <world-noun>") -> search-records
# =============================================================================
D_CAND = ["search-records", "query-last-interaction", "recall-contact-fact", "create-reminder"]
# true OOD -> none
add("D-ood-1", "D", "What's the weather tomorrow?", D_CAND, "none", {}, "DP-02 world knowledge")
add("D-ood-2", "D", "Who won the match last night?", D_CAND, "none", {}, "DP-02 sports")
add("D-ood-3", "D", "What's the capital of Australia?", D_CAND, "none", {}, "public fact")
add("D-ood-4", "D", "How tall is the Eiffel Tower?", D_CAND, "none", {}, "public fact")
# adversarial personal (G-19 privacy boundary) -> search-records (never OOD)
add("D-adv-1", "D", "What did I say about the weather on our cabin trip?", D_CAND, "search-records",
    {"query": "weather cabin trip"}, "G-19 adversarial: world-noun in a records query")
add("D-adv-2", "D", "What did I note about the Barcelona match we watched together?", D_CAND, "search-records",
    {"query": "Barcelona match"}, "G-19 adversarial: sports noun in records query")
add("D-adv-3", "D", "What did I write about our trip to Australia?", D_CAND, "search-records",
    {"query": "trip to Australia"}, "G-19 adversarial: place noun in records query")
add("D-adv-4", "D", "Remind me what I said the restaurant near the Eiffel Tower was called.", D_CAND, "search-records",
    {"query": "restaurant near the Eiffel Tower"}, "G-19 adversarial: landmark in records query")

# =============================================================================
# CLASS E — ambiguous / adversarial: near-miss candidates, coordinations, anaphora
# =============================================================================
# near-miss twin: run vs walk (F-14)
add("E-nearmiss-1", "E", "Log 5k.", ["log-run", "log-walk", "log-meal"], "log-run", {"distance": "5k"}, "F-14 default-to-run near miss")
add("E-nearmiss-2", "E", "Log 10,000 steps.", ["log-walk", "log-run", "show-streak"], "log-walk", {"steps": "10,000"}, "steps -> walk not run")
# task vs reminder twin (both present) — F-01 labelled create-task in corpus
add("E-twin-1", "E", "Remind me to call the plumber Thursday.", ["create-task", "create-reminder", "create-recurring-reminder"], "create-task",
    {"description": "call the plumber", "dueDate": "Thursday"}, "F-01: task/reminder twin both retrieved")
# fact vs interaction twin (F-02 looks like a fact)
add("E-twin-2", "E", "Note that Ana starts her new job Monday.", ["log-interaction", "add-contact-fact", "create-task"], "log-interaction",
    {"contactName": "Ana", "note": "starts her new job Monday"}, "F-02: dated event -> interaction not standing fact")
# recall vs add fact twin
add("E-twin-3", "E", "What's Mia allergic to?", ["add-contact-fact", "recall-contact-fact", "log-interaction"], "recall-contact-fact",
    {"subjectName": "Mia", "query": "allergic to"}, "read vs write twin")
# coordination — two tasks in one utterance
add("E-coord-1", "E", "Remind me to buy milk and call the dentist.", ["create-task", "create-reminder", "log-interaction"], "create-task",
    {"description": "buy milk and call the dentist"}, "coordination: two actions one skill")
# coordination — two trackers, one has no template (F-13)
add("E-coord-2", "E", "Track my mood and my energy.", ["instantiate-template", "log-mood", "create-task"], "instantiate-template",
    {"templateName": "mood"}, "F-13: mood instantiates, energy has no template (partial)")
# anaphora / context-dependent — no safe candidate -> none (needs prior turn)
add("E-ana-1", "E", "Actually, make it 28 minutes.", ["log-run", "create-task", "log-walk"], "none", {}, "F-15: slot correction needs prior-turn context")
add("E-ana-2", "E", "Same as yesterday.", ["log-run", "log-meal", "log-medication"], "none", {}, "anaphora: no referent in candidates")
add("E-ana-3", "E", "Undo that.", ["undo", "create-task", "log-run"], "undo", {}, "system command")

# =============================================================================
dataset = {
    "meta": {
        "spec": "05b §3 (G-20) local-model trust eval",
        "task_shape": "candidate-discrimination: utterance + <=5 retrieved candidates -> one skillId (or 'none') + slots + confidence",
        "classes": {
            "A": "known-capability routing (core)",
            "B": "slot extraction incl. multi-entity",
            "C": "meta-intent (novel need -> expect 'none', retrieval-owned)",
            "D": "out-of-domain boundary (true OOD -> 'none'; adversarial personal -> search-records)",
            "E": "ambiguous / adversarial (near-miss, coordination, anaphora)",
        },
        "n_cases": len(cases),
    },
    "cases": cases,
}

out = os.path.join(RIG, "dataset.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(dataset, f, indent=2)

from collections import Counter
by = Counter(c["class"] for c in cases)
print(f"wrote {out}")
print(f"{len(cases)} cases:", dict(sorted(by.items())))
