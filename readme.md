# Plenara

Plenara helps Luis make space for relationships, follow through on commitments, and build routines that fit his life. Today brings those three goals together; People, Tasks, and Routines provide direct access. Labeled Talk to Plena and Message Plena controls follow roots and detail pages into one resumable conversation.

The optional GPT guide reads relevant planner context and proposes editable, undoable updates. It uses a separate secure OpenAI API key, explicit context consent and a persisted monthly spending limit. Local commands and direct touch actions remain available offline. No recorded relationship update means unknown. Practices support a reason, cue, normal/minimum versions, flexible opportunities, and deliberate skips.

User-selected Calendar/Reminders evidence, pasted text and Shortcuts captures reduce bookkeeping without automatic message surveillance. Calendar entries do not prove attendance. Notifications use private, silent copy and open the relevant conversation. Planner files remain readable JSON in the chosen folder; device history stays local. See [the privacy policy](PRIVACY.md).

## Repository

| Path | Purpose |
|---|---|
| `v0/` | Pure-Dart engine: routing, planning, execution, storage, sync, migrations, and cloud seams. |
| `app/` | Flutter client for iPhone, macOS, and Windows. |
| `planning/specs/` | Product and architecture specifications, including the living-planner Spec 17. |
| `reviews/` | Spec/code, art/animation, and planner UX reviews. |
| `releases/` | Version history and App Store metadata. |
| `tool/` | Hermetic precheck, seed synchronization, release inspection, and deployment utilities. |

## Build and verify

Flutter is pinned by `.flutter-version`; native platform toolchains are also
required.

```sh
cd v0 && dart pub get && dart test
cd ../app && flutter pub get && flutter test
cd .. && bash tool/precheck.sh
```

The external promotion gate builds and inspects macOS and unsigned iOS AOT
artifacts without installing or launching anything on a physical phone:

```sh
bash tool/external_release_gate.sh
```

All automated phone, layout, render, motion, and integration verification uses
a local iPhone simulator. A physical iPhone is deployment-only. Completed,
simulator-verified, committed, and pushed phone builds install under the owner's
standing authorization and are never launched automatically.

## Configuration

The app creates its config and data root on first launch. Anthropic credentials
are entered in Settings and stored through the operating system secure credential
store; they do not belong in config JSON, source files, or build defines. Offline
mode works without a key. Settings can move records into a user-selected iCloud
Drive, OneDrive, Google Drive, or other backed-up folder.
