# Compact Home implementation

Luis approved implementation on November 25, 2026: “Looks great let’s imolement”.
This follows his request to use the write-like-luis skill for UI strings, reduce
space per person, and switch relationship types and combined filters when
choosing whom to follow up with. The starting report concerned Aaron appearing
before close friends and family despite no recorded interaction history.

## Result

Home uses one compact list with All, Family and Friends tabs. Closeness,
follow-up status, all five relationship dimensions, name search and sorting can
be combined. Choices survive reopening. A row expands for Reach out, Log contact,
Later, contact-date provenance and the person's profile. Large accessibility
text uses stacked controls and a readable filter footer.

Missing history stays unknown. Starting invitations use chosen closeness;
family with unknown closeness precedes other unclassified relationships.
Due reminders retain the established due ordering. Optional invitations share
recent-contact, unanswered-outreach, pause and snooze suppression. A shared
event cools down all attendees. The full current behavior is owned by the
[product design](../../design/relationship-app.md#home).

Reminder normalization is shared by person saves, including the profile editor.
Saving Reminders off clears its disabled clock. Explicitly enabling reminders
without known contact starts today, without inventing an interaction. Unrelated
profile edits do not start a missing clock. Failed atomic writes publish neither
person edits nor the normalized clock.

UI copy names actions and recorded states directly. Saved user notes and
classification values remain distinct from app-authored explanations. Preferences
use stable encoded keys independent of their displayed labels. No journal schema,
identity or storage path changes. UserDefaults access is declared with per-app
reason CA92.1 in the privacy manifest, following [Apple's required-reason
API guidance](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

## Verification

The original cold-start test failed against the previous implementation before
the change. Unit checks and focused native UI checks passed during development.
Controlled faults proved checks reject incorrect closeness priority, ignored
combined filters, missing shared-event cooldown, a stale disabled reminder clock,
oversized rows and ignored filter application. Faults were restored after each
run. The corresponding calibration JSON and red logs are in this directory.
The first precheck stopped at the simulator-storage guard. After Luis authorized
the scoped exception, the complete Release precheck passed: 926 archived files,
six prototype journeys, six TestFlight-helper tests, two calibration-helper tests,
73 native tests and one Contacts-denied repeat. The separate small-screen gate
passed 46 tests (45 unit tests and one UI journey). See [the precheck output](precheck.log).

Native UI verification found and fixed an accessibility wrapper that hid button
identifiers, an undersized relationship hit area, a filter footer that intercepted
taps, lazy-query handling in the shared test helper and truncated Cancel text at
accessibility sizes. One earlier runner was edited while Bash was still executing
it, causing a later parse error after tests passed. That gate was treated as
incomplete; the unchanged runner subsequently completed focused checks. Neither
that incomplete gate nor negative-control results establish a final green release.

The unsigned physical-target Release compilation succeeded. It was compile-only;
no physical device was launched or used for testing. The final simulator app and both test bundles also compiled in Release after
the saved-key polish, without booting a simulator. Compilation does not establish
test execution.

## Development storage

Builds, caches and temporary capture output now resolve through persistent links
to `/Volumes/MacExt/DeveloperData/projects/plenara`. Entry-point guards verify the
mounted volume's UUID and fail instead of writing to a substitute internal path.

Offline copies of both dedicated simulators were verified before trying external
storage. CoreSimulatorService could not write there: macOS returned Cocoa 513 /
POSIX 1, including through its supported external device-set API. Original
internal simulator data was restored. No app data was discarded. Details and
hash-verification counts are in [the storage record](simulator-storage.json).
Luis explicitly authorized temporary internal simulator data for this release
on November 25: “Yes, use internal simulator data for this release”. Builds and
caches remain on MacExt. The exception is scoped to this release. The default runner refuses internal simulator
storage. This is an OS filesystem access boundary, not a session sandbox denial.

## Learning record

The active-runner mistake and obstructing-footer diagnosis were generalized into
the authoritative global `ship-what-you-ran` and `tests-that-can-fail` skills.
Both were validated, mirrored to the authorized recovery repository, committed
and pushed in backup commit `e7532a7`. Project facts remain here rather than in
global guidance.

## Delivery status

Build 1009 is prepared in project configuration. Release validation, main integration and TestFlight delivery are complete.
Build 1009 is available to the enrolled internal tester, confirmed by the
[release receipt](testflight.json).

## Deployment request and storage exception

Luis requested “Deploy to my phonr”. He then explicitly approved internal
simulator data for this release. The signed build-1009 candidate archived and
exported successfully and passed Apple validation. Package inspection confirms
iPhone-only identity, the UserDefaults reason declaration and absence of test
bundles, fixtures and simulator-only demo flags. Apple's validator issued only
a future SDK-deadline warning, not a current compatibility error.

The first small-screen run exposed two test setup errors: an inherited helper
seeded a known baseline in the unknown-history test, and a UI test tried to tap
an offscreen lazy row. The fixture now explicitly clears that baseline and the
UI test uses the actual search entry before choosing Zoe. One intermediate
compile failed because the wrong search-helper name was used; it was corrected
to the existing helper before rerunning. No result from either failed run is
counted as a green gate. The corrected unit and small-screen UI run passed.

## Final rendered-label correction

The first full Release gate passed 73 tests and the Contacts-denied repeat passed
one. Screenshot inspection then found that the expanded Reach out label had the
same purple color as its button background. The inherited ComfortableButtonStyle
overrode the outer white foreground. The dense action now opts into the plain
style, matching the existing filled ActionButton pattern. The prior green result
is retained as an intermediate gate, not the final source receipt. The original
render is retained in reach-out-red.png for comparison.

The final change after the full gate is exactly the dense Reach out button's
plain style. The compact Home regression and real outreach integration passed
again (two native tests). A pixel check on the actual button-label area rejected
the broken capture (zero near-white text pixels) and accepted the corrected
render (2,254). Both renders are retained. A redundant broad rerun was started
then stopped, following ship-what-you-ran's instruction to rerun the narrow path
and closest integration boundary after an isolated late fix. Its interrupted
output is retained separately and is not counted as a pass. Final source hashes
and the base-plus-supplement validation mapping are retained in this directory.

Normal, dark, expanded, combined-filter, small-screen and accessibility captures
were visually inspected. Memory samples are bounded simulator observations, not
proof of no leak or physical-device resource behavior. Final scratch attachment
exports were removed after retaining selected screenshots. Failed external
simulator copies were removed only after the restored internal originals had
been exercised. The prior usable signed build is retained until its replacement
passes packaging validation. See cleanup.json.

The rendered-label lesson is now in the authoritative global ship-what-you-ran
skill: inspect focused captures and resolved text color before the broad gate.
It was validated and mirrored, committed and pushed in backup commit b4dad2b.

## Release packaging and readback

Implementation commit 400b2f4 was pushed to main and verified on the remote
before tool/deploy-testflight.sh ran. The final build-1009 package passed Apple
validation and upload. The final package receipt includes its IPA SHA-256 and
source commit. A progress update initially misread a stale build-1008 upload
log as current; the package identity check rejected that inference immediately.
The mistake was corrected in chat before any availability claim. The current
validation/upload outputs were then checked with fresh timestamps and build
identity. Availability remains a separate App Store Connect readback.

The final readback confirms build 1009 is VALID, unexpired, assigned to Internal,
and IN_BETA_TESTING, with owner enrollment true and auto-notification enabled.
Delivery uses the authorized remote TestFlight path. Installation and Automatic
Updates on the iPhone are controlled by TestFlight on that device; no physical
launch, test or installation readback is claimed.

The deployment runner now invalidates its four previous step logs before a new
run. This implements the existing global rule about stale success receipts
rather than adding another rule. A seeded stale-output check proved all four
logs disappear while the prior usable package remains; shell syntax and all six
TestFlight-helper tests passed. The active runner was allowed to exit before
editing its source. This tooling-only follow-up does not change the uploaded app.

Selected native screenshots, both rendered-label controls, validation logs, source
hashes and release receipts are committed evidence. Both dedicated simulators
are shut down; no owned test host or memory watcher remains. Only the latest
usable signed TestFlight package is retained.
