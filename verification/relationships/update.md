# Independent relationships — Plenara 1.0.0 (1002)

Luis approved this model after the Astra consultation. The implementation keeps
five independent, optional dimensions:

| Dimension | Choices |
| --- | --- |
| Connection | Family and/or Friend |
| Distance | Nearby / Far away |
| Closeness | Inner circle / Close / Casual |
| What I want | Keep it steady / Grow closer |
| How it feels | Feels good / Needs care |

All can be unset. People shortcuts combine across dimensions, and Filters
exposes every dimension. The active combination remains visible. Growth and
care choices do not start or change rhythms, declare a relationship unhealthy,
or create notifications. Optional personal context explains what matters.
Home keeps rhythm reminders separate from explicit growth/care invitations.

[Native preview](preview.png) · [About your relationship](about.png) · [All filters](filters.png)

## Keeping the existing import

The app's bundle identity and journal path stay exactly the same. There is no
reset, replacement with demo data, or reimport step in the production update.
The old journal and backups decode with new optional fields. Family/Friend and
old deepening choices carry forward. Local becomes Nearby; Acquaintance becomes
Casual. Getting to know is retained as earlier context and current closeness
is left unset. A previous deepen=false becomes unanswered, not Keep it steady.
Feelings always start unanswered.

The migration retains stable person IDs, contact links, photos, contact fields,
notes, personal context, moments, dates, rhythms, pauses, snoozes, and settings.
Opening the journal leaves its disk bytes untouched. On the first successful
edit, an exact protected before-update copy is retained in addition to the
normal previous-save backup. Later saves never replace the before-update copy.
Settings offers **Recover before relationship update**, with confirmation.
Backup restore and both local recovery options use the same decoding and
migration path as startup.

A frozen fictional journal was exported using the actual build-1001 model and
encoder. Unit checks open it, compare every original saved field except the
two explicitly renamed classification fields, verify original recovery bytes,
edit/save/reopen it, and restore both old and new backups. A native UI journey
opens the same old-format import, selects Family + Friend and independent
intention/feeling, changes closeness/distance, relaunches, finds the existing
note, and combines filters without losing either person. Fixtures are packaged
only into test bundles; fixture injection is simulator-only and uses an
isolated UI-test journal. No real imported journal is accessed during testing.

## Verification and delivery

Focused upgrade, persistence, classification, and reminder checks passed.
Known-broken controls were rejected for missing migration, a damaged recovery
copy, filters using OR instead of AND, and care flags starting reminders.
[Calibration record](calibration.json).

The full precheck passed: archive integrity, six historical design-reference
checks, three deployment-workflow checks, **20 native Release checks** (13 unit,
7 UI), and another successful Contacts import/reimport journey with broad
Contacts access denied. All 13 storage/model checks passed again after moving
the existing-recovery-copy check ahead of unnecessary old-file decoding.
[Full native summary](native-tests.json) · [Storage recheck](storage-recheck.json)
· [Contacts-denied summary](contacts-denied.json) · [Source hashes](source-hashes.json).

Light, dark, and maximum accessibility text captures were inspected, including
the actual new choice controls and the saved imported profile. [Dark choices](dark-choices.png)
· [Large-text choices](large-choices.png).

The focused dark/large-text UI journey passed again after requiring the sheet’s actual presented position before capture. [Appearance recheck](appearance-recheck.json).

Final TestFlight availability is recorded below after Apple's processing. All app verification uses the dedicated simulator, with a
memory guard and cleanup. No physical phone is launched or tested. The owner's
remote installation cannot be observed from this Mac.

The simulator app RSS peaked at 398.6 MiB in the full test run under the calibrated 512 MiB guard. This bounded observation does not establish physical-device memory use or absence of leaks.
