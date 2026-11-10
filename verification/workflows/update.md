# Relationship workflows and social events

Luis approved Astra’s three recommended first-iteration improvements, plus logging social events with multiple people and a description. The [approved decision](../../docs/reviews/2026-11-09-relationship-effectiveness-proposal.md) retains the alternatives and tradeoffs.

## What changed

- Reach out from Home or a person’s page, with their preferred contact method first and every saved address available. Opening another app saves a recoverable draft. Returning offers **We connected**, **I reached out**, or **Nothing to record**. Only an explicit successful save records contact; unanswered outreach does not reset the connection date.
- Choose contact rhythms for multiple people after import, or from People/Home. Nobody is preselected; existing rhythms start protected. Setup never invents a conversation. Undo restores only the fields that setup changed and preserves newer unrelated notes and corrections.
- After logging a moment, an optional next-time step lets you save a memory or keep, resolve, unpin, or postpone existing conversation threads. Resolving preserves the original memory.
- **Log a social event** from Home or Moments. Choose any number of people, add a title, date, channel and what you did. A dinner with five friends is one shared entry in all five histories. Editing updates the same entry everywhere. Removing an attendee recalculates their connection date; deleting a person preserves the event for its remaining attendees.

## Native previews

[Saved five-person dinner](screens/saved-shared-dinner.png) · [Reach-out confirmation](screens/return-from-reaching-out.png) · [Dark event editor](screens/dark-shared-event-editor.png) · [Largest text event editor](screens/large-shared-event-editor.png)

## Existing journals

Storage identity and production paths are unchanged. Additional fields decode when absent; old single-person moments retain their original identity. Before the first edit of a previous journal, its exact bytes are retained in `.before-workflow-update`, with a recovery action in Settings. The frozen build-1007 fixture was generated with the previous model, before the new model was edited; [provenance](fixture-provenance.json) identifies its source and hashes. The build-1001 upgrade regression also remains active.

## Implementation review

Astra performed a read-only integration review and found three additional edge cases, all corrected before release:

1. Both return-confirmation outcomes now default to the persisted draft’s original date, including an overnight interruption. The date remains editable.
2. A custom contact interval always has a matching picker option, so a 15-day rhythm remains named and selectable.
3. Applying an unchanged batch explicitly reports that nothing changed, clears a stale success message, and preserves the earlier actual Undo receipt.

Astra then reviewed the restored Home and editor integrations. A separate review of native screenshots identified cramped Home actions at accessibility text sizes, an oversized next-time banner, and an event Save action whose disabled appearance was too subtle. Those visual corrections are included. The native thread preview also exposed a stale resolution notice after starting a different thread; each new thread action now clears that notice.

## Verification

The production faults in shared-event membership, exact recovery bytes, chosen cadence, draft consumption and thread postponement were deliberately introduced and rejected by the new unit tests. The actual previous search-hidden Done button and a disconnected background-return offer were also rejected by native UI checks. All three existing quick-log controls (channel selection, saved note and largest-text entry position) were rerun and rejected after the integration. New assertions also rejected the actual stale thread notice and the old 174-point-wide accessibility Home action before their production fixes.

The mutation runner restores source on interruption. Its isolated self-tests also reject an earlier red log after a build failure; both protections were themselves checked against deliberately broken versions. Final checks rebuild from restored production source.

The simulator journeys exposed and corrected search hiding the attendee Done action, an offscreen test-navigation helper, and a custom-stepper test locator that did not match the actual accessibility identifier. Native search completion now stays in a fixed footer; test navigation uses measured direction and the rendered control identifier. The custom-stepper investigation also established a stale test-host execution:
the built and installed bundle hashes matched, but the run omitted the current
assertion/capture and used the previous selector. Recreating the dedicated UI-test
runner installation executed the current selector and passed the custom-rhythm
journey. The native gate now installs a fresh owned runner, uses an explicit
architecture-specific manifest with checked Release paths, records binary hashes,
and rejects zero-test results. The [existing global shipping guidance](/Users/luisma.code/.codex/skills/ship-what-you-ran/SKILL.md) already
covered this failure; its entry checklist now links directly to that section,
and the entry-checklist change was validated, mirrored, committed and pushed to the guidance
backup (`f6bde47`).

The first full gate also caught an older largest-text journey typing into a
People search field covered by bottom navigation after the new setup entry moved
it lower. The UI suites now share one visibility helper that measures the tab
bar and keyboard viewport, scrolls toward the actual control, and waits for a
keyboard before typing in People search. The existing failed run is retained as
the known-broken control.

The next complete run passed 60 of 61 tests. Its remaining failure was an older
quick-sort journey tapping a person row outside the visible viewport. The actual
native recording showed the covered/offscreen list; its retained
[frame](quick-sort-covered-row.png) is the diagnostic evidence. Converting that
navigation to the shared measured helper passed the targeted journey. A later
gate was deliberately interrupted to batch the screenshot-review corrections
before the final full run; its raw output is retained separately and is not
reported as a passing gate.

An initial contact run also encountered an XCTest activation timeout; the return journey now acknowledges background state before reactivation. Raw first-run logs are retained alongside the restored-source checks, without treating the timeout as a demonstrated device-app defect.

The two final UI regression assertions passed after the visual/state fixes. Astra accepted the refreshed native screenshots individually. Final gate results appear below.

The next gate exposed numerical noise in a pre-existing touch-height assertion:
a correct 44-point target was reported as `43.99999999999994`. Every minimum
height assertion now uses one shared comparator allowing only `0.000001` point
of arithmetic noise. The gate was stopped to repair that verifier, with its raw
output retained. A native 43-point target is the negative control. This lesson
was added to the live `calibrate-the-instrument` skill, validated, mirrored, and
pushed to the guidance backup (`dbf8503`).

The first geometry calibration changed only the expansion button’s outer frame;
the shared comfortable-button style still enforced 44 points, so the check
correctly continued to pass. That output is retained as a positive control. The
revised undersized control changes both minimum-producing paths, then restores
their exact source bytes before rebuilding the candidate.

A subsequent run exposed an older bulk-selection test assuming that a batched
backspace/retype operation had replaced its search. The native recording still
showed **Alex**, with Alex correctly selected, when the test expected Maya and
an outside-view count. The retained [failure frame](organize-selection-failure.png)
distinguishes missed query input from lost selection. The UI suites now share an
explicit clear/submit helper that waits for keyboard focus, cleared text,
submitted query and keyboard dismissal for nonempty submissions; the count waits for its rendered state. Empty search uses its own clear-completion path because the native Search action is disabled.
The same helper serves repeated attendee and rhythm searches.

The repaired bulk-selection journey passed through cancellation, batch save,
Undo and imported-journal reopen. The five-person dinner journey also passed
with the shared explicit-query helper. The general lesson now lives in the
live `events-not-timers` skill, validated and backed up in pushed commit
`c0050a8`. Final full verification rebuilt the unchanged production app and
these corrected test instruments together.

## Final gate

`bash tool/precheck.sh` passed: all 926 archived hashes, six design-reference
checks, six TestFlight-tool tests, two calibration-runner tests, **39 native unit
and 22 native UI tests**, plus the separate Contacts-denied import repeat.
[Structured result](verification.json) · [complete gate output](final-precheck.txt).
All native checks used Release on the dedicated iOS26.5 simulator. The bounded
memory guard remained active; the measured peak and source hashes are recorded
with the result. All nine workflow previews were refreshed from the final green
native run. No automated verification ran on a physical phone.

TestFlight1008 delivery is being completed from the committed, pushed source.
