# Focus on unassessed people

Luis requested: “The organize UI should let me filter out people I’ve already
sorted so I can focus on the people I haven’t assessed yet.”

## Behavior

Together starts with **Needs assessment only** enabled. **Missing detail**
defaults to Any detail: anyone with at least one of the five classification
dimensions still Not set. Choose Connection, Distance, Closeness, What I want,
or How it feels to work through one specific unanswered dimension in groups.
Turn the toggle off to revisit everyone. Search and Select shown use this
filtered list; the existing selection warning includes people outside the view.

Quick sort starts with its existing **Not set only** enabled. Saving a choice
removes a person from the relevant unanswered list; Undo returns them when their
earlier value was Not set. Show everyone clears the filtering and search.

Assessment derives from existing saved values. There is no duplicate completion
flag, schema migration, import replacement, or new reminder behavior. The
canonical design and iOS README now describe these defaults and filters.

## Regression

Before changing production code, the new native journey failed on build 1004
because Together offered no assessment filter. [Baseline test log](baseline.log).
The journey covers default filtering, Any detail, specific missing dimensions,
showing everyone, batch-save removal, Undo, and persistence after reopening.

A deliberate production mutation left the toggle active but bypassed the actual
filter. The same journey rejected it with “Fully assessed people must be hidden.”
[Calibration](calibration.json) · [Known-broken log](broken-filter.log). Production
source was restored in a finally block before the final Release build.

The existing batch/imported-journal and quick-sort journeys passed in the focused
run. Light and dark captures were reviewed, and the large-text journey now also
scrolls through Together's controls, selects an unanswered person, and returns
to Quick sort through the real mode control.

## Final verification

`bash tool/precheck.sh` passed: 926 archived files verified, six retained
browser-prototype checks, three TestFlight-workflow checks, **29 native Release
checks** (16 unit, 13 UI), and a separate Contacts import/reimport check with
broad Contacts permission denied. [Native summary](native-tests.json) ·
[Contacts-denied summary](contacts-denied.json).

The final light, specific-detail, finished-list, dark, and largest-text captures
were reviewed. The largest-text journey successfully reached a remaining person,
selected them, and returned to Quick sort.

[Default filter](assessment-remaining.png) · [Specific detail](assessment-specific-detail.png)
· [Finished list](assessment-complete.png) · [Dark](dark-organizer-assessment.png)
· [Largest text](large-text-organizer-assessment.png).

The sampled app RSS peak was 397.6 MiB under the calibrated 512 MiB simulator
guard. This bounded observation does not establish physical-device memory
behavior or absence of leaks. [Memory samples](memory.csv) ·
[Tested source hashes](source-hashes.json).

## Consolidation

Removed 569.7 MiB of logical bytes from superseded
compiler intermediates, redundant attachment exports, and extracted device
packages. This is logical removal, not a measured free-disk increase. The latest
usable simulator product and previous signed device artifact were retained, as
were native xcresults, logs, source, authored assets, and reviewed captures.
[Removed paths, hashes, and retained evidence](consolidation.json). No required
application services were stopped. Temporary test harnesses exited.

## Delivery blocked by account-holder agreement acceptance

Implementation source commit `f8ee402` is pushed to `main`. The automatic
`tool/deploy-testflight.sh` sequence built and archived optimized Release
**1.0.0 (1005)** successfully, but Apple's distribution export stopped with:

```text
error: exportArchive Unable to process request - PLA Update available
error: exportArchive No signing certificate "iOS Distribution" found
```

[Exact export log](testflight-export.log) · [Candidate archive checks](device-archive.json)
· [Fresh TestFlight readback: no build 1005 uploaded](testflight-status.json).

A fresh App Store Connect API read with the existing credential succeeds and
confirms owner enrollment and build 1004 still available. This is an Apple
account agreement block, not a session sandbox or established missing-credential
problem. The certificate error is retained as a secondary export diagnostic;
distribution signing must be retried after agreement acceptance before deciding
whether an independent certificate problem remains.

Apple states that the Account Holder must accept updated license terms and
that unsigned updates can pause automatic signing and TestFlight.
[Apple roles and agreement requirements](https://developer.apple.com/help/account/access/roles/) ·
[Apple access troubleshooting](https://developer.apple.com/help/account/access/resolving-access-issues/).
Luis must review and accept the update at
[Apple Developer Account](https://developer.apple.com/account/). No license
agreement was accepted on his behalf.

The candidate archive signature verifies, simulator fixture controls are absent,
and the binary contains the assessment UI and existing journal path. Build
1004's signed IPA remains the last usable distribution artifact while 1005's
validated archive is retained pending export. Temporary simulator verification
is shut down; no physical phone was launched. After preserving archive and logs,
completed packaging caches were removed. Total consolidated logical removal
is now 655.4 MiB, without claiming net filesystem
or free-disk change. Final tested source hashes still match.
