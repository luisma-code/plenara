# Dogfooding Plenara

This is the current operator guide for ordinary internal use. Historical Windows and Mac bring-up
notes live in `HANDOFF.md`, `SESSION-HANDOFF.md`, and `TRANSITION.md`; they are evidence, not setup
authority.

## Start the app

Use a development build on the host, or an explicitly deployed internal build on the physical
iPhone. Automated verification, debug probes, render checks, and integration tests use a local
iPhone simulator only; the physical phone is deployment-only.

```sh
cd app
flutter run -d macos
```

Windows remains supported with `flutter run -d windows`. Run the complete repository gate before a
commit or deployment:

```sh
bash tool/precheck.sh
```

## Configure data and Claude

- Choose **Settings → Data location** to keep records device-local or move them to a user-selected
  iCloud Drive, OneDrive, Google Drive, or other backed-up folder.
- Enter the Anthropic API key in Settings. The Flutter app stores it through the platform secure
  credential store; do not put it in `config.json`.
- Development-only command-line tools may use `ANTHROPIC_API_KEY`. Internal/external app builds
  ignore that environment variable and use only the secure store.
- No key is required for Today, Plan, Library, History, deterministic skills, local retrieval,
  storage, sync, or voice. A key enables residual routing, generative features, and authoring.

The production retrieval index is in-process and offline. The localhost HTTP embedding adapter is
only a development experiment; ordinary dogfood never needs a companion server.

## What to exercise

- **Capture and plan:** add tasks, schedule them, select several in Plan, move/resize/defer them,
  complete with the explicit circle, and use targeted undo.
- **Inspect and revise:** tap a Today task body to open its detail editor; use Library for people,
  goals, routines, trackers, journal, projects/areas, learned phrases, automations, and the complete
  data browser.
- **Relationships:** remember facts, log interactions, link commitments to people, and respond to
  relationship-date suggestions with Keep, Tomorrow, or Dismiss.
- **Voice:** tap to start, tap again to stop and send, or use ×/mute to discard. Interim text may
  appear while listening, but dispatch happens once at finalization.
- **Cloud:** request gift ideas, reconnect coaching, a briefing, weekly reflection, pattern insight,
  or a message draft. Settings lists the record classes each implemented feature may send.
- **Capabilities and routines:** ask to start tracking something new or create a movement routine;
  inspect the persisted preview before activating a custom capability.

## Diagnostics and measurements

Development/internal builds intentionally retain content-bearing local diagnostics during this
single-user stabilization phase. Settings previews the exact raw files and size before invoking the
share sheet. Nothing uploads automatically. External builds capture no raw content and expose no
raw export; secrets and raw audio are forbidden in every channel. Spec 11 is the sole policy
authority.

The turn log is device-local at `<deviceDir>/turnlog.jsonl`, not in the synced records folder. Run:

```sh
cd v0
dart run bin/turnlog_report.dart
dart run bin/turnlog_report.dart --errors
dart run bin/turnlog_report.dart --trace 25
```

The useful ordinary-use measures are clarification/correction rate, local routing source mix,
planner glance and revision effort, suggestion decisions, and relationship follow-through.
Impressions, screen time, and animation do not count as engagement.

## Current limitations

- Physical iOS cannot use Dart's recursive directory watcher. It reconciles the selected provider
  folder at cold open; provider-side changes made while Plenara stays open appear after relaunch.
- iOS currently has in-app reminder nudges but no native notification backend.
- At-rest encryption is deferred. Synced records, including journal entries, are readable JSON in
  the selected provider folder. Execution history and diagnostics are device-local but also
  plaintext under the current pass-through crypto posture.
- Five-day engagement, planner-speed, and slow memory-leak claims require ordinary use or an
  explicit long soak; short automated runs do not establish them.
