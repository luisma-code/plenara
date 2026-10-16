# Native Plenara

SwiftUI iPhone app, iOS 18+. Product behavior is owned by the
[approved design](../design/relationship-app.md). No packages or paid services.

## Build and verify

Xcode 26 and XcodeGen are available on this Mac. Run from the repository root:

```sh
bash tool/precheck.sh
```

The native gate builds the actual app in Release for the active simulator architecture, runs XCTest persistence and
relationship/reminder checks, then XCUITest journeys on a dedicated iPhone 16
Pro simulator. `ENABLE_TESTABILITY=YES` is used only for simulator test builds;
compiler optimization remains Release. `tool/test-native.sh` accepts ordinary
`xcodebuild` test-selection arguments and `PLENARA_SIMULATOR_ID` for another
explicit simulator. The combined precheck also repeats native import with broad Contacts access denied.
Use `PLENARA_CONTACTS_DENIED=1` with `tool/test-native.sh` for that mode.
It samples app RSS and stops it above 512 MiB; this is a
bounded safeguard, not proof of device memory behavior or absence of leaks.
It terminates the app it started. Test results and builds are under `.build/`;
local logs are under `.tmp/`.

The simulator-only launch arguments `--ui-testing --reset --demo` provide
fictional people for UI checks. `--dark` supplies an actual dark trait for
render verification, and `--dated-demo` adds a fictional birthday/follow-up. `--reset` touches only the isolated UI-test
journal. `--contact-fixture` seeds one fictional system contact only on a
simulator with pre-granted contact access. These paths are not compiled into
the physical-device binary. Production opens an empty journal.

## Data

The live file is `Application Support/RelationshipJournal/journal-v1.json`.
This distinct path does not read or migrate the previous app’s planner data.
Writes are atomic, protected until the first device unlock, and retain one
previous save. A damaged file is left untouched and editing is blocked until
recovery. Settings can restore an exported JSON backup or recover the previous
local save after confirmation. Readable exports are additional convenience;
restoration uses the complete JSON representation.

Contacts are selected through Apple’s picker without requiring broad access.
Reimport is manual, reviewed, and preserves relationship notes/history.
No Contacts writes, analytics, remote model calls, or account service exist.
Logs record operations/errors without personal content.

## Delivery

`tool/deploy-phone.sh` builds an optimized signed iPhone artifact using the
existing team, app identity, and configured App Store Connect key. Credentials
remain outside the repo. It installs to Luis’s configured iPhone without
launching. No tests or probes are run on the phone. The configured device is
Aluminum Monster, CoreDevice ID `D79FABC7-9CA8-5170-AF1F-58FB541002B6`.

The bundle identifier remains `com.plenara.plenaraApp`; installation replaces
the old executable while the new journal uses a fresh storage path. There is
no automatic import of archived planner data. The archive is never active
source or guidance.
