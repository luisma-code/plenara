# Plenara — organize your people quickly

Luis found editing imported people one profile at a time too slow. He approved
a single Organize workspace with bulk selection and a quick attribute-by-
attribute pass, plus an unanswered filter and Undo.

## The two flows

People has an **Organize** button above its introduction, including at maximum
accessibility text size. **Together** lets you search by name or city, select
individual people or Select shown, and apply shared details. Selection carries
across searches; its total explicitly indicates people outside the current
search. Clear selection clears all selected people.

The shared-details sheet starts all five attributes at **No change**. Only the
choices you make are applied. **Add Family** and **Add Friend** retain the other
label; their Remove choices remove only that label. Family + Friend sets both,
and Not set clears that attribute. Apply is disabled without a choice; Cancel
saves nothing. Existing imported fields, notes, history, and rhythms are kept.

**Quick sort** picks one attribute and presents direct choices beside each
person, with the current value visible. Tapping saves immediately. **Not set
only** filters the chosen attribute, and answered people leave that view. Skip
omits someone from the current pass without saving a classification; Show
skipped people brings them back. Changing mode or attribute resets skips.

Both flows share the same validated, atomic organizing operation. A group is
saved in one write. Neither flow creates a new contact, changes reminder
rhythms, or replaces a person’s complete saved profile.

## Undo and data preservation

**Undo** restores the attributes changed by the latest successful organizing
action. It remains available after closing/reopening Organize during the same
app session, and is intentionally not a durable history across app restarts.
It preserves unrelated newer edits, including a later note. If an edited
attribute has since changed, or a person was removed, Undo refuses the whole
operation. It never recreates a deleted person. Failed writes publish no partial
batch and retain the prior Undo for retry. A successful backup restore clears
the old Undo.

The app identity, journal file, schema, Contacts link IDs, and recovery paths
are unchanged. The original previous-version import fixture is exercised by
both persistence tests and the bulk UI journey. All verification runs on the
dedicated simulator. No physical phone is launched or tested.

## Review and verification

The first storage checks passed preservation, conflict detection, failed save,
retry, and Undo. The first quick-sort and appearance journeys passed as well.
The initial bulk UI query matched both a native picker’s Nearby option and the
covered People shortcut. The test was corrected to select the presented
collection’s option, and the complete bulk/cancel/Undo/reopen journey passed.

The large-text capture revealed a long fixed status footer consuming too much
space. Status text was moved into the scrolling list; Undo stays compact and
reachable at the bottom. Both modes use a native lazy list and scroll their
controls at larger text sizes.

Four deliberate broken builds were rejected: applying a batch to an unselected
person, allowing Undo to overwrite a newer choice, publishing a batch after a
disk write failure, and a quick-sort button that failed to save its choice.
Each check failed for its intended assertion, and source was restored before
rebuilding the release candidate. [Calibration evidence](calibration.json).

The first full gate exposed two older journeys whose test taps assumed their
targets were already visible. The added entry shifted Clear filters below the
viewport, and its test tap navigated to Stay close via the covered tab bar. The
empty-list import button was likewise below the visible content. Recordings
were inspected before changing these flows. Clear is now beside Filters;
Organize is omitted when there are no people. The native import journey scrolls
its actual button completely above the tab bar before opening the picker, and
the filter-clear journey checks both visible placement and the restored count.

The repaired import and clear-filter journeys then passed. Their updated checks
also rejected disconnected Clear and Import actions for their intended reasons.
[Viewport journey calibration](viewport-calibration.json). All production
source was restored before the final full gate.

Visual review then found that an active search keyboard could remain beneath
the shared-details sheet, particularly after returning from its picker menus.
The workspace now binds the native search focus, resigns it before presenting
the sheet, and dismisses focus on Search submission. The first keyboard check
used accessibility existence, which falsely accepted a still-painted panel.
The corrected check samples the rendered light-form canvas after interacting
with the pickers: a warm canvas reads below B-R -1, while the deliberately
broken keyboard panel read +1. The known-good capture’s patch mean was -3.16;
the original broken capture’s was +0.25. The original focus fault was reproduced
and rejected, then production source was restored. [Focus calibration](focus-calibration.json).

## Final verification

`bash tool/precheck.sh` passed: all 926 archived files, six historical prototype
checks, three delivery-workflow checks, **28 native Release checks** (16 unit,
12 UI), and an additional native Contacts import/reimport check with broad
Contacts permission denied. The complete run includes the prior upgrade,
export/restore, notes/moments, reminder, and accessibility journeys alongside
all new organizing journeys. The rendered shared-form check read B-R **-6**
with production focus handling, versus **+1** with the original fault.

Sampled app RSS peaked at 406.6 MiB under the 512 MiB simulator guard. This
bounded run does not establish physical-device memory behavior or absence of
leaks. All app instances started for verification are terminated by the harness.

[Preview](preview.png) · [Selection](selected.png) · [Shared details](shared.png)
· [Quick sort](quick-sort.png) · [Saved choices](saved.png) · [Profile](profile.png)
· [Dark](dark.png) · [Largest text](large.png).

[Native results](native-tests.json) · [Contacts-denied results](contacts-denied.json)
· [Source hashes](source-hashes.json) · [Memory samples](memory.csv).

## Signed delivery

Source commit `45abc2a2fffe0361058468334dbdaab471bb5e8d` is on `main` and
`origin/main`. The signed Release IPA is version **1.0.0 (1004)**. Its strict
code signature verifies; simulator controls and test fixtures are absent.
The optimized binary contains the organizing interface and preserves the
existing journal filename and app identity. [Signed artifact checks](device-artifact.json).

The final source hashes still match the tested code after archive/export.
The dedicated simulator is shut down; process inspection found no remaining
Plenara instances or memory watchers started by verification. No physical
phone was launched or used for tests.

Apple accepted the upload and processing completed. Fresh App Store Connect
readback confirms build **1004** is valid, unexpired, attached to the existing
Internal group, and `IN_BETA_TESTING`, with Luis enrolled.
[TestFlight availability](testflight-status.json). The build's English
[release notes](release-notes.json) were saved and read back exactly.
TestFlight installation and Automatic Updates on the remote iPhone remain
controlled on that device; this confirms testing availability, not installation.
