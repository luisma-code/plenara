# Plenara — Windows → macOS transition

_Written 2026-07-12 on the Windows machine, right before moving to Mac. Read this **plus**
`HANDOFF.md` and `CLAUDE.md`, then continue. This doc is the Mac-specific companion; `HANDOFF.md`
is the full session history (Windows-oriented) and `CLAUDE.md` is the working-mode + principles. For
the multi-OS **release** path (packaging, signing, the ranked must-do list), see `RELEASING.md`._

---

## 0. First message to the new (Mac) session

> Read `TRANSITION.md`, `HANDOFF.md`, and `CLAUDE.md`, then continue.

The Claude auto-memory does **not** transfer across machines/users (it lives under
`~/.claude/…`). Everything you need is in the repo docs.

---

## 1. Where we are (stable checkpoint)

- **HEAD when this was written:** `cae51ee` (plus the commit that adds this file + the macOS
  prep below). `origin` = `github.com/luisma-code/plenara.git`, all pushed.
- **Tests green:** v0 engine **1654**, Flutter app **49**, `analyze` clean on both.
- **The engine (`v0/`) is complete and heavily tested.** The **Flutter app (`app/`)** is the
  front-end: voice-first presence UI ("Plena"), talk-back TTS, on-device STT, reminders.

**What the last few sessions shipped (newest first):**
- **Gesture dev-loop + glyph fixes.** A headless harness renders the *real* `plena.dart` +
  `glyphs.dart`, freezes each gesture at 8 points, and montages contact sheets so gestures can be
  judged by eye. Used it to redesign 9 glyphs that didn't read as their symbol (wave, candle,
  leaf, quill, laurel, clasp, question, double-check, open-book). Run:
  `cd app && tool/snap_gestures.sh [all|<glyph>|a,b,c]`. Snaps are temp (`.gitignored`).
- **Dev harness in the app.** `⋯` menu → **"Dev harness"** — force presence state / difficulty,
  fire any glyph, flip display modes, speak a test line, without driving the engine. (`main.dart`,
  `_forceState`/`_forceDifficulty`.)
- **Fable review round.** Fixed all engine (router/session/skills/corpus) + app (Plena visual +
  voice) findings, then synced specs 02/03/04/07/12/14/15 to the shipped implementation.
- **Two-way voice + presence-primary UI** (earlier): see `HANDOFF.md`'s top block.

**A faithful browser port of the swarm** (7 tuning knobs + all glyphs) was published as a
claude.ai Artifact for quick previewing — it's a sketchpad, not the source of truth; the real
Plena is `app/lib/plena.dart`.

---

## 2. What is Windows-specific and won't carry (with the macOS equivalent)

| Windows thing | On macOS |
|---|---|
| **Toolchain in `.tools/`** (`dart-sdk`, `flutter`) — **gitignored**, Windows binaries | Install Flutter for macOS (`flutter.dev` or `brew install --cask flutter`) + **Xcode** (for the macOS runner + codesign). Use `flutter`/`dart` from `PATH`. |
| **`app/windows/`** runner only | **`app/macos/` is now pre-generated + customized** (done this session, on Windows): runner, **unsandboxed** entitlements (mic `device.audio-input` + `network.client`), Info.plist usage strings, app name **Plenara**, bundle id `com.plenara.app`. On Mac it's just `flutter pub get` → pods install on first `flutter build macos`. |
| **TTS = WinRT/SAPI** (the "crummy Windows voice"; needed `nuget.exe`) | `flutter_tts` uses **AVSpeechSynthesizer** automatically — the good Apple voice Luis wanted. No nuget. |
| **STT = sherpa_onnx Whisper, else SAPI** | sherpa_onnx works on macOS (onnxruntime); `speech_to_text` falls back to Apple Speech. Model still expected at `~/.plenara/models/en-whisper` (or it no-ops). |
| **`WindowsToastScheduler`** (real OS toasts, needs ATL) | **`MacToastScheduler` is now written + wired** (`app/lib/macos_scheduler.dart` — `flutter_local_notifications` → UNUserNotificationCenter, analyze-clean). `_scheduler` picks Windows / macOS / else-`FakeScheduler` by `Platform`. It requests notification permission on first arm. |
| **Hardcoded seed path** `Z:\code\plenara\v0\data` | Now `PLENARA_SEED_DIR`-overridable. Set `export PLENARA_SEED_DIR="$HOME/code/plenara/v0/data"` (or wherever you clone), **or** do the real fix: bundle `v0/data` as Flutter assets. |
| **Root scripts** `build.cmd` / `run.cmd` / `dogfood.cmd` / `prep-machine.ps1` | Windows-only. macOS: `flutter run -d macos` / `flutter build macos`. A Mac prep is just Flutter + Xcode. |
| **`tool/snap_gestures.sh`** references `../.tools/flutter/bin/flutter.bat` | It already **falls back to `flutter` on `PATH`** if that's absent — works on Mac as-is. |
| **`pat.txt`** (GitHub token + BYOK key) at `z:/code/pat.txt` — **not in the repo** | Provide your own on Mac (see §4). |

Nothing else is OS-bound: `v0/` is pure Dart, and `plena.dart`/`glyphs.dart` are pure Flutter.

---

## 3. macOS setup — ordered checklist

