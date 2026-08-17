# Plenara Flutter app

The Flutter client for Plenara's living planner. iPhone is the primary target;
macOS and Windows are supported development/desktop targets.

The client provides Today, Plan, Library, History, settings, voice capture and
speech output, reminders, Plena's animated presence, secure BYOK credential
storage, and user-selected data-folder access. Product logic remains in the
pure-Dart package at `../v0`.

## Local verification

```sh
flutter pub get
flutter analyze lib test integration_test
flutter test
```

Use `../tool/precheck.sh` for the complete repository gate and
`../tool/external_release_gate.sh` for compiled external-artifact inspection.
Automated iPhone verification runs only in a local simulator. A physical phone
is deployment-only and must never be selected by a test or debug harness.
