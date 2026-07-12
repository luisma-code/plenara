# Plenara

A voice-first, offline-first personal assistant that helps you be a better friend, partner, and
parent — it remembers the people and moments you care about and nudges you at the right time. The
interface is **Plena**: a living particle-swarm presence you talk to; text materializes only when
needed. Runs on your own machine against your own data folder, with a bring-your-own-key (BYOK)
Anthropic model for the few things that need the cloud. Everything core works offline.

## Layout

| Path | What |
|---|---|
| `v0/` | The engine — **pure Dart**, no Flutter. Router, skill interpreter, store, cloud/notification seams. 1657 hermetic tests. |
| `app/` | The Flutter desktop app (Windows + macOS): the Plena presence UI, voice in/out, reminders. |
| `planning/specs/` | The design specs (01 meta-schema … 15 presence). |
| `releases/` | Per-version retrospectives + `VERSIONS.md`. |
| `tool/` | `precheck.sh` (quality gate), `sync_seed.sh`, `snap_gestures.sh`, `ci-workflow.yml`. |

Orientation docs: **`CLAUDE.md`** (working mode + principles), **`HANDOFF.md`** (full session
history), **`TRANSITION.md`** (Windows→macOS setup), **`RELEASING.md`** (multi-OS release plan).

## Build & run

Requires Flutter (pinned in `.flutter-version` = 3.44.5) + the platform's native build tools.

```sh
# engine tests (pure Dart)
cd v0 && dart pub get && dart test

# the app
cd app && flutter pub get
flutter run -d windows      # Windows: needs Visual Studio Build Tools (Desktop C++) + Dev Mode
flutter run -d macos        # macOS: needs Xcode; see TRANSITION.md for entitlements/first-run
```

The app seeds its built-in capabilities on first run from bundled assets (no repo needed). For
development against live `v0/data`, `export PLENARA_SEED_DIR="$PWD/v0/data"` before running.

## Configuration (`~/.plenara/config.json`)

Scaffolded on first run. Set your data folder and (optionally) BYOK key:

```json
{ "dataDir": "/path/to/your/synced/Plenara", "apiKey": "sk-ant-..." }
```

Offline features (tasks, people, reminders, journaling) work with no key. Cloud routing, authoring,
and generative features need one. On-device voice input uses a Whisper model at
`~/.plenara/models/en-whisper` if present, else falls back to the OS recognizer.

## Quality gate

```sh
bash tool/precheck.sh   # analyze, tests, coverage floor, seed-asset sync, host-OS build, secret scan, conformance
```

CI runs the same on Windows + macOS — see `tool/ci-workflow.yml` (move to `.github/workflows/` to
activate; needs a `workflow`-scoped token).

## Status

Engine complete and heavily tested; Windows app is dogfood-ready; macOS is scaffolded and builds.
Distribution (signing/notarization, model download, installers) is tracked in `RELEASING.md`.
