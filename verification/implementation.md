# Plenara — native implementation

October 16, 2026. The approved relationship app is implemented in SwiftUI for iPhone, iOS 18 and later.

[Open the native preview](native-preview.png)

## What works

- Stay close: a small rotating set of reconnection suggestions, with snooze, pauses, and separate treatment of reaching out versus actually connecting.
- People: selective Apple Contacts import and reviewed refresh, manual entry, search, local/distant filters, closeness, relationship details, and intentions to deepen.
- Person pages: contact actions, local time, photos, birthdays, individual contact rhythms, pinned catch-up context, categorized notes, dated follow-ups, and an editable connection history.
- Moments: log or edit a conversation or attempt to reach out. Removing a moment recomputes the connection history.
- Reminders: opt-in weekly local notification, birthday and dated-note reminders, quiet hours, and private notification text.
- Settings: complete JSON backup/restore through Files, readable export, and previous-save recovery. Atomic local saves do not publish changes after a failed disk write.
- Adaptive dark appearance, Dynamic Type, and accessible primary touch targets.

The production app starts empty. Fictional demo people and test launch paths are compiled only into simulator builds. There are no accounts, analytics, paid services, or runtime network dependencies. Notes and contact snapshots stay in the local journal; the app never writes to Contacts. Backups contain personal information and are saved wherever the user chooses in Files. Automatic cross-device sync is not included.

## Verification

`bash tool/precheck.sh` passed: archive integrity, six original design-prototype checks, **16 native Release checks** (10 unit and 6 UI), followed by another successful native Contacts import/reimport journey with broad Contacts access denied.

The UI journeys exercised first use, saved notes and moments after relaunch, the real Apple contact picker, duplicate-safe reimport, notification permission and the OS pending-request readback, actual Files export and restoration, dark pixels, maximum accessibility text, and birthday/follow-up context and completion. Verification ran only on a dedicated iPhone 16 Pro simulator running iOS 26.5. The iOS 18 minimum builds against the current SDK; older OS runtimes were not available for execution.

[Native test summary](native-test-summary.json) · [Denied Contacts summary](contacts-denied-summary.json) · [Verified source hashes](native-source-hashes.json)

Known-broken controls were rejected before trusting the checks. Records cover persistence/reminder/import behavior, dark appearance, recovery, first-use sheet dismissal, dated reminders, and the memory guard. During implementation, real regressions in picker dismissal, unstable picker identifiers under denied access, exact backup date preservation, and nested first-use dismissal were corrected and reverified.

The simulator app RSS peaked at **385.7 MiB** during XCTest. A calibrated 512 MiB guard ran throughout. This is a bounded test observation, not proof of absence of leaks or physical-device memory performance.

## Delivery

The implementation is committed to `main` and pushed. A signed optimized arm64 device build succeeded with the existing Apple development identity and passed strict code-signature verification. Version **1.0.0 (1000)** retains bundle identity `com.plenara.plenaraApp`. Simulator fixture people and launch controls are absent from the device binary.

Installation was attempted on the configured iPhone, **Aluminum Monster**. CoreDevice returned error **1011: unable to locate the requested device**. This is an unreachable-device blocker; signing succeeded. No physical-phone app was launched or tested. The install script retains the signed artifact locally for delivery when that hardware is reachable.

The signed-artifact audit also exposed XcodeGen’s target-level device-family default overriding the project setting. The app target now explicitly declares iPhone only; the Release gate and device build were repeated after that correction.

## More captures

[Dark appearance](dark-home.png) · [Large text](large-text-person.png) · [Contact refresh](repeat-import.png) · [Dated reminders](dated-reminders.png) · [Files export](backup-export.png)
