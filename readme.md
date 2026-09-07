# Plenara

Plenara is a voice-first living planner and relational assistant. Relationships,
one-off Todos, and tracked Habits are its three primary workspaces; Plan, Library,
and History remain directly reachable secondary tools. Free-form capture and
visible state work together so a person can compare, sequence, revise, and revisit
plans without making voice carry persistent state alone. Plena—the warm particle
presence—moves between a full conversational form, a compact planner collaborator,
and a detail ember.

Common planning and routing run locally. Optional Anthropic features use the
user's own API key and disclose the record categories sent for each feature.
Records are readable JSON files in a user-selected folder; the execution journal
and other device state remain local. See [the privacy policy](PRIVACY.md).

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
