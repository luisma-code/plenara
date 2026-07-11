# v4 — First Contact (the play test)

**Release point:** `68a7c24` — 2026-07-09 ("Add a Free/Paid mode toggle (offline-only switch) in Settings")
**Runnable:** Windows GUI (.exe) with **on-device voice input**, + console.
**Span:** `9220ac0`/`5d1c641` (2026-07-08) → `68a7c24` (2026-07-09), ~75 commits.

## What this version is

v4 is the version that met its user. The BYOK key went into the config, the cloud tier ran
**live** for the first time, and the app was dogfooded through many real iterations — every
gap that surfaced becoming a same-day fix. At the release point Plenara is a voice-first
Windows assistant: tap the mic, speak, pause, and an on-device **Whisper base.en + Silero
VAD** pipeline (sherpa_onnx) transcribes and auto-sends — fully offline, private, with modern
accuracy. A keyless first launch lands on a Welcome screen and a guided "Connect Claude" flow
that validates the key live and diagnoses the #1 gotcha (valid key, no credits). The corpus
has grown from ~190 to **640 seed templates** plus 112 tracker phrasings; essentially every
catalogued free-tier phrasing gap is closed — spoken word-times ("half past six"), relative
times ("in 20 minutes"), weekday-set/monthly/yearly recurrence, positional deletes, multi-task
adds, back-dated interactions, bare mood statements, anchored predicates ("Sarah is allergic
to peanuts"), reverse fact search, unit-aware miles, task de-duplication. Content search,
offline fact recall, a 403-food nutrition knowledge base with mandatory provenance, real
per-turn cost telemetry, and a Free/Paid mode toggle round it out. 1,601 Dart + 38 app tests;
conformance 24/60.

## The journey from v3

**Live cloud, and the bugs the fakes hid.** The first hours with a real key were vindicating
— grounded gift ideas off a contact's actual hobbies, an honest weekly review of light
logging, authoring end-to-end through offer → preview → activate — and humbling. Four real
defects surfaced across three live passes that no fake had caught (`5d1c641`, `eae8072`,
`205706f`): a cloud-routed reminder with no time left ProvideSlot *stuck*, swallowing every
subsequent turn; an authored confirmation template leaked `{var:count}` syntax; natural slot
corrections ("actually that was 6k") missed; and "track my water intake in glasses" was
pre-empted by the eager ml-based template, silently dropping the unit — re-routed to
authoring so the user gets the tracker they described. The lesson was structural, not
incidental: the cassette proves the *pipeline*, only live traffic proves the *conversation*.
Cost went from guess to instrument the same day — real token usage per turn, spend/day in the
turnlog report; a cloud-heavy sample day measured $0.0037 (`ee31c43`).

**Onboarding as an engineering problem.** Research confirmed there is no OAuth or
programmatic key path from Anthropic — copy-paste is the only compliant mechanism — so the
flow was made near-foolproof instead: deep-link to the console, live validation, and a
`classifyHttp` that reads "credit balance too low" as billing rather than a generic server
error (`c80e67b`, `07523fd`).

**Voice: three engines in one day.** The seam (`SpeechRecognizer` + Noop fallback) came
first, per directive #1. The OS engine (speech_to_text → SAPI) went in behind it — and
dogfooding immediately exposed a maddening one-session-late transcript. The diagnosis is a
small epic: verbose lifecycle logging narrowed it, then **Fable read the plugin's shipped
C++ and root-caused it in SAPI's event handling** — no hypothesis events are ever registered
(so no partials exist on Windows), our pause timer therefore fired mid-utterance, and stop()
stranded the finished result on a reused recognition context, delivering it ~10-100ms into
the *next* listen (`f188921`). Worked around, then leapfrogged: sherpa_onnx streaming
zipformer replaced SAPI's ceiling (`66288ea`) — accurate enough to be responsive, but a
GigaSpeech all-caps model ("LIST MIGHT YOU DOES") — and the same day it was swapped for
**Whisper base.en gated by Silero VAD** (`65f01b8`): speak, pause ~1s, transcribed and sent.
Dogfood feedback drove the interaction design too: start/stop with live partials, then
auto-send on the final result — the text box became optional. Spec 14 documents the path,
including Luis's mid-course preference for the OS-managed model (tried honestly, outgrown
measurably).

