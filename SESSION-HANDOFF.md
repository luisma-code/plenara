# Plenara — Session Handoff (read this first)

_Written 2026-07-14 to hand off to a fresh session after new global defaults were configured._

> **First thing:** read this file, then `CLAUDE.md` (working mode + principles), then `HANDOFF.md`
> (full history — the top has the newest session blocks + the overnight-incident post-mortem), then
> `TRANSITION.md` (macOS specifics). The Claude auto-memory carries the macOS env setup; everything
> else you need is in these docs.

## Where we are

- **Platform:** developing on **macOS** (moved from Windows). iPhone is the **P1** target.
- **Repo:** `origin/main` == local, **fully pushed** (HEAD ≈ `ed2f9ec`). Working tree clean.
- **Green:** full `tool/precheck.sh` passes — v0 **1670** tests, app **65** widget tests, 3 real-GPU
  integration tests, coverage floor, conformance 24/60 (baseline 24), 2-OS CI workflow.
- **The app builds + runs on Mac.** Run it with **`bash app/tool/dev-run.sh`** (NOT bare
  `flutter build`) — it re-signs with the stable "Plenara Dev" identity so mic permission persists.

## ✅ DEPLOY TO IPHONE — DONE (2026-07-14)

Plenara now installs and runs on the iPhone ("Aluminum Monster"). What it took:
- **Apple Developer account approved**; Xcode auto-populated `DEVELOPMENT_TEAM = 7V63BZ39HU`.
- **The real blocker was the work-MDM profile** on the phone — it forced an on-device
  developer-cert online verification ("internet connection needed to verify") that the corporate
  network blocked. **Removing the work management profile cleared it.** (If a work phone is used
  again, TestFlight is the clean path — MDM devices install App Store/TestFlight apps normally.)
- **Deploy is release-mode standalone:** `bash` →
  `flutter run --release --dart-define=PLENARA_DEBUG=true -d 00008140-000645442862201C`
  (prefix with the brew/DEVELOPER_DIR evals). Release has no Dart VM, so it **sidesteps the
  debug-attach mDNS/Local-Network-permission wall** that made `flutter run` (debug) "exit right
  after launch." The app installs + launches; the Mac-side console can be killed, the app stays.
- **Logs off-device:** Settings → Diagnostics → **"Share diagnostics"** bundles every on-device
  `.log` into one ~1 MB-capped `.txt` and opens the share sheet (email it out — no cable). Verbose
  traces are ON in this build via the `--dart-define`. (Files-app retrieval still works too.)
- **Gotcha fixed:** `path_provider_foundation` is pinned to **2.4.1** (dependency_overrides) — its
  2.6.0 native-assets hook (`package:objective_c`) breaks `flutter build --release` because a stale
  Xcode keychain-credential warning corrupts its `xcrun` stdout parse. Cleaning that keychain
  account (`91B206EB…`, "missing Xcode-Username") is a deferred follow-up; the pin avoids it for now.

### Old notes (kept for reference) — the pre-deploy staging
Everything was staged; it was blocked only on Luis-gated steps:
1. **Apple Developer Program** — Luis is enrolling ("pending"). $99/yr, Individual account. Unlocks
   **TestFlight** (wireless/remote push — the goal: "work remotely, push to my phone") **and** App
   Store. A free app costs nothing beyond the membership.
2. **Xcode signing** — Luis must add his Apple ID (Xcode → Settings → Accounts) and set the **Team**
   (Runner target → Signing & Capabilities → Automatically manage signing → Team). Currently
   **`DEVELOPMENT_TEAM` is unset** — that's the gate. If the bundle id `com.plenara.plenaraApp`
   conflicts on a free/personal team, change it to something unique.
3. Then: iPhone **"Aluminum Monster"** (`00008140-000645442862201C`) is in Developer Mode + trusted;
   `flutter run -d <iphone-id>` deploys. (The iOS runner `app/ios/` is generated, configured with
   mic/speech usage strings, and `flutter build ios --no-codesign` succeeds — all plugins link.)
- **iOS diag logs** are already retrievable remotely: they write to the app's Documents dir with
  `UIFileSharingEnabled`, so grab them via **Files app → On My iPhone → Plenara → plenara-logs**
  (works on TestFlight too). No cable needed.
