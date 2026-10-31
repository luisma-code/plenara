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
