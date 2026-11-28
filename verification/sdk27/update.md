# Xcode 27.2 rebuild

Luis installed the new SDK and requested: “I installed new sdk pls rebuild the
app with latest libraries”. After an initial license/setup blocker he asked:
“Try again try again”. Xcode 27.2 (27B52) now passes first-launch checks and
provides the iOS 27.2 SDK. Plenara uses Apple system frameworks without
third-party package dependencies. The rebuild keeps the product design,
iOS 18 minimum target, journal identity and storage format unchanged.

Build 1010 replaces build 1009 for this SDK rebuild. The standing delivery path
is a Release build, simulator verification, precheck, commit/push to main, then
TestFlight upload and confirmed internal availability. No physical-phone tests
or automatic launch are authorized or performed.

## Verification status

Release validation passed: the complete precheck finished with 73 native tests
and the separate Contacts-denied journey, all green. Build 1010 uses SDK 27.2
and keeps iOS 18 as its minimum. Signed TestFlight delivery is in progress;
cloud availability is not yet claimed.

## Simulator storage

The prior internal-storage exception was scoped to build 1009. This rebuild
retries external storage under the new Xcode instead of assuming that exception
continues. A fresh device in the supported external device set booted on iOS
27.2, demonstrating that the previous CoreSimulator MacExt write denial is no
longer present. Its boot log is retained. The dedicated existing compatibility
simulator was moved offline with an independently verified file copy;
the internal original was retained until its external consumer was verified.

The offline copy verified 23,406 files (3,948,089,114 bytes). Four protected
Location Services score-cache files, totaling 180 bytes, could not be read and
were excluded explicitly; no app data was excluded. The dedicated simulator
then booted successfully through its normal device ID with data resolved to
MacExt. Its internal original was retained for the app-consumer check described below.
The fresh external device became the dedicated iOS 27.2 verification target.

Before the bounded Release gate, an unrelated project's Xcode simulator test
was already active on the shared Mac. Plenara waits for observed process exit
and rechecks the workload inventory before starting, before each guarded run. Other projects can start after that inventory check;
observed overlaps are disclosed and memory figures are not treated as isolated
performance measurements. The waiting simulator was
shut down after the storage check to release its background resources.

The new SDK Release app and both test bundles compiled successfully. The built
simulator package identifies SDK iphonesimulator27.2 and build 1010. App source
required no SDK compatibility changes. The compiler's only warning skips
App Intents metadata extraction because the app has no AppIntents dependency.
This compilation receipt does not establish a passing native test run.

A working command from another local project exposed Xcode's external-device-set
option. Before adopting it, `xcodebuild -showdestinations` with
`DVTSimulatorSetLocation` positively listed Plenara's external iOS 27.2 target.
The runner, memory guard and guard-calibration tool now share one simulator
configuration, including the device set for every install, launch and stop.
The release suite will use iOS 27.2 itself, not only compile its SDK. The
internal-data control still fails before boot, demonstrating that the external
storage guard has not been bypassed.

## SDK-specific test-helper repair

The first broad native run passed the unit suite and several Home journeys,
then failed in the accessibility test helper while the filter sheet dismissed.
The footer existed at one query but disappeared before a later live frame
query. The rendered sheet and subsequent Home state were valid; this was a
non-atomic optional-element lookup in the test adapter, not an app filter error.
The broad run was stopped after that failure. Xcode returned exit 75 during
interruption, and that incomplete gate is retained as red evidence, not a pass.
The old helper text, failure log, issue description, accessibility hierarchy and
rendered attachments are retained here.

The helper now reads optional footer, keyboard, tab-bar and target geometry from
fallible snapshots. A separate existence check is not treated as a lock. The
unchanged accessibility journey passed after the footer fix, and the search /
cancel / reset journey and accessibility journey both passed after the complete
helper repair. Other Xcode workloads started after that narrow run's initial
clear check; those results establish functional behavior, not isolated memory
figures. The guard calibration waits for clear workload inventory again.

The general lesson was added to the existing authoritative global
`tests-that-can-fail/SKILL.md`, validated, mirrored and pushed to its authorized
recovery repository in commit 6b91685. No product rule or app behavior changed
to accommodate the test.


## Native Files test adaptation

The next broad run again passed all six compact Home journeys and reached the
backup-export journey, which expected the system navigation button to be named
Save. The iOS 27.2 hierarchy instead identifies the action as Copy, with the
stable `DOCPicker.actionButton` identifier. That stopped broad run remains red.
The picker no longer exposes an editable filename field. The test now finds
the saved backup by its timestamp within the actual export interval, preventing
an older backup from satisfying the restore check.

The first focused retry found and tapped Copy, then failed its old five-second
dismissal deadline while Files still showed an In progress activity indicator.
The UI hierarchy and run log are retained. The test now waits for the picker’s
actual dismissal, with a bounded 30-second deadline. The focused journey then
passed: the system export completed, the newly saved file was available through
Files, and restore reported five people and four moments. App export and journal
code were unchanged. A full Release precheck is running against these final
test adaptations.

## Calibrated safeguards

The simulator memory guard was tested against the real Release app: a one-KiB
ceiling stopped it, while the standard 512-MiB ceiling allowed it to continue.
Old trace files were then seeded with impossible sentinel readings; the repaired
calibration invalidated them and recorded fresh real-process samples. These
controls prove guard routing and stale-receipt protection, not absence of leaks
or a physical iPhone resource ceiling.

The TestFlight helper now checks both the exported IPA’s SDK metadata and the
executable’s actual build load commands before validation or upload. It rejected
the prior SDK 26.5 package and a copy with only its plist restamped to SDK 27.2.
It accepted a temporary unsigned wrapper of the newly compiled SDK 27.2 phone
product for SDK compliance only. Apple validation of the final signed export
remains a separate gate. Temporary control packages were removed; their receipt
is retained. The final distribution package will have its own SHA-256 receipt.


