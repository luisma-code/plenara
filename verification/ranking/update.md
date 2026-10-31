# Inner-circle priority and complete reconnection list

Luis reported that Close relationships appeared ahead of inner circle and asked
for an Astra consultation and approval before implementation. The
[Astra-reviewed proposal](https://chatgpt.com/space/page_7ac81bc6f2b8819181b3d01e018f6619)
compared weighting, universal closeness tiers, protected/rotating slots, and a
complete list. Luis approved the recommended two-group scheme with **“Ship it.”**

## Approved change

Due inner-circle people precede every other eligible relationship. Within each
group, chosen-rhythm-relative elapsed time orders the list. Exact ties use
closeness, growth intent, then stable identity. Home shows the first three and
can expand to everyone in order, without calendar rotation. The accepted cost
is that lower-ranked people do not automatically rotate into the first three.

Pauses, snoozes, reply space, and explicit custom rhythms still apply. Growth
and care cards use the same suppression gate and avoid duplicate people. An
optional growth idea does not enable a rhythm; Needs care never adds urgency.
Birthdays and dated threads retain their separate explicit-date behavior.
The canonical design and README now describe this policy and link the approved
proposal. Historical verification records and browser reference are preserved.

## Regression evidence

Before production edits, the new native test failed on the shipped growth
promotion and calendar rotation paths. [Original failure log](baseline.log).
The implementation builds moment-date indexes once per selection pass, and
constructs the reconnection section separately from the rest of Home. No journal
identity, schema, atomic-save behavior, or import storage was changed.

The focused native model checks and Home journeys passed. Four exclusive
known-broken controls were then rejected for the intended reasons: inverted
inner-circle precedence, bypassed snooze suppression, a no-op expansion button,
and missing row-rhythm explanations. [Calibration](calibration.json). Production
source was restored before the final release gate.

The first largest-text journey exposed a narrow metadata layout and a test
that demanded a whole oversized row fit on screen. The
[recorded frame](large-row-before.png) and [original test log](large-text-initial.log)
were inspected. Accessibility rows now give their name and reason full width;
the improved row measured 452.7 points high in a 702-point usable viewport.
The test steers bounded drags using observed frames rather than overshooting
with full swipes, and still requires on-screen controls above the fixed tabs.
Light, dark, and largest-text focused journeys passed with actual expansion,
profile navigation, logging, snooze, and reopening.

Astra performed a separate read-only implementation review against the approved
Page and found no blocking policy, history, or storage mismatches. Astra did not
run the simulator or builds; runtime evidence comes from the local Release runs.

The pre-approval check of the unchanged production ranker is preserved as
[an inert probe source](old-ranking-probe.swift.txt) and
[its fixed-clock output](old-ranking-output.json). The source uses the model
from commit `41e9dd4c907a5e3c11fc37aa2b0f25846b3dd4d7`; it is historical evidence,
not an active app or test source. Growth displaced the small-list leader, and
calendar slicing omitted the very stale inner-circle person on three of six
consecutive dates.

## Final Release verification

`bash tool/precheck.sh` passed: all 926 archive entries, six historical browser
reference checks, three delivery-workflow checks, **36 native Release checks**
(21 unit and 15 UI), and a separate Contacts import/reimport check with broad
Contacts permission denied. [Native results](native-tests.json) ·
[Contacts-denied results](contacts-denied.json).

Final light/dark and largest-text captures were reviewed. The actual Home path
exercised full-list order, collapsing/expanding, profile navigation, logging a
connection, snoozing, reopening, and consistent suppression across sections.
[Home](ranked-home.png) · [Complete list](complete-ranked-list.png) ·
[After snooze](after-snooze.png) · [Dark Home](dark-home.png) ·
[Dark expansion](dark-expanded.png) · [Largest text](large-home.png) ·
[Largest-text expansion](large-expanded.png).

Sampled app RSS peaked at 398.8 MiB under the calibrated 512 MiB simulator
guard. This bounded run does not establish physical-device memory behavior or
absence of leaks. [Memory samples](memory.csv) · [Tested source hashes](source-hashes.json).

## Validation consolidation

Removed 171.2 MiB of logical working bytes from redundant
attachment exports, scratch inspection buffers, and completed compiler caches.
This is not a measured net directory or free-disk change. The latest simulator
product, last usable device IPA, native results, logs, selected failure frame,
old probe, and reviewed evidence were retained. [Consolidation ledger](consolidation.json).
The dedicated simulator is shut down; no verification app processes remain.
No normal application services or physical phone apps were stopped or launched.
