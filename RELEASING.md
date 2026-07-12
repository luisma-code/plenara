# Plenara — multi-OS release foundation

_Synthesis of a 3-lens Fable review (2026-07-12) of the cross-platform abstractions, plus the
ranked path to shipping on more than one OS. Companion to `TRANSITION.md` (Windows→macOS setup)._

## Verdict

**The architecture is sound.** The OS-facing seams — `NotificationScheduler`, `SpeechRecognizer`,
`SpeechOutput`, `StorageRepository`, `CloudClient` — are textbook: thin shims, a recording fake, and
all product logic in pure Dart that's CI-tested OS-independently. `v0/` is verifiably Flutter-free.
The gaps the review found were **not structural** — they were (a) things the seams didn't *express*
(now fixed) and (b) **distribution plumbing** that's genuinely missing. Nothing here blocks
*building* on macOS; the list below is what stands between "builds" and "a stranger can install it."

## Fixed in this pass (commit `134d0df` + infra)

- **macOS permission denial was a silent lie** → readiness now gated on the grant; self-heals.
- **Seam now expresses health** → `selfTest()` + `unavailableReason()` on `NotificationScheduler`;
  Session surfaces a ⚠️ on-open nudge; dropped the `is WindowsToastScheduler` downcast.
- **macOS STT ~45s stall** → `pauseFor` set off-Windows; the SAPI stale-guard is Windows-gated.
- **Unstable notification ids** → shared FNV-1a `notificationId()` in both shims.
- **Scheduler selection** → a single `_platformScheduler()` factory that logs the no-native fallback.
- **`precheck.sh`** → toolchain-agnostic (`.tools` else `PATH`) + host-OS build, so the quality gate
  survives the move to a Mac. **`.flutter-version`** pins 3.44.5. Real app **version** (0.7.0+7).

## Must-do before the first macOS *release* (ordered)

1. **[BLOCKER] Bundle `v0/data` as app assets.** First-run seeding copies built-in defs from a
   filesystem path (`PLENARA_SEED_DIR` / a `Z:\` default) and `ensureSeeded` throws if absent — so a
   distributed `.app`/`.exe` **cannot start** without the repo next to it. `v0` is pure Dart and
   can't declare Flutter assets, so: copy `v0/data/**` into `app/assets/seed/` (build step or
   checked-in), list it in pubspec, add an app-layer extractor (enumerate `AssetManifest` → write
   JSONs to a staging dir → reuse the existing dir-to-dir `ensureSeeded`). Keep `PLENARA_SEED_DIR` as
   a dev override. *Sub-item:* seed is copy-once — version the seed set + reconcile via MigrationRunner before release #2.
2. **[gate] Stand up 2-OS CI** (`windows-latest` + `macos-latest`) running the same `precheck.sh`.
   The pure-Dart engine suite runs identically on both; the per-OS delta is just `flutter build` +
   widget tests. Without it, the Windows build stops being verified the day the dev machine is a Mac.
3. **[macOS] Sign + notarize.** `Developer ID Application` cert → set `DEVELOPMENT_TEAM` in
   `Configs/AppInfo.xcconfig` → `codesign --options runtime` (sign nested onnxruntime/sherpa dylibs
   inside-out, **not** `--deep`) → `xcrun notarytool submit` → `stapler staple` → ship a DMG. Without
   this, a downloaded `.app` is Gatekeeper-blocked ("damaged"). Watch hardened-runtime vs onnxruntime
   (may need `com.apple.security.cs.allow-unsigned-executable-memory` — verify at notarization).
4. **[both] STT model on first run.** Whisper is hand-placed at `~/.plenara/models/en-whisper` today
   and silently degrades to SAPI/Apple Speech if absent. Host the int8 subset (~75 MB:
   `base.en-{encoder,decoder}.int8.onnx` + tokens + `silero_vad.onnx`) as a versioned Release asset
   with SHA256; add a Settings/onboarding "Download voice model" flow (temp → checksum → atomic
   rename). Make the fallback *visible* ("voice model: not installed").
5. **[both] Per-OS artifact matrix + real versions.** Name artifacts per tag
   (`plenara-vN-win-x64.msix`, `plenara-vN-macos-universal.dmg`) + a `SHA256SUMS`; `flutter build
   macos --release` is a universal (arm64+x86_64) binary by default, so one macOS artifact suffices.
   Record per-OS runnable status per version in `releases/VERSIONS.md`.
6. **[Windows, can trail] MSIX + signing.** The raw zip is unsigned (SmartScreen wall) and
   identity-less — which is *also* why reminder `cancel` is a native no-op (a deleted reminder's
   toast still fires). The `msix` pub package gives identity (real AUMID + cancel), declares the VC++
   dependency, and is signable. Self-signed for dogfood; a real cert for public.
7. **[polish] Real `readme.md`** (it's literally "Placeholder") with per-OS install notes
   (macOS right-click-open until notarized; Windows SmartScreen until signed; model download; BYOK).

## Deferred seam refinements (from the review; not release-blocking)

- **`armed()` doesn't hydrate from the OS on restart** (both platforms) → a cancel-while-app-closed
  (e.g. a synced delete from another device) can miss, and a stale toast fires. macOS can fix it via
  `pendingNotificationRequests()`; Windows when MSIX lands. MED.
- **macOS permission prompt timing** — requested lazily on first arm, so it can pop mid-startup or
  mid-turn (the turn's reply awaits reconcile). Better: request at onboarding / first reminder
  *creation*. MED.
- **TTS `onStart`/`onDone` on Apple engines is unverified** — the caption choreography assumes
  `awaitSpeakCompletion(true)` resolves `speak()` per-utterance on macOS; it's never run there. If
  broken, the caption vanishes ~1.6s in while AVSpeech still talks. **Top of the Mac smoke list.** MED.
- **`UrlOpener` capability has no shared seam** (the `Process.run('open'/'xdg-open'/'cmd')` triple is
  a per-widget method) — extract when a second URL/reveal-in-Finder surface appears. LOW.
- **Home-path duplicated** — `main.dart:_pickSpeech` rebuilds `~/.plenara/models` inline instead of
  `config.dart` owning it. LOW.
- **`ClaudeClient()` reads `ANTHROPIC_API_KEY` ambiently** — forces the "inject an empty-key client
  for free mode" contortion; resolve the key in `loadConfig` and pass explicitly. LOW.
- **Schedulers reach for the `AppLog.instance` global** — give them an `onLog` ctor param like the
  speech impls. LOW.
- **macOS 64-pending-notification cap** — log a warning when `desiredArmed` > ~60. LOW.

## App-Store / sandbox ledger (only if an iPhone/MAS target gets real)

The macOS build is deliberately **unsandboxed** (so `~/.plenara` is the real home, mirroring
Windows). A sandbox target later needs: `$HOME`→container migration, the plaintext `apiKey` → Keychain,
a synced `dataDir` → security-scoped bookmarks + open-panel grant, and env-var switches
(`PLENARA_SEED_DIR`, `ANTHROPIC_API_KEY`, `PLENARA_FREE`) replaced (unusable under Launch Services).

## The one contract asymmetry to NOT "fix"

Unpackaged-Windows native `cancel` is a no-op; macOS `cancel` genuinely works. So macOS is *more*
correct than shipping Windows for undo/delete — don't equalize downward. (Windows gets real cancel
with MSIX, item 6.)