- **Known iOS gaps (fine for testing, real follow-ups):** sandboxed storage (no synced folder yet —
  enter the BYOK key via the in-app **Settings** screen); reminders use the in-memory FakeScheduler
  (on-open nudges, not real iOS notifications — `_platformScheduler` only wires macOS/Windows).

## New global defaults now in effect (`~/.claude/CLAUDE.md`)

These were just configured — honor them:
- **Default = SHORT turns** (Luis at the keyboard). One meaningful step, then hand back so he can
  redirect. Only go heads-down when he explicitly says **"working mode" / "agentic mode"** (= he's
  leaving the machine).
- **Minimize manual reruns:** do ALL known work first, then trigger the one manual rerun.
- **Always push after committing** — in the same turn. (Auth is set up; `git push` works.)
- **RAM watch + cleanup (hard rule, from an incident):** whenever you launch the app in work mode,
  **sample its RSS and kill it if it's climbing**; **never leave an app instance running** when work
  is done. A short soak that plateaus is **NOT** proof of no leak.

## Recently shipped (newest first) — so you don't relitigate

- **Overnight RAM-balloon incident → FIXED.** The app left frontmost overnight exhausted RAM
  (AppLifecycleState doesn't change on display-sleep, so it rendered forever). Fix: **idle
  suspension** in `plena.dart` — no pointer/key input for 3 min ⇒ the presence suspends (zero
  frames); any input resumes. See the `HANDOFF.md` incident block. (Also fixed a real per-frame
  `ui.Gradient` GPU leak earlier — the aura now draws the cached sprite.)
- **Fable's UI/render test net:** P0 headless Picture/Image leak audit (MUTATION-validated), a
  precheck `[4b]` static shader lint, §9.1 suspend-when-hidden, P1 numeric render-and-measure
  invariants, resize-crash guard, M5/M6/semantics. Honest limits documented in `HANDOFF.md`
  (in-test memory soak is invalid; `leak-check.sh` is a diagnostic not a gate; goldens skipped).
- **Two-reviewer pass** (Fable prod review + test-sufficiency audit) — all fixes landed.
- **Tour v1** — "what can you do?" is a guided conversation (chapter state machine in `session.dart`).
- **List-reply redesign** — Plena flies to the corner over one unified void; three-register text.
- **macOS voice** — Apple Speech (built-in), audio barrier, live transcript, "I heard: X".

## Environment / how to run (macOS)

- Toolchain via Homebrew (owned by `luisma.code`). Prefix build cmds:
  `eval "$(/opt/homebrew/bin/brew shellenv)"; export LANG=en_US.UTF-8; export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Engine: `cd v0 && dart test && dart analyze lib bin test`
- App: `cd app && flutter analyze lib test integration_test && flutter test`
- Integration (real GPU): `cd app && flutter test integration_test -d macos`
- Full gate: `bash tool/precheck.sh`
- **Run the app:** `bash app/tool/dev-run.sh` (stable signing). **Use a WIRED/USB mic**, not the
  Jabra Bluetooth headset (its mic forces low-fi HFP mode + delivers silence → voice fails).
- No-sudo Mac: admin account is `luisma`; `~/.zprofile` has brew + `DEVELOPER_DIR` + `LANG`.

## Open / deferred (with reasons — don't reflexively pick these)

- **iOS notifications** (real, not FakeScheduler) + **iOS synced-folder storage** — follow-ups once
  dogfooding on-device starts.
- **Leak certainty:** a proper **Xcode Instruments (Allocations)** profile of the render path is the
  honest next step if we want to fully rule out a slow native leak (footprint sampling was
  insufficient — that's what caused the incident).
- **Deferred, cloud/model-gated:** authoring preview→refine→activate loop (G-29), safety Layer-2/3
  model gate (G-30) — can't validate hermetically without a live BYOK key + model.
- **Low value / skipped (documented):** golden tests (flaky on the additive swarm; numeric
  invariants substitute), frame-time ratchet, an in-app "Share diagnostics" button (Files-app access
  already covers log retrieval).

## Suggested first move for the new session

Ask Luis whether the Apple Developer account is approved. If yes → walk the Xcode Team/signing step
and `flutter run -d` to the iPhone. If not yet → offer the free Wi-Fi/tethered on-device path today,
or pick up any other item he wants. Default to SHORT turns unless he says otherwise.
