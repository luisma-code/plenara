# Plenara Flutter app

The Flutter client for Plenara's living planner. iPhone is the primary target;
macOS and Windows are supported development/desktop targets.

The client provides primary Relationships, Todos, and Habits workspaces; secondary
Plan, Library, and History tools; settings; voice capture and speech output;
reminders; Plena's animated presence; secure BYOK credential storage; and
user-selected data-folder access. Product logic remains in the pure-Dart package
at `../v0`.

The Relationships root is Focus-first: due connections are bounded and ranked,
global search plus circle and Local/Remote filters cover the complete address book,
and direct or bulk organization shares the engine's durable undo path. Circle and
proximity remain independent; proximity selects in-person versus call/FaceTime
guidance without changing contact-frequency goals.

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
