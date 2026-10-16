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
The independent-attributes update keeps this exact file and app identity;
imported people do not need to be imported again. `JournalStore.readJournal`
is the shared old/new decoding, migration, and validation path for startup,
backup import, and recovery. New attributes decode optionally. The original
bytes are not rewritten on open. The first edit retains a protected
`.before-relationship-update` copy which later saves never replace; Settings
can recover it after confirmation. The frozen fictional build-1001 journal in
`PlenaraTests/Fixtures/` exercises preservation in unit and UI tests. It is
packaged into test bundles only, never the production app.
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

For remote delivery, use **TestFlight** through the existing Plenara App Store
Connect app and its enrolled internal group. `bash tool/deploy-testflight.sh`
archives optimized Release code, exports an App Store Connect IPA, validates,
uploads it, waits for Apple processing, assigns the exact build to the existing
internal group, and confirms `IN_BETA_TESTING`. This is the standing delivery
default after validated app changes; no repeat permission is needed. It uses the
existing API key outside the repository. Run precheck and commit/push first.
For readback or resuming an already uploaded build:

```sh
python3 tool/testflight.py status 1000
python3 tool/testflight.py release 1000
```

The helper reads back bundle identity, the internal group, owner enrollment,
exact build number, version 1.0.0 for iOS, processing status, group assignment,
and beta availability. Do not equate upload completion with availability.
The release waiter has a 20-minute ceiling and reports a processing blocker
instead of claiming success. It refreshes API authentication on every read.
Change the version check deliberately when releasing another marketing version.
A future upload needs a new build number; do not upload the same build twice.
Build/export/upload logs stay under `.tmp/testflight/`; the IPA is ignored
under `.build/testflight/export/`. TestFlight installs remotely through Apple's
app; no physical-phone testing or automatic launch is performed.

`tool/deploy-phone.sh` is the direct-install alternative when the phone is
reachable. It builds an optimized signed iPhone artifact using the
existing team, app identity, and configured App Store Connect key. Credentials
remain outside the repo. It installs to Luis’s configured iPhone without
launching. No tests or probes are run on the phone. The configured device is
Aluminum Monster, CoreDevice ID `D79FABC7-9CA8-5170-AF1F-58FB541002B6`.

The bundle identifier remains `com.plenara.plenaraApp`; installation replaces
the old executable while the new journal uses a fresh storage path. There is
no automatic import of archived planner data. The archive is never active
source or guidance.
