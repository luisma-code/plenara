# Plenara — quick moments

Luis chose to skip message/call-history integration and AI, and asked for an
easy way to record calls, texts, and visits with typed or dictated notes.

## The experience

**Log a moment** sits near the top of Home, above the introduction so it stays
reachable with large text. Find someone by name, then choose **Called**, **Texted**,
or **Met**. A moment defaults to today. Save immediately, or add a few words.
The same editor works from a person’s page and the Moments tab, including editing
existing entries. Video calls, voice notes, and email remain under Another way.

Notes use the standard text keyboard. Its dictation microphone can enter the
same editable text when iPhone dictation is enabled. Plenara does not add audio
recording, message access, a model account, or an AI service.

Connected and Reached out remain explicit. An unanswered message or missed
call can be saved as outreach without changing the last actual connection.
Notes stay with the corresponding moment in that person’s history. Existing
memories remain separate, deliberately written facts for the next catch-up.

## Existing data

There is no new schema or migration in this update. The bundle identifier,
journal location, person/contact IDs, moment representation, atomic save path,
and recovery copies are unchanged. The previous-version import fixture and
upgrade/edit/reopen checks remain part of precheck. Production does not receive
test data or reset flags.

## Verification

The quick-log journey exercises the real Home button and searchable chooser,
saves all three channels (including a blank optional note), cancels a draft,
reopens the app, checks the saved notes/channel/count, and edits an entry to
outreach. A second journey exercises dark mode and the largest accessibility
text size. Screenshots are captured from the actual Release simulator app.

During test development, a query incorrectly assumed the person heading was a
container rather than text, and a blank-note predicate incorrectly searched
for an empty substring. Both queries were corrected. The large-text flow also
revealed an actual offscreen Home action: the recording showed the introduction
pushing it below the viewport. Moving logging above the introduction fixed the
entry path; replacing a search query alone had not addressed it.

System microphone dictation is not verified on a physical device. The simulator
proves ordinary text entry, editing, persistence, and layout. All automated
verification uses the dedicated simulator; physical phones are not launched.

The regression checks were calibrated against three deliberately broken builds:
a channel button that did nothing, a save that discarded notes, and the original
offscreen Home entry at maximum text size. Each failed for its intended reason,
and source was restored afterward. The first visibility probe relied only on
`isHittable`, which incorrectly accepted the offscreen action. The final probe
also compares the control’s frame with the visible area above the tab bar.
[Calibration evidence](calibration.json).

## Final Release gate

`bash tool/precheck.sh` passed: all 926 archived files, six historical prototype
checks, three delivery-workflow checks, **22 native checks** (13 unit, 9 UI), and
a further native Contacts import/reimport check with broad Contacts permission
denied. This includes old-journal preservation, atomic saves and recovery,
relationship choices, reminder behavior, all three quick channels, saved notes,
cancellation, reopen/edit, and dark/large-text journeys.

The app’s sampled RSS peaked at 402.8 MiB under the 512 MiB simulator guard.
This bounded run does not establish physical-device memory behavior or absence
of leaks. App instances started for verification are terminated by the harness.

[Preview](preview.png) · [Quick editor](editor.png) · [Search](chooser.png)
· [History](history.png) · [Dark](dark.png) · [Large text](large.png)

[Native results](native-tests.json) · [Contacts-denied results](contacts-denied.json)
· [Source hashes](source-hashes.json) · [Memory samples](memory.csv).

## Signed device package

The optimized 1.0.0 (1003) App Store Connect package passed strict signature
verification. The exported app retains `com.plenara.plenaraApp` and the existing
journal path, includes the quick notes UI, and contains neither simulator reset
controls nor test fixtures. The app source is unchanged from the final Release
verification. [Signed artifact record](device-artifact.json).

The dedicated simulator was shut down after verification, and no Plenara app
instance or memory watcher was left running. No physical phone was launched or
tested. Remote installation remains controlled by TestFlight on the iPhone.

## TestFlight delivery confirmed

**1.0.0 (1003)** is available to the existing **Internal** group, with the owner
enrolled. Apple reports **VALID**, not expired, assigned to the group, and
**IN_BETA_TESTING**. Validation and upload completed without errors. Delivery UUID:
`2b514a8d-c4db-412a-814c-ef7d5a19b773`. Release notes were updated and their exact content read back.

[TestFlight availability](testflight-status.json) · [Release notes](release-notes.json).

Implementation and verification are pushed to main. This delivery record is
committed alongside the signed-package and TestFlight evidence. The remote
iPhone’s installation state is not observable from this Mac.