## Large-text organizer touch targeting

The next full run passed all 45 unit tests, all six Home journeys, backup restore,
previous-version journal upgrade/edit/reopen, explicit Contacts selection,
notifications and bulk organization. It then failed the large-text organizer
journey: the test scrolled Quick sort to y=50, behind a navigation/search bar
whose measured lower edge was y=266. XCTest reported the segment hittable, but
tapping there left Together selected. The expected Quick sort toggle therefore
never appeared. This was a test touch-target error; the hierarchy, screenshot
and interrupted broad-run log are retained without treating the incomplete run
as a pass.

The organizer test now measures the actual navigation/search bar, scrolls the
segment fully below it, and waits for the destination mode’s toggle before
interacting. Its next focused dark/large-text journey passed. All three focused
organizer journeys then passed. The ten remaining quick-log, ranked Home and
shared-workflow journeys also passed before the final broad gate. The existing
global testing skill already requires viewport exclusions from real control
frames; this change applies that rule to the old test’s zero-inset assumption.
No app layout or product behavior was altered for this repair.


## Cold Contacts-service readiness

A later broad run reached 58 passing tests but failed the initial seeded-contact
lookup. The failure hierarchy showed an empty remote picker host rather than a
Contacts screen with a missing row. OS logs put ContactsViewService’s initial
layout work at 17:00:25, with further initialization at 17:00:28; the test began
its eight-second row deadline at 17:00:19 and captured failure at 17:00:27.
The existing fixture had already worked in earlier runs. This is a separate
system-service opening event that the test previously conflated with row lookup.
The interrupted run and its evidence remain red. During diagnosis the existing
Contacts grant was reapplied; this does not establish the earlier authorization
state and is not used as evidence of it.

The test now waits for the native Contacts navigation bar before requiring the
seeded row, on every picker opening. It keeps all selection, cancellation,
repeat-import, no-contact-history and no-reminder assertions. After a simulator
shutdown/boot, the full import journey passed. The same journey then passed with
broad Contacts access denied. There is no app permission or picker implementation
change. The final precheck will still rerun the complete suite and denied mode.


## Older runtime and storage cleanup

The rebuilt SDK 27.2 app also passed the frozen previous-version journal’s
upgrade/edit/reopen journey on the retained iOS 26.5 compatibility simulator,
using its migrated MacExt data. The simulator was shut down after that check.
Together with the earlier byte verification, this established the consuming
app and CoreSimulator path before removing the redundant internal original.
Cleanup completed without errors; `simulator-storage.json` records the result.
No internal simulator-storage exception was needed for this release.


## Lazy restore-status assertion

The next complete attempt passed 53 tests, then failed after the actual Files
export, file selection and restore confirmation. The status existence query
succeeded, but a separate live label query failed as the lazy Settings Form
recycled its offscreen row while recovery controls changed. The hierarchy and
interrupted run remain red. Completion is now asserted by a single query that
matches both the status identifier and expected result text, scrolling before
waiting for that match. The complete export/restore journey then passed without
changing app code or weakening the required five-person/four-moment result.

Repeatedly interrupting the broad suite at its first independent failure was a
workflow error: it replayed an expensive passing prefix and delayed discovery of
later test repairs. The existing authoritative testing skill now directs broad
migration suites to collect independent failures, repair them together, verify
focused cases, and then run the full gate. Unsafe growth or invalid shared state
still requires stopping. The skill was validated, mirrored and pushed in global
backup commit e5308a6. The current full precheck is allowed to finish collecting
its independent cases; no active runner’s source will be edited.


## Final verification and visual review

The final precheck passed all 73 tests, with no skips or expected failures, plus
the separate Contacts-denied journey. The final result paths, memory sample
counts and peaks, guard limit and source/tool manifest hashes are recorded in
`validation.json`. Functional behavior was verified on iOS 27.2; the additional
frozen-journal consumer check passed on iOS 26.5. Simulator checks do not prove
physical iPhone resource limits or absence of leaks. Other projects started
Xcode jobs after some initial clear checks; no isolated performance claim is made.

The final native Home, dark Home, filters and large-text filters were reviewed.
An apparent clipped footer in the tool preview was initially misdiagnosed as an
app defect. A targeted measurement disproved it: the action ends at y=824 on a
874-point screen, and all 150 bottom pixel rows in the original full-device
image are background. The original image opened alone shows the complete
button. No product layout change was made. The temporary diagnostic assertion
was removed, and every app/test/fixture/project file was SHA-256 checked against
the exact source manifest of the passing 73+1 gate. Its geometry and image
receipts are retained rather than presenting this false start as a product fix.

The full-result console-log command reported no console stream; selected test
activities and the immutable result bundles are the execution evidence. The
verification simulators were shut down after use. Scratch attachment exports
are removed after retaining selected captures and failure evidence; the result
bundles and authored records remain.

Current native previews: [Home](home.png), [dark Home](dark-home.png),
[Family](family.png), [filters](filters.png), [filtered list](filtered.png),
[person actions](actions.png), [large filters](large-filters.png),
[large contact log](large-log.png), [ranked list](ranked-complete.png).


The complete gate also retained one SwiftUI runtime warning during the quick-log
journey: “Invalid frame dimension (negative or non-finite).” Xcode attributes it
to the app root at line zero, without a usable call site. That journey completed
all save/reopen assertions, and its focused run and rendered captures showed no
corresponding failed behavior. The warning is retained in the result summary
and `quick-log-runtime-warning.json`; this record does not claim a warning-free
runtime or an identified cause for that framework diagnostic.