1. **Clone** (origin is current): `git clone https://github.com/luisma-code/plenara.git`
2. **Flutter + Xcode.** Install Flutter (macOS), then `flutter doctor` — accept Xcode license,
   install CocoaPods (`sudo gem install cocoapods` or via brew). Confirm `flutter doctor` is green
   for macOS desktop.
3. **Deps:** `cd v0 && dart pub get` and `cd ../app && flutter pub get`.
4. **macOS runner — ALREADY DONE** (committed this session): `app/macos/` exists with entitlements
   + Info.plist + app name/bundle id set. You do **not** need `flutter create`. On first
   `flutter build macos`, CocoaPods installs the plugin pods (flutter_local_notifications,
   sherpa_onnx, record) — that step needs the Mac + Xcode.
5. **Seed data (the one runtime step):** `export PLENARA_SEED_DIR="$(pwd)/../v0/data"` before
   `flutter run` — first-run seeding copies the built-in capability defs from there. (Proper fix,
   still TODO: bundle `v0/data` as a Flutter asset so this env var isn't needed — see §6.)
6. **BYOK key + config:** `~/.plenara/config.json` with `"apiKey": "sk-ant-…"` and optionally a
   `"dataDir"`. (`~/.plenara/` is cross-platform — same as Windows; the build is unsandboxed so
   this is the real home dir.) Offline features work with no key; cloud needs one.
7. **(Optional) STT model:** put the Whisper model at `~/.plenara/models/en-whisper` for
   sherpa_onnx; without it, STT no-ops to Apple Speech / typing.

---

## 4. Credentials

- **GitHub:** authenticate however you prefer on Mac (`gh auth login`, or a PAT in the macOS
  keychain via Git Credential Manager). The repo remote is public; only pushing needs auth.
- **BYOK Anthropic key:** provide via `ANTHROPIC_API_KEY` env, `planning/specs/05a-rig/.env`
  (for tests/the fixture recorder), or `~/.plenara/config.json` (for the app).
- **Standing security note (do not re-raise with Luis — he owns rotation):** the previously-pasted
  GitHub PAT and BYOK key are exposed/compromised and should be treated as such. **Never print or
  commit a key**; before every commit run `git grep --cached -nE "sk-ant-[A-Za-z0-9]{20}"` (must be
  0). Same rule on Mac.

---

## 5. How to run / verify on macOS

```sh
# engine
cd v0  && dart test && dart analyze lib bin test
# app
cd ../app && flutter analyze lib && flutter test          # 49 widget/unit tests
flutter run -d macos                                       # launch Plena (set PLENARA_SEED_DIR first)
# gesture dev-loop (headless render → contact sheets)
tool/snap_gestures.sh all
```

Commit trailers are required (see `CLAUDE.md`): `Co-Authored-By: Claude …` + `Claude-Session: …`.

---

## 6. Good first tasks on Mac (once it builds & runs)

- **Smoke-test the build:** `flutter pub get && flutter build macos` (installs pods), then
  `flutter run -d macos` with `PLENARA_SEED_DIR` set. Fix any pod/entitlement issues Xcode surfaces.
- **Confirm the macOS toast fires:** `MacToastScheduler` is written but **never run** (I can't on
  Windows) — set a near-future reminder and verify the notification appears; approve the permission
  prompt. Instrumented via `AppLog` (`sched(macos): …`).
- **Confirm AVSpeechSynthesizer voice** quality and pick a nicer default voice/rate in
  `speech_out.dart` — the upgrade from the Windows SAPI voice.
- **Bundle `v0/data` as Flutter assets** so `PLENARA_SEED_DIR` is no longer needed (the proper fix
  for dev-path seeding; the v0 engine is pure Dart so the extract-to-dir must live in the app layer).
- **Finish the glyph pass if desired:** `nod`, `snooze-arc`, `still-flame` were left as
  deliberately-minimal marks; the snap loop (`app/tool/snap_gestures.sh`) is ready.

---

## 7. Gotchas

- **`main.dart` still imports `windows_scheduler.dart`.** That's fine — the Windows notification
  plugin declares only the `windows` platform, so the macOS build skips its native side and the
  Dart import compiles; the scheduler is only *constructed* on Windows (`Platform.isWindows`).
- **`sourceDataDir` default is still the `Z:\` path** as a fallback — set `PLENARA_SEED_DIR` or the
  app will throw at first-run seeding with a clear "source data dir missing" error.
- **Line endings:** a `.gitattributes` now normalizes to LF in-repo (checks out native), so the
  perennial CRLF warnings stop and `.sh` scripts stay executable on Mac.
- **`.tools/` won't exist on Mac** and is gitignored — don't look for it; use `PATH` Flutter/Dart.
- **All native plugins support macOS** (verified from Windows against the resolved versions):
  `sherpa_onnx`→`sherpa_onnx_macos`, `record`→`record_macos`, `flutter_tts`→AVSpeechSynthesizer,
  `speech_to_text`→Apple Speech, `flutter_local_notifications`→`MacOSFlutterLocalNotificationsPlugin`.
  So `flutter build macos` resolves every pod — no missing-platform surprises expected.
- **Runtime paths are already cross-platform** — `config.dart`/`main.dart` resolve `$HOME` (fall back
  from `USERPROFILE`), `app_log.dart` uses `Directory.systemTemp`, `settings_view.dart` already
  branches `open` vs `xdg-open` vs `start`. No Windows-path landmines remain besides the seed dir.
