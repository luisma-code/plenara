# Plenara — Work Capsule (living doc)

**A continuously-updated working memory.** Unlike `SESSION-HANDOFF.md` / `HANDOFF.md` (point-in-time
snapshots), this file is kept **current as work happens** — the latest state, the live facts I need
at my fingertips, hard-won gotchas, decisions + rationale, and open threads. If you're a fresh
session, read this first; it should already be up to date. Keep it skimmable, prune stale lines.

_Last updated: 2026-07-15 — after shipping v8 (iOS-first voice tour + glyph vocabulary)._

---

## Current state
- **v8 shipped** (`releases/VERSIONS.md`; release point `6ceeeb2`). App **runs on the iPhone**, on the
  **Matilda (Premium, en-AU)** voice. Repo `origin/main` fully pushed, tree clean, tests green
  (**1676 v0 + 74 app**).
- **G-46 (generative recognition) DONE on `main`, NOT yet on the phone.** Spec 03 → v0.7 (Fable-reviewed
  SOLID); Phase 1 (cloud residual recognizes generative intents + dispatch + §6.3 follow-up) + Phase 2
  (learn recognition templates → 2nd phrasing routes offline; degrade→no-learn; correct→forget), both
  tested. iOS build **validated (compiles)**; on-device install is the pending Luis-gated step —
  **unlock the phone + reconnect the Anthropic key**, deploy, then test "can you suggest a gift for
  Elena" live (recognized by the cloud, no regex).
- Developing on **macOS**; **iPhone is P1**. Apple Developer Program **approved** (TestFlight not set up yet).

## Live facts / commands (grab these)
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
