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
local logs are under `.tmp/`. Each run replaces the owned simulator UI-test
runner installation and executes the architecture-specific `.xctestrun` manifest
with verified Release product paths. The recorded test context hashes both test
executables. A result with zero executed tests is rejected; the runner and app
are stopped at cleanup.

The simulator-only launch arguments `--ui-testing --reset --demo` provide
fictional people for UI checks. `--dark` supplies an actual dark trait for
render verification, and `--dated-demo` adds a fictional birthday/follow-up. `--reset` touches only the isolated UI-test
journal. `--contact-fixture` seeds one fictional system contact only on a
simulator with pre-granted contact access. These paths are not compiled into
the physical-device binary. Production opens an empty journal.

## Home suggestions

The [approved ranking policy](../design/relationship-app.md#stay-close) is
implemented by `Journal.rankedSuggestions`, with `suggestions` returning the
first three. `ReconnectionSection` provides the leading invitation, factual
reasons, and in-place expansion. `Journal.contextualSuggestions` keeps secondary
growth/care invitations consistent with the shared suppression gate. Neither
classification nor optional ideas turn on a contact rhythm. There is no new
journal schema or storage path. [Verification and delivery](../verification/ranking/update.md).

The notification schedule reserves one slot for the weekly invitation and selects
the nearest 47 birthday/follow-up dates together. A distant birthday cannot
displace an earlier dated note; reopening refreshes that finite horizon.

## Organizing people

People → **Organize** supports Together (search, select, then apply shared
attributes) and Quick sort (one attribute per pass, with Not set only and Skip).
Together defaults to Needs assessment only, with Any detail or a specific
missing dimension. Quick sort defaults to Not set only for its chosen dimension.
Both can show everyone again; assessment derives from saved classification
values, with no new journal fields or migration.
The [approved design](../design/relationship-app.md#people) defines selection,
No change, add/remove connection labels, and Undo semantics. Both modes use
`JournalStore.organize`; all selected edits persist in one atomic write. Undo
uses a short-lived receipt of changed fields, never a whole-person snapshot.
It refuses conflicts, preserves unrelated newer edits, and is cleared by a
successful backup restore. No contact import identity or journal schema changes.

## Quick logging

Home’s **Log a moment** opens a searchable people list. A person’s page and
Moments use the same editor. Called, Texted, and Met select the channel directly;
Another way keeps video calls, voice notes, and email available. Today and
Connected are the defaults. Notes are optional and editable with the standard
keyboard, including system dictation when enabled on the iPhone. Plenara does
not record audio, request speech access, or call an AI service. Simulator checks
verify text entry and persistence; they do not prove microphone dictation on a
physical device. The Connected / Reached out control preserves the distinction
between a catch-up and unanswered outreach.

## Relationship follow-through and shared events

The [approved product behavior](../design/relationship-app.md#following-through-and-social-events)
owns Home outreach, optional rhythm setup, next-time memories, and shared social events.
`ReachOutButton` uses the same contact routes on Home and a person’s page.
Its selected route waits for the chooser’s dismissal before opening the external app.
A persisted draft is separate from confirmed history; background/active scene events
only offer review. Apple's [URL completion](https://developer.apple.com/documentation/swiftui/openurlaction/callasfunction(_:completion:))
indicates whether the URL can open, never whether contact occurred.

`JournalStore.save` commits one shared moment and all guest references atomically.
`participantIDs` is the common membership path for history, last connection, outreach,
ranking, validation, editing, deletion, and export. Removing a person retains other
attendees’ shared event. Rhythm setup and thread actions use the same atomic store;
Undo receipts contain only changed rhythm fields.

The simulator-only `--rhythm-demo` supplies fictional people without configured rhythms.
`--contact-demo --contact-handoff-fixture` replaces only the external URL boundary;
UI tests drive real background/foreground events, confirmation, storage, and reopening.
`--contact-unavailable-fixture` makes that boundary reject the request. None of these
paths or flags is compiled into the physical-device app. They do not send messages
or establish that an external communication was delivered.

## Data

The live file is `Application Support/RelationshipJournal/journal-v1.json`.
The independent-attributes update keeps this exact file and app identity;
imported people do not need to be imported again. `JournalStore.readJournal`
is the shared old/new decoding, migration, and validation path for startup,
backup import, and recovery. New attributes decode optionally. The original
bytes are not rewritten on open. The first edit retains a protected
`.before-relationship-update` copy which later saves never replace; Settings
can recover it after confirmation. The frozen fictional build-1001 journal and build-1007 model export in
`PlenaraTests/Fixtures/` exercise upgrade preservation in unit tests; the build-1001
fixture is also driven through the native UI. Fixtures are packaged into test
bundles only, never the production app.
Additive optional workflow fields preserve old single-person moments. The first successful
edit of a pre-workflow file retains `.before-workflow-update` bytes, independently of
the earlier relationship recovery file. Settings can recover either after confirmation.
The journal schema number, bundle identity, and file path remain unchanged.

This distinct path does not read or migrate the previous app’s planner data.
Writes are atomic, protected until the first device unlock, and retain one
previous save. A damaged file is left untouched and editing is blocked until
recovery. Settings can restore an exported JSON backup or recover the previous
local save after confirmation. Readable exports are additional convenience;
restoration uses the complete JSON representation. Startup and restore use the
same structural validation, with no restore-only byte limit that could reject
a backup exported by this app. Large journals are decoded in memory.

Contacts are selected through Apple’s picker without requiring broad access.
Reimport is manual, reviewed, and preserves relationship notes/history.
No Contacts writes, analytics, remote model calls, or account service exist.
When deliberately separate people share a selected contact ID, reimport requires
an explicit link even if the contact’s name and communication details changed.
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
