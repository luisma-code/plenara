# Plenara — Work Capsule (living doc)

**A continuously-updated working memory.** Unlike `SESSION-HANDOFF.md` / `HANDOFF.md` (point-in-time
snapshots), this file is kept **current as work happens** — the latest state, the live facts I need
at my fingertips, hard-won gotchas, decisions + rationale, and open threads. If you're a fresh
session, read this first; it should already be up to date. Keep it skimmable, prune stale lines.

_Last updated: 2026-07-28 — TestFlight is LIVE (deploy-from-anywhere works, first release shipped). Correctness + data-integrity review pass: 12 defects found, reproduced, fixed, regression-tested._

---

## Current state
- **TestFlight works end to end — the deploy-from-anywhere blocker is GONE.** Luis did the
  Apple-account batch; `0.8.0+8` uploaded, processed, and distributed on 2026-07-28. App record
  `6795650460`; internal group **Internal** (`23726f32-08a5-4c99-9470-5eecd52760ea`); Luis is
  ACCOUNT_HOLDER/ADMIN and an internal tester. **Claude owns the whole release loop now** — no
  browser step. See "Live facts" for the commands.
- **Correctness + data-integrity review pass (2026-07-28) — 12 defects, all reproduced before fixing
  and pinned with regression tests.** v0 **1731** + app **80** green, analyze clean. The severe ones:
  - **A torn `corpus-learned.json` permanently bricked launch.** Whole-file rewrite was
    non-atomic and `Router.load` jsonDecoded it inside `init()` — a crash mid-write meant the app
    never opened again until the file was hand-deleted. Every learn/forget hit that path. Now
    atomic + tolerant. Same class found and fixed for the **seed corpus** and **`config.json`**
    (a torn config silently lost `dataDir` + API key → app opens on an empty folder, reads as
    total data loss).
  - **Undo was lost exactly when it mattered.** The journal entry was pushed AFTER the persist
    loop, so a disk failure left the change live in memory, unjournalled, un-undoable — while
    `handle()` told the user "I didn't do anything". Now journal-then-persist.
  - **An approved automation write wasn't undoable** (violates the CLAUDE.md rule) and worse,
    "undo that" then reversed an unrelated earlier write.
  - **CRDT stamping was wrong for list/map fields** (`==` is identity in Dart → re-stamped every
    write) and **a cleared field left no tombstone** (peer's old value resurrects on sync).
  - `write_record` did no schema coercion; `add()` silently concatenated numeric strings.
- **Still outstanding: the app ships Flutter's PLACEHOLDER app icon + launch image.** That's what's
  on the home screen now. Cosmetic for TestFlight, an automatic rejection at App Review.
- **v8 shipped** (`releases/VERSIONS.md`; release point `6ceeeb2`). App **runs on the iPhone**, on the
  **Matilda (Premium, en-AU)** voice. Repo `origin/main` fully pushed, tree clean, tests green
  (**1676 v0 + 74 app**).
- **G-49 (numbered corrections + editable data view) — renamed from G-47 (that number was taken by
  the gap register). 4-lens Fable review done; ALL confirmed defects fixed + regression-tested.** The
  two majors were data-corruption paths: (1) a mixed-type readback (recall-facts numbers facts AND
  relationships) wrote a junk field on the wrong type on "change N to X" → fixed with a PER-ITEM
  `{id,typeId,labelField}` reference channel; (2) a manual data-view edit between a spoken write and a
  voice "no, I meant…" made the correction reverse the wrong journal entry → manual writes now clear
  the spoken-correction context + the data-view snackbar uses a TARGETED `undoById(token)`. Plus: a
  date-picker crash on any date >5y old (birthdays) → clamped; edit-failure was invisible behind the
  modal sheet → now inline `errorText`; ref-by-number commands could be swallowed mid ProvideSlot →
  guarded; ref actions killed a live Tour → kept alive; `ref_mark` id/label now var-closure-checked;
  execute() before-image uses putIfAbsent; +orderBy on the numbered read_many skills; learned-flow
  forget/restore hardened (token synthesis + dedupe). Specs 02/03/07 synced (§3 ops, §2.3a
  reference-by-number, §5.5 posture), gap register row added. **v0 1718 + app 80 green.**
- **TestFlight — Mac-side plumbing done, GATED on Luis.** Release archive builds clean;
  `tool/testflight-upload.sh` exports+uploads a signed IPA via an App Store Connect **API key** (no
  Xcode login needed — `xcodebuild -allowProvisioningUpdates` auto-creates the distribution cert).
  Blocker: the machine has no distribution cert / no Apple account in Xcode → Luis must (1) create the
  App Store Connect app record for `com.plenara.plenaraApp`, (2) generate an **Admin** API key (.p8 +
  Key ID + Issuer ID) → drop in gitignored `tool/.testflight.env`, (3) add himself as an internal
  tester. Then Claude runs one command. Full steps in `TESTFLIGHT.md`. Remote deploy across networks
  is impossible today (device shows `unavailable` off the Mac's LAN — that's what TestFlight fixes).
- **G-46 (generative recognition) DONE on `main` + code-review-clean, verified LIVE, NOT yet on the phone.** Spec 03 →
  v0.7 (Fable-reviewed SOLID); Phase 1 (cloud residual recognizes generative intents + dispatch + §6.3
  follow-up) + Phase 2 (learn recognition templates → 2nd phrasing routes offline; degrade→no-learn;
  correct→forget), both tested. **A 2-lens Fable code review found 8 real bugs — ALL 8 fixed + tested**
  (forget-on-correct on corpus-match, _splitCompound crash on a generative half, learnGenerative
  substring-corruption → word-boundary + round-trip, _pendingGen swallowing commands, retrieval-index
  skillId '' crash, near-dup accumulation, non-string contact, **#8 silent multi-action drop → now
  skipped-and-counted + admitted, P2.8** `f4e018b`). v0 **1680 green**, app analyze clean. iOS build
  **validated (compiles)**; on-device install is the pending Luis-gated step —
  **unlock the phone + reconnect the Anthropic key**, deploy, then test "can you suggest a gift for
  Elena" live (recognized by the cloud, no regex).
- **G-47 (two features) DONE on `main`, NOT yet on the phone** — Fable-designed, both accepted:
  1. **Numbered-list corrections.** Every list Plena reads back is now numbered ("1. …, 2. …"), and
     you reference an item by the number spoken — "delete 2", "complete 1", "correct 3" (two-turn
     re-speak) or "change 2 to X" (one-turn). Fixes the misheard-item problem ("Zpack my clothes" was
     un-retargetable). Two new closed-vocab DSL ops — `enumerate` (flat lists) + `ref_mark` (captures
     a ref from inside a foreach for rich/conditional/joined readbacks); ~18 list skills converted
     across every domain. Session `_enumCtx` (survives intervening turns, cleared on empty readback)
     + `_pendingCorrection`; offline regex recognition; all three actions journaled so "undo that"
     reverses them. 15 corrections tests.
  2. **Editable "Your data" view.** The existing read-only archetype view (`app/lib/data_view.dart`,
     behind the "…" menu) is now editable: Spec 07 §5.5 per-value tap-to-edit (NO forms — D5),
     delete-with-undo-snackbar, and a "Learned phrases" card showing what Plena learned to recognize
     from how Luis talks (humanized templates) with a per-phrase forget (+ undo). Six new Session
     facade methods (`editField`, `deleteRecord`, `undoLast`, `learnedFlows`, `forgetLearnedFlow`,
     `restoreLearnedFlow`) + `Router.restore`; ALL edits ride the ONE journal, so voice "undo that"
     reverses a manual edit. `ManualWrite`/`LearnedFlow` value types (no exceptions across the UI
     seam). 9 facade + 4 widget tests. **Ran `tool/sync_seed.sh`** — app carries the numbered skills.
  Tests: **v0 1704 + app 78, all green.** On-device is the pending Luis-gated step.
- Developing on **macOS**; **iPhone is P1**. Apple Developer Program **approved** (TestFlight not set up yet).

## Live facts / commands (grab these)
- **SHIP A RELEASE (TestFlight — works from anywhere, no browser, no Xcode login).** Bump
  `version:` in `app/pubspec.yaml` first — the `+BUILD` must strictly increase or Apple rejects the
  binary as a duplicate. Then, after the env evals:
  ```
  cd app && flutter build ipa --release      # its OWN export step fails on signing — EXPECTED, ignore
  ../tool/testflight-upload.sh               # re-exports signed + validates + uploads (this is the real one)
  ../tool/asc.py status                      # wait for processingState=VALID (~2-15 min)
  ../tool/asc.py release                     # distribute newest build to the Internal group
  ```
  `tool/asc.py` = App Store Connect API client (status/groups/add-tester/invite/release/raw). Needs
  the venv at `~/.plenara-asc/venv`; recreate with
  `python3 -m venv ~/.plenara-asc/venv && ~/.plenara-asc/venv/bin/pip install 'pyjwt[crypto]' requests`.
- **TestFlight identifiers:** app record `6795650460`; internal group `Internal`
  `23726f32-08a5-4c99-9470-5eecd52760ea`; key `AQMT4FFHKW`, issuer `12ee92f1-bd97-4747-bc50-87c476d9eb9b`;
  `.p8` at `~/.plenara-asc/AuthKey_AQMT4FFHKW.p8` (mode 600) — **Apple allows the download only once,
  do not delete both copies**. Config in gitignored `tool/.testflight.env`.
- **iPhone:** "Aluminum Monster", id **`00008140-000645442862201C`**, iOS 26.5.2. Bundle
  `com.plenara.plenaraApp`, team **`7V63BZ39HU`**, `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (intentional —
  we want newest APIs).
- **Deploy to phone (release, verbose logs):** from `app/`, after the env evals —
  `flutter run --release --dart-define=PLENARA_DEBUG=true -d 00008140-000645442862201C`
  (release-mode = no debug-attach mDNS/Impeller pitfalls; kill the Mac console after, app stays).
- **Build env evals:** `eval "$(/opt/homebrew/bin/brew shellenv)"; export LANG=en_US.UTF-8; export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **Pull device logs (no cable needed via the wireless tunnel):**
  `xcrun devicectl device copy from --device 00008140-000645442862201C --domain-type appDataContainer --domain-identifier com.plenara.plenaraApp --source Documents/plenara-logs --destination <dir>`
  (libimobiledevice/idevice* can't see the wireless device; use devicectl.)
- **Console-launch to capture stdout/crash signal:** `xcrun devicectl device process launch --console --terminate-existing --device <id> com.plenara.plenaraApp`
- **Keep the Mac awake all session:** `caffeinate -dimsu` detached (see CLAUDE.md). Currently running.
- **Glyph preview loop:** `flutter test test/glyph_render.dart` → PNG sheet in system temp; then read it.

## Hard-won gotchas (the gold — don't rediscover these)
- **`flutter build ipa` ALWAYS prints `exportArchive No Accounts` / `No signing certificate "iOS
  Distribution" found` — that is EXPECTED and not a failure.** It builds the `.xcarchive` fine; only
  its own export step can't sign (no Apple account in Xcode, by design). `tool/testflight-upload.sh`
  re-exports that same archive with the API key. Don't chase these errors, and don't grep build logs
  for `error:` to decide whether a release worked — grep for `UPLOAD SUCCEEDED`.
- **TestFlight is NOT preinstalled on iOS** — it's a separate free Apple app from the App Store, and
  it must be signed into the SAME Apple ID that owns the developer account.
- **An internal tester's API `state` stays `NOT_INVITED` even after a successful invite (201).** For
  internal groups that field is effectively cosmetic — access comes from the TestFlight app itself.
  The real proof a build reached a tester is `GET /v1/builds?filter[betaGroups]=<groupId>`. Note the
  `builds->betaGroups` relationship allows only CREATE/DELETE, never GET_RELATED.
- **Make the beta group INTERNAL, never external.** An external group drags every single release
  through Apple's Beta App Review (days of latency). Internal is instant, capped at 100 testers.
- **Work-MDM blocked the dev-cert verification** ("internet connection needed to verify") — the
  corporate network blocked Apple's check. **Removing the work management profile cleared it.** If a
  work phone is used again → **TestFlight** (MDM devices install App Store/TestFlight apps fine).
- **iOS rotates the app's container UUID on each `flutter run` reinstall** → data + API key are
  **wiped every redeploy** (you re-onboard + re-pick voice each time). Stable on normal use + TestFlight.
- **iOS has no `HOME` env var** → v0's `~/…` paths collapse to non-writable `./…` (white-screened the
  first build). Fix: app injects the Documents dir (`config.homeOverride`, via path_provider) **before**
  any config/log path; and `dataDir` is **re-derived live** on mobile (never trust a stored absolute
  container path). Apps may only write under `<container>/Documents|Library|tmp`, never the root.
- **Impeller (iOS's only renderer; Skia removed) crashes on the presence's per-frame `toImageSync`
  comet-trail** — native GPU abort, no Dart exception. iOS skips the offscreen persistence (Plena
  animates, **no lingering trail on iOS for now**). `FLTEnableImpeller=false` just fails to launch.
- **iOS TTS needs a `.playback` audio session** (re-asserted **before every utterance**) so Plena is
  audible in silent mode (like Siri) and after Apple-Speech STT leaves the session in record mode.
- **Natural voices are a user download** (Settings → Accessibility → Spoken Content/Read & Speak →
  Voices). App auto-picks the best installed; the in-app picker (Settings → Voice) lets the user choose.
- **Locked phone → "Could not run …Runner.app"** on deploy. Unlock + keep awake, then re-run.
- **`path_provider_foundation` pinned to 2.4.1** (dependency_overrides): its 2.6.0 native-assets build
  hook (`package:objective_c`) breaks `flutter build --release` because a **stale Xcode keychain
  credential** (`91B206EB…`, "missing Xcode-Username") corrupts the hook's `xcrun` stdout parse.

## Open threads / deferred (with reasons)
- **Generative recognition via the cloud residual (G-46) — Phase 2 (learning) still to do.** The
  dogfood miss ("suggest a gift for Elena" → clarify) was root-caused to generative intents being
  regex-only + the residual being skill-scoped. Spec 03 → v0.7/G-46 (co-designed + reviewed with Fable,
  SOLID). **Phase 1 SHIPPED:** `routeResidual` carries the fixed generative-kind inventory and returns
  `{generativeKind, params}`; `session._dispatchGenerative` runs it (missing contact → §6.3 follow-up);
  the `_giftRe` band-aid is reverted + the regexes frozen. So novel phrasings no longer dead-end.
  **Phase 2 SHIPPED — the "evolve local handling" half:** `router.dart` now stores + matches a
  `generativeKind`-target corpus entry; `learnGenerative` abstracts the contact to `{contact:entity}`
  and learns on a DELIVERED synthesis (`GenerativeService.lastDelivered` flag — degrade/unknown-person/
  offline turns don't learn); a learned template routes the 2nd identical phrasing OFFLINE (no residual
  call), and a next-turn "correct" forgets it (§5.2 negative half). Tested end-to-end (learn→offline,
  degrade→no-learn, correct→forget). So the loop is closed: Claude recognizes a novel phrasing once,
  the DSL absorbs it — no regex edits. (End-state retrieval migration still deferred, `G-44`.)
  **Code-review arc CLOSED** — all 8 findings fixed + regression-tested; the last (#8, a generative
  half silently dropped from a mixed batch) now surfaces a "ask me that on its own" coda instead of
  vanishing. Nothing left on-repo; only the Luis-gated device deploy remains.
- **flutter_tts shares one static method-channel handler** (deferred from the 5-lens Fable review):
  every extra `FlutterTts()` (voice enumeration on each Settings/onboarding open + resume, and the
  preview instance) re-registers the handler, so the main voice's `setStartHandler`/`setErrorHandler`
  go dead on iOS after the Voice card is shown (onStart audio-anchor + tts error logs degrade; speech
  still works), and a **preview shares the one native synthesizer** so it can stop a live reply. Fix
  needs a single shared `FlutterTts`/`FlutterTtsSpeechOutput` (inject the app's into the card). Soft
  impact today, so deferred.
- **Impeller-safe comet trail on iOS** — restore the persistence trail without the toImageSync crash.
- **Clean the stale Xcode keychain credential** `91B206EB-734B-447D-B085-D12AAC3EC664` (then un-pin
  path_provider_foundation).
- **TestFlight setup** — the goal "work remotely, push to my phone" wirelessly (Dev account approved).
- **iOS notifications** (currently FakeScheduler — on-open nudges only) + **iOS synced-folder storage**.
- **Glyph polish** — bell could move closer to Luis's reference; pairings are aesthetic/tunable.

## Decisions worth remembering (why)
- **Release-mode is the iOS deploy path** (not debug): debug's mDNS/Local-Network attach + Impeller are
  the pitfalls; release sidesteps both and the app runs standalone.
- **Voice-first display:** Plena *speaks* replies with no on-screen text; captions only when muted.
- **Glyphs refined by render-and-review**, not by guessing (`test/glyph_render.dart`); Fable proposes
  shapes, we render + compare to references.
- **iOS requires newest APIs on purpose** (deployment target 26.0) — no backward-compat baggage.

## Doc map
- **This file** — living working memory, kept current.
- `SESSION-HANDOFF.md`, `HANDOFF.md` — session/history snapshots (older; this capsule supersedes the
  "what's the current state" role — consider folding them in over time).
- `TRANSITION.md` — macOS specifics. `planning/` — design specs. `releases/VERSIONS.md` — milestones.
