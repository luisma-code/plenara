# v5 — The Router Grows Up (entity resolution + the self-improving corpus)

**Release point:** `1c06393` — 2026-07-10 ("feat(learning): cloud-suggested templates, round-trip validated (self-improving corpus)")
**Runnable:** Windows GUI (.exe) with voice, + console + `bin/dogfood.dart` CLI.
**Span:** `933b46a` → `1c06393` (2026-07-10), 20 commits.

## What this version is

v5 is what a night of *real* dogfooding — real spouse, real dinners, real contacts — did to
the cloud tier. At the release point the residual router is no longer a stateless
single-intent classifier: it **knows the user's contacts** and reuses them ("Katherine" →
"Katherine Zinger", no duplicate); it returns **multi-action** routes ({"actions":[…]}), so
"lunch with Sarah Chen and Mike Torres yesterday" logs one interaction per person, undoable
as a single turn; it distinguishes **future plans from past interactions** (a `planned` flag,
log-plan, "when am I seeing X next", and last-interaction excluding plans); it resolves
relative dates against the *real* clock instead of the model's stale training date; and it
captures the memory that matters — setting and remarks into the note, a relationship named
in passing always its own record. Contact find-or-create gained a general `resolve` mode
(unique whole-word token match reuses; ambiguity clarifies; zero matches creates), killing
the duplicate class at the root. And the corpus learning loop closed its last gap: the cloud
now *suggests the template itself*, abstracted from the surface, which the router adopts only
after a full round-trip validation — so date/time phrasings the verbatim learner could never
capture ("pop a todo to sand the deck on Sat") cost one cloud call and then serve offline
forever. Observability kept pace: the turnlog traces what every read *resolved to*, Settings
shows a full cloud-usage panel, and each cloud-touched reply carries a green dot keyed on
actual token spend. 1,643 Dart + 38 app tests.

## The journey from v4

**Every feature in this version began as a named dogfood bug.** The stored spouse that
recall couldn't see (facts and relationships were separate read paths — `933b46a`). The
duplicate Katherine (the router had never been shown the user's contacts — `6f49b69`). The
dinner that logged only one guest (single-skill routing — `b4d7941`). Tonight's dinner
recorded as a past conversation (`dd76061`). "Yesterday" dated 2024-12-18 (the model resolving
relative dates against its training data — fixed by instructing verbatim passthrough to the
deterministic resolver). A multi-record statement dying with "unexpected response from the
cloud" — the 200-token response cap truncating the actions JSON mid-array (`8600b82`).
The two-sentence utterance swallowed whole by the greedy `i just had {food}` template —
compound utterances now route to the cloud's multi-action path (`c65ca3e`). Each fix was
verified *live*, and prompt changes got their own instrument: `bin/usecase_harness.dart`,
eight representative cases run against the real cloud so tuning is validated by eyeball, not
vibes. Prompt determinism itself became a workitem — "one record per person" had to be made
an explicit rule before multi-person routing went 6/6 (`e1d86f8`).

**Then the whole thing was audited.** A full Fable review — 44 agents, 33 adversarially
confirmed findings — swept the upgrade, and every HIGH was fixed in four batches
(`2f6aad9`..`d70b96d`): resolve-mode reuse restricted to a *unique* token match (two Johns
now clarify instead of a silent length-based guess); a self-relationship guard ("Maria is
Maria Elena's mother" can no longer collapse two people into one); dateless tasks leaking
into "due by" lists; recurring reminders appearing in date-windowed lists on the wrong day;
multi-action turns made a single undo unit, with skipped actions admitted rather than
silently dropped; bare weekdays in `pastday` back-dating the right direction; word-time
over-matching ("five miles" is not five o'clock); and free mode actually free (it had been
falling back to the env key). Findings deliberately left are recorded as trade-offs in the
handoff — reusing the shorter "Katherine" name prevents the duplicate and is the same person;
correction-after-multi-action already has undo-whole-turn.

**The capstone is the learning commit.** `1c06393` is small but is the thesis of the whole
NLU design finally complete: the make-or-break metric since the v0-era measurements was
corpus-learning rate, and verbatim-only learning had a structural ceiling (any slot whose
resolved value differs from its surface form — every date, every time — could never be
learned). Letting the model propose the abstraction while the router trusts nothing it can't
round-trip (known slot types, a surviving literal, compiles, matches, re-extracts to the
exact dispatched slots, second-pass so it can never shadow a seed) keeps the determinism
guarantee while removing the ceiling. Proven live in the commit message: one cloud call,
then the phrasing — and its cousins — serve offline.

## What shipped

- Cloud router: known-contact entity resolution; multi-action routing; plans-vs-past;
  verbatim relative dates; interaction kind/setting/remarks capture; bounded contact list
  in the prompt.
- General contact de-duplication (`resolve` mode) across every find-or-create skill.
- Cloud-suggested, round-trip-validated corpus templates — the self-improving corpus.
- Observability: per-read resolution traces, Settings cloud-usage panel, per-reply cloud
  dot, dogfood CLI reporting offline/cloud per turn.
- Full Fable review (33 findings) fixed in four batches; live use-case harness.
- Offline: weekday abbreviations, "add a todo…" templates, relationship-aware recall.

## Known gaps at release

Same-person shorter-name reuse is an accepted trade-off; per-action ProvideSlot in a batch
doesn't exist (missing-slot actions are skipped and admitted); the presence/UI layer is still
a plain chat window — which is precisely what v6 turns to. Distribution tasks (model
download, asset bundling, MSIX packaging for toast-cancel) still open.

## Toolchain / runnable note

Windows GUI (.exe) with voice; also `bin/dogfood.dart` for CLI dogfooding against the same
data folder and engine. Suitable for a GitHub Release binary.