**The phrasing campaign.** Six Fable agents brainstormed ~30 variants per capability;
`integrate.py` folded the survivors into the corpus with collision-ordering notes
(`0a83100`). Expansion at that scale is an over-match risk, so the hardening came with it: a
new `:entity` router guard (a name slot can't start with an article/pronoun — "remember the
alamo" stops being a person), six inherently ambiguous templates deliberately *dropped* to
the cloud, and 13 regression guards. The remaining ~54 gaps were catalogued as JSON worklists
(`planning/phrasing/*.json`) and then systematically closed across ~28 batches spanning
07-08/09 — each batch a skill/router/interpreter change + corpus + tests + full suite green.
The reusable machinery matters more than any single gap: constrained slot types (`dayword`,
`pastday`, `posword`, `moodword`, `mealword`, `predword` — bounded regexes that make the
correct split the only viable one, since the router never backtracks), compound AND-list
read filters, `split_list`/`position_index`/`years_since`/`weekday_nums` compute fns.
Mid-campaign the BYOK key went down — and the session kept working the no-re-record-needed
gaps until it was rotated back (`db17c9b`), a small proof of the cassette discipline's value.

**Reviews on both halves.** A Fable engine review caught a critical learning bug — learn()
abstracting a known contact to `:text` would have persisted a template that hijacked all
"what is X…" world-knowledge (`4e4083e`) — plus the trailing-punctuation slot leak and a
null-date `gte` miscount. The app review fixed key-UX honesty (a valid-but-no-credits key is
now *saved*), mic teardown privacy, and `ensureSeeded` failing loudly on a missing seed
source instead of booting capability-less (`7dea2c4`).

**Redirects of the era:** a separate log-run-miles skill confused the cloud router and was
reverted for a unit-aware slot on the same skill (`2103292`) — a rule ("unit-aware single
skills, not parallel skills") recorded for the future. F-08's earlier over-broad template was
resurrected correctly via the new `:contact` slot guard (`44282e3`). Task and goal
duplicates — the first genuinely user-reported bugs — got dedup (`3e9840c`) and upsert
(`3e4ab45`) semantics.

## What shipped

- Live cloud validation + 4 live-caught fixes; per-turn cost capture; Free/Paid toggle.
- Guided BYOK connect + WelcomeScreen onboarding.
- On-device voice: seam → SAPI (root-caused) → sherpa zipformer → Whisper + VAD; Spec 14.
- Offline fact recall (`:contact` guard, F-08), content search (F-12), nutrition KB
  (Spec 13: `read_reference`, provenance-mandatory, honest misses).
- Corpus 190→640 templates + `:entity` guard; ~28 phrasing-gap batches; new slot types and
  compute fns; task/goal dedup; clear-tasks; domain-scoped help.
- Fable engine + app review fixes. 1,601 Dart + 38 app tests green; conformance 24/60.

## Known gaps at release

Deliberately left: non-running goal units/periods (no data source to track against),
paid-template internals, agent-flagged unsafe phrasings ("i did the laundry" collides with
activity logging), event-relative reminders (cloud path). The Whisper model is
pre-provisioned in `~/.plenara/models` — download-on-first-run remains a pre-distribution
task, as does bundling seed data as Flutter assets. Cloud-side entity handling was still
naive — the very next dogfood night would prove it (duplicate contacts), which is v5's story.

## Toolchain / runnable note

Windows GUI (.exe) with voice. Native build needs CMake ≥3.23 (4.3.4 installed, VS2019 cmake
symlinked) for record_windows; sherpa_onnx/onnxruntime DLLs bundle into the build. Runnable
release binary — the closest yet to a distributable app, minus model download and asset
bundling.
