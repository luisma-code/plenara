# Plenara — a little closer

**Approved design · October 16, 2026 · independent relationship attributes approved after Astra consultation**

Plenara is a quiet place to care for your relationships. It helps you remember
who you want to stay close to, make room for them, and carry the little details
forward. The primary problem is time slipping away, especially with distant
friends. The app should turn that into an easy invitation to reconnect.

[Current native relationship update](../verification/relationships/update.md) · [Original screen preview](preview.png) · [Original interactive design reference](prototype.html)

The preview and prototype use fictional people. This document is the single
home for the approved product design. The previous planner, designs, project
skills, instructions, tests, and implementation have been archived; they place
no constraints on this design. Global working preferences remain in effect.

## The experience

Open Plenara and see a few people it would be lovely to connect with. A friend
in Brooklyn hasn’t heard from you in a while. Her ceramics show is coming up.
You open her page, remember what’s going on, and send a voice note. Later, when
you’ve exchanged messages, record that moment in a few taps. Next time, you
have a thread to pick up instead of a blank page.

This should feel like a thoughtful personal address book, with a gentle sense
of time. Beautiful means calm, legible, and specific to the people you care
about. Avoid relationship scores, streaks, competitive dashboards, and alarming
“overdue” counters. Luis approved this direction; he can change any of these design choices.

## Three places, one simple structure

### Stay close

The opening screen answers “Who could I make a little room for?”

- One prominent reconnection invitation, with a personal detail to make starting
  easier. Prefer a relationship marked for deepening when several are due.
- Up to two more people whose chosen rhythm suggests it is time to reconnect.
- A nearby person you want to know better, with a concrete shared idea.
- A global “Log a moment” and a person-specific “Log with [name]” make logging easy; “Catch-up notes” and “Another week” support the invitation.
- A quiet all-clear state when nobody needs a reminder. No target to fill.
- Explicit birthday and dated-note reminders appear with their person at the top
  when due. Completing a dated thread clears its reminder and keeps the memory;
  it never fabricates a connection.

Distant people get opportunities to call, exchange voice notes, or plan ahead;
local people get opportunities to meet. Distance changes the suggested method.
It does not imply that a distant friendship matters less.

### People

A searchable, alphabetical list of people. Shortcuts include Everyone, Grow
closer, Needs care, Nearby, Far away, and Family. Choices from different
dimensions combine: Family + Far away + Needs care narrows the list to all
three. The Filters sheet exposes connection, distance, closeness, intention,
and feeling independently, including unanswered profiles. Everyone clears all
filters. A Clear action beside Filters also clears the combination. Show the active combination and a reassuring empty state: no matches
does not mean the imported people disappeared.

Each row has a photo or a warm initials avatar, name, location, and closeness.
Growth and care intentions have small symbols with accessible text labels.
An add button offers Contacts import and manual entry.

**Organize** appears when there are people to organize, above the People
introduction and reachable at large text sizes. One workspace has two modes:

- **Together:** select individual people, or Select shown after searching by
  name/city. Selection persists across searches, with a visible total and a
  warning when selected people are outside the search. Clear selection clears
  the entire selection. A shared-details sheet starts every attribute at No
  change. Apply changes only chosen attributes for selected people, atomically.
  Add/Remove Family and Friend preserve the other label; Family + Friend sets
  both, and Not set clears only that attribute. Cancelling applies nothing.
- **Quick sort:** choose one of the five attributes, then tap a value beside
  each person to save immediately. The current value stays visible. Not set
  only filters that chosen attribute; a newly answered person leaves that view.
  Skip omits someone from the current pass without changing their journal.
  Show skipped people brings them back; switching mode/attribute resets skips.

Undo last organization reverses the last successful organizing action during
the current app session, even after closing and reopening the workspace.
It restores only attributes that actually changed, preserving later notes and
other unrelated edits. If those attributes were edited again or a person was
removed, Undo refuses the whole operation. It never recreates a deleted person.
A failed batch or Undo does not publish partial changes or consume an earlier
Undo. A backup restore clears the older Undo. Organizing never changes contact
rhythms, dates, notes, contact links, or moments. It uses the same journal and
atomic persistence path as individual editing; there is no schema migration.

### Moments

A personal history of calls, meals, visits, message exchanges, and little
hellos. Entries run newest first, with the person, date, channel, a short optional
note, and whether you connected or simply reached out. This is a way to remember
time together; it does not reward logging volume.

Home has a prominent Log a moment button for any person, including those without
a contact rhythm. A searchable person chooser leads to the same quick editor
used on a person’s page and in Moments. Called, Texted, and Met are one-tap
choices; video calls, voice notes, and email remain under Another way. The
editor defaults to today and Connected. Notes are optional, and a moment can be
saved without typing. The keyboard’s standard dictation microphone can fill the
same editable note field; Plenara adds no speech recording or AI service.
Connected and Reached out stay explicit so an unanswered text or missed call
never silently becomes a catch-up. Date, notes, and channel remain editable.
The existing local journal and contact import identity stay unchanged.

## A person’s page

Read from top to bottom in the order you need before contacting someone:

1. **Who they are.** Photo, preferred name, city, local time if known, Family
   and/or Friend, current closeness, and Nearby/Far away. Birthdays are visible
   here when kept. Connection, distance, and closeness form About your relationship.
2. **What matters now.** Two separate optional choices: What would you like?
   (Keep it steady / Grow closer) and How does it feel? (Feels good / Needs care).
   A shared optional context note captures what you want to give attention to.
   Both choices can be cleared. A good relationship can still be one to grow;
   a close bond can need care without a change in desired closeness.
3. **Do something.** Log a moment; reach out using their preferred method.
4. **Before you catch up.** A pinned fact or question: an upcoming show, a new
   job, a parent’s recovery, a topic to revisit. Written by you; no inference
   that an old fact is still current. Show when the note was made.
5. **Your rhythm.** Editable contact interval and factual time since connection.
6. **Little things to remember.** Short, dated, editable notes in lightweight
   categories. These remain visible without a complex tagging system.
7. **Time together.** The timeline for this person.

Important notes should be pinnable; a completed conversation thread can be
unpinned or archived. “Their world” can link another tracked person when useful,
but should also work as plain text. No requirement to build a family tree.

## What we keep per person

Only a name is required to add someone. Everything else can be learned over
time. A short setup offers relationship, closeness, near/far, and rhythm; it can
be skipped. Don’t demand a complete profile before the person appears.

| Information | Why it belongs | Suggested treatment |
| --- | --- | --- |
| Preferred name, pronunciation, photo | Recognize and address them naturally | Name required; the rest optional |
| Contact methods and preference | Start a call or message without searching | Import phones/emails; let Luis choose the preferred route |
| Connection: Family and/or Friend | How you know them, independent of affection | Two optional selections, either or both; optional “cousin,” “university friend,” etc. |
| Current closeness | How close the bond feels today | Inner circle, Close, Casual; leave unset |
| City/area, time zone, Nearby/Far away | Suggest a fitting connection at a sensible time | Manual or imported area; no GPS requirement or assumption from phone prefix |
| Desired direction | Remember the relationship you want | Keep it steady / Grow closer; leave unset |
| Personal feeling | Distinguish feeling good from something deserving care | Feels good / Needs care; leave unset, never inferred; optional context note |
| Desired contact rhythm | Convert intention into a gentle reminder | Weekly to seasonal, custom interval, or off; always editable |
| Last meaningful connection | Notice when time has slipped away | Derived from confirmed moments; allow an approximate starting date |
| Recent outreach | Avoid pestering someone awaiting a reply | Separate from connection; no automated escalation |
| Birthday and important dates | Make room for meaningful occasions | Optional dates and reminder choice; year optional |
| Their people | Remember partners, children, parents, pets | Short notes; optional links to existing people |
| What matters to them | Interests, preferences, values, favourite places | Short freeform notes; no required fields |
| What’s happening now | Job changes, projects, celebrations, hard things | Dated notes, easy to update/archive |
| Our shared context | How you met, shared interests, traditions | Optional notes |
| Next-time threads and shared ideas | Start conversations and make plans | Pinnable question or idea, with optional date |
| Moments together | Remember the relationship over time | Channel, date, connected/outreach, optional note |

Sensitive details are optional personal notes, never inferred fields. Avoid
collecting an entire address or personal identifiers when city and time zone
are enough. Notes belong to the relationship journal, separate from the phone’s
Contacts notes. Do not silently write journal notes back to Contacts.

## How the reminders work

“Healthy” is personal. The app uses a rhythm Luis chooses; elapsed time is a
reminder signal, not a claim that the bond is unhealthy. Direction and feeling
are user-authored answers, independent of connection, distance, and closeness.
They start unset, including on import. Keep it steady is an intention, not a
health assessment. Needs care does not lower closeness, change a rhythm, start
a countdown, or add a notification. Home keeps Time to connect separate from
small, explicit growth/care invitations, avoiding duplicate cards for the same
person. Needs care is never ranked as urgent by the reminder algorithm.

**Starting suggestions, to be confirmed during setup:**

| Closeness | Initial rhythm | If marked for deepening | Examples by distance |
| --- | --- | --- | --- |
| Inner circle | Weekly | Offer twice weekly or a personal rhythm | Nearby meal; distant call |
| Close | Monthly | Offer every 2 weeks | Nearby walk; distant voice-note exchange |
| Casual | Every 3 months | Offer monthly | Nearby coffee/event; distant thoughtful check-in |
| Unset | Off until chosen | Offer setup | Import is not permission to nudge |

These are proposals, not a formula for friendship. Family does not automatically
mean inner circle. Distance does not lower the suggested frequency. Location
and distance are separate: “local” is Luis’s judgement, and can be edited after
a move. Travelling can temporarily change how a connection is suggested.

A manual rhythm always wins. Choosing Grow closer does not change a rhythm. The rhythm editor
offers a suggestion that must be explicitly chosen. A custom rhythm is supported in
the native app even though the browser prototype uses preset choices.

For scheduling, use calendar dates in the owner’s time zone. A reminder becomes
eligible once the interval has elapsed since the last confirmed connection.
Unknown last contact means “Last contact not set”; offer “roughly when?” or
“start reminding me from today,” never fabricate history or call it overdue.

Rank eligible people by proportion of their interval elapsed, then the
explicit deepening intention; break ties deterministically. For a small daily
set, surface at most three. Quietly rotate eligible people that weren’t shown
so one long gap never monopolizes the screen. The prototype demonstrates the
three-person cap and deepening preference; rotation is a native implementation
detail, not implemented in the browser example.

A confirmed call, meet-up, or reciprocal exchange resets the interval. A sent
message or unsuccessful call is an outreach; it does not reset connection time.
Recent outreach suppresses repeated invitations for seven days by default,
with an option to revisit. Snooze postpones the reminder without inventing a
connection. Pause reminders per person indefinitely when life calls for space.
Never interpret silence as permission to keep increasing pressure.

A quiet weekly digest is the recommended default after opt-in. Let Luis choose
a day/time and quiet hours. The native notification should say “A little time
for your people?” without personal notes on the lock screen. The in-app list
still works with notifications denied. Optional birthday and specific follow-up
reminders are separate, individually controlled choices. The prototype does
not send notifications or implement all scheduling behavior.

## Contacts import

1. Explain: “Choose the people you’d like to keep close.” Offer manual entry
   alongside Contacts; permission is requested only when importing.
2. Use Apple’s permission-aware Contacts selection. Support selected-contact
   access, full access, and denial; never force whole-address-book permission.
3. Review selected people before adding. Import name, available photo, selected
   phone/email, and optional birthday/city only when useful and accessible.
4. Ask for lightweight setup, individually or in a batch. Do not infer family,
   closeness, direction, feeling, last contact, or reminder permission.
5. Let Luis add more later without duplicating existing people. Keep source
   contact identifiers for reimport; detect possible matches but ask before
   merging ambiguous entries. Linking a manually added person must preserve
   their notes and moments.

If access is denied, continue with manual entry and offer an explicit Settings
route. If access is later revoked, retain Luis’s journal, explain the lost link,
and allow unlinking or removing imported fields. An unavailable contact should
never silently delete the relationship history. A removed person in Plenara
never deletes the phone’s contact. Refresh contact fields deliberately, with
journal fields kept separate and conflicts reviewable.

Apple documents both limited contact access and the user-controlled contact
access picker in [Accessing the contact store](https://developer.apple.com/documentation/contacts/accessing-the-contact-store).
Exact implementation must follow the supported OS versions chosen for the
native app. The browser prototype demonstrates selection using three fictional
contacts; it has no access to the phone address book.

## Visual direction

**Warm editorial address book.** An ivory canvas, deep plum text and actions,
soft lavender reconnection cards, sage nearby invitations, and a peach reminder
panel. A rounded serif heading gives the app warmth; system sans-serif keeps
names, dates, and controls familiar. Initials make the app beautiful before
photos are available. Real people’s photos can replace those circles later.

| Element | Direction |
| --- | --- |
| Canvas | Warm ivory `#F8F6F2` |
| Main text | Ink `#302C39` |
| Secondary text | Muted plum `#716B78` |
| Primary action | Plum `#65516F`, white label |
| Feature surfaces | Lavender `#ECE5F0`, sage `#E5ECE4`, peach `#F3E3D9` |
| Heading | Serif, 34–42 pt for page title; smaller for sections |
| Body | Native system font, 17 pt target in the iPhone build |
| Controls | Minimum 44 pt targets; primary actions 48 pt |
| Shape | 20–26 pt card corners; round avatars; restrained outlined icons |
| Motion | None required by this proposal; keep interactions immediate |

The native design should support Dynamic Type, VoiceOver labels and logical
reading order, Increase Contrast, light and dark appearance, reduced motion,
safe areas, and small screens. Colour is never the only signal of a state.
For dark mode, use a charcoal-plum canvas with lighter ink and muted plum/sage
surfaces; approve actual rendered pairs during implementation. The prototype
intentionally explores light mode only, with fixed sample typography rather
than claiming native accessibility coverage.

## Options considered

| Option | Strength | Cost / reason not chosen |
| --- | --- | --- |
| Gentle editorial address book — recommended | Personal, readable, easy to act on; dates and notes share the screen | Requires careful prioritization to stay quiet as the list grows |
| Relationship garden or orbit map | Beautiful overview, expressive sense of a circle | Names and actionable context become harder to scan; spatial layout needs teaching and accessibility alternatives |
| Health dashboard with scores | Fast comparisons, explicit targets | A score implies knowledge of emotional closeness the app does not have; encourages optimizing logging |
| Contact list with reminder badges | Familiar and cheap to build | Easily becomes an intimidating queue; makes distant friends disappear into a long list again |

Keep the garden metaphor in a small line illustration rather than making it
the navigation. Luis approved the warm editorial direction and requested implementation.
The native app uses SwiftUI, with the existing browser prototype as a visual
reference rather than a web wrapper.

For storage, an on-device personal journal is the smallest private first
version, but needs an explicit backup/export path. Private iCloud sync would
make device replacement easier at the cost of conflict and account handling.
A hosted account service adds recovery and multi-platform flexibility but also
an account flow, operational work, and a larger privacy boundary. The first implementation uses
local storage plus user-controlled export and restore. There is no automatic
sync; the app explains the need to back up before changing phones.
The prototype’s browser storage is demo convenience, not a chosen native
storage architecture or a safe place for real relationship information.

## First usable app boundary

Contacts import and manual people entry; relationship setup; home suggestions;
search and filters; person page; editable notes and moments; adjustable rhythms;
independent direction/feeling choices; opt-in reminders; export and deletion. The app opens
existing communication tools rather than building its own messaging system.

It should not need an AI service to remember a fact or know time has passed.
A voice-capture convenience or automatic summaries could be assessed later,
but neither is part of this fresh design. No message scraping or background
contact-history inference is assumed.

Deleting a person must explain the effect on their journal and offer a clear
cancel action. Editing or deleting a moment must recompute the latest confirmed
connection. Export must include people, notes, rhythms, and dated moments in a
readable format. These controls are part of the proposed native app, not all
present in the design demo.

## The original browser design reference

This is the historical visual reference from before the independent-attributes
update. Its original categorical labels and single-filter behavior are not the
current native product specification. It stays clearly marked as an earlier
reference, with fictional demo data, so original design decisions and their
checks remain reproducible.

Originally implemented and wired: three tabs; people search and filters; person pages;
manual add/edit of basic person fields; intention toggling; preset rhythm
editing; adding dated notes; logging a connection or outreach; seven-day snooze;
fictional selective contact import with repeat-import deduplication; a reminder
explanation; and confirmed demo reset. Changes persist in this browser when
storage is available. No network requests, remote fonts, or third-party assets.

The native implementation in `ios/` is separate from the reference. Relationship
type, closeness, and distance start unset; importing never guesses family or
friend status. It adds
real Contacts selection and import review; call/message/email handoff; local
notifications; birthdays; custom intervals; note pinning, editing and archiving;
editable/deletable moments; an approximate initial connection date; outreach
suppression; daily suggestion rotation; paused reminders; backup/export/restore;
adaptive appearance; scalable text; and native accessibility labels.

Contacts uses Apple’s `CNContactPickerViewController` for one-time selected
contact access. It does not request persistent full or limited address-book
access, so no permission-revocation watcher is necessary. Reimport is always
user initiated. An application-owned UUID keeps each person stable. Selected contact IDs support
deduplication, with a unique exact match of already imported name, communication
details, city, birthday, and photo as a fallback when picker IDs change.
Ambiguous matches start unselected and require an explicit choice to link an
existing person or keep a separate person. There is
no silent merge or ongoing contact refresh. Import never writes phone Contacts.
[Apple documents this picker’s selected-contact access](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller).

The journal is a versioned JSON file in Application Support, written atomically
with file protection. A previous local save is retained for recovery. Journal
state changes only after a successful disk write; a read failure leaves the
original protected until recovery. Restoring a JSON backup is validated and
requires confirmation before replacing current data. A readable text export is
also available. JSON is the complete restorable representation, including photos.

Reminder settings request system permission only on explicit enable. Weekly
digests repeat; optional birthday and dated-note reminders are independently
controlled. Quiet hours shift the scheduled time, and notification text contains
no names or journal notes. At most 48 requests are scheduled, refreshed on data
changes and foreground entry. Opening periodically refreshes the horizon for
dated reminders. There is no background fetch or cloud scheduler.

See [implementation verification](../verification/implementation.md) for the
checks actually performed, screenshots, and physical-device delivery outcome.

## Reset and review record

Luis requested: “stash the current plenara implementation in an archive folder
in the repo” including “all designs, skills, instructions,” and “start from 0
again.” The new goal is a beautiful iPhone interface for family and friends,
local and distant, at differing levels of closeness; explicit deepening
intentions; help remembering distant friends; personal context for the next
conversation; and Contacts import.

This replaces the archived project rule “Plenara is Luis’s voice-first personal
planner and relationship assistant” from the previous `AGENTS.md`. The
recommendation is to retire that broader planner remit in favour of this
relationship-focused product. No tasks, habits, voice-agent, or existing
architecture is carried forward. Luis subsequently said “Looks beautiful, please implement,” approving the
design and authorizing the native build. The old archive remains historical.

## Historical verification of the browser design artifact

Ran `bash tool/precheck.sh --capture` against the actual HTML in headless Chrome:
all six browser journeys passed (saved connection and persistence, outreach,
people search/filter, selective repeat import, notes/rhythm, snooze). Each
journey was separately shown a broken implementation and rejected it before
the restored prototype passed. The archive guard also rejected a deliberately
altered checksum, then passed the restored manifest.

One calibration initially searched the entire page for a note. The catch-up
summary repeated the same text and masked a broken note renderer. The check
now reads the memory list itself; that same mutation fails with the intended
message. The general lesson was added to the live global
`tests-that-can-fail` skill and mirrored/pushed to its guidance backup.

Captured and visually reviewed Stay close, People, the person page, moment
logging, and Moments at 393 × 852 CSS pixels. Navigation views also remained
within the viewport at 320 and 430 pixels. These are browser layout and
interaction checks, not native iPhone runtime, accessibility, notification,
or Contacts verification. The screen collage is composed from the captured
prototype; it is not a separate illustration of an unbuilt UI.

To regenerate: `bash tool/precheck.sh --capture`, then run
`node tool/render-preview.cjs` with the same Node module path used by precheck.
The archive’s 926 file hashes are verified on every precheck. No archived app
was launched and no physical device was used.


## Native app icon

The native icon uses six filled, rounded petals in the app’s ivory, lavender,
and peach palette, on a plum field. This carries the six-part botanical motif
into the launcher with enough visual weight for small sizes. The dark
appearance deepens the plum background. Editable masters live in `design/icon/`;
`tool/render-icon.cjs` renders both asset-catalog PNGs and the size-review sheet.
See the [icon update record](../verification/icon-update.md).


## Independent attributes: alternatives and preservation

Luis approved the five-dimensional model following Astra consultation: Family
and/or Friend; Nearby/Far away; Inner circle/Close/Casual; Keep it steady/Grow
closer; Feels good/Needs care. Every dimension can remain unset.

A single Steady/Grow/Repair selector would mix desired closeness with felt
condition; someone can want to maintain a close bond while clearing the air.
A lone Needs care toggle would make an unassessed relationship look healthy.
The two explicit optional choices preserve both distinctions with one small
additional field. Health scores, severities, target closeness levels, and
automatic assessments add apparatus and false precision without helping the
chosen experience. These choices remain revisable by Luis.

Updates retain the existing app identity and `RelationshipJournal/journal-v1.json`
storage path. New classification fields are additive and optional for decoding
old journals and backups. Old Family/Friend selections remain; Deepen=true
becomes Grow closer, while false stays unanswered. Local becomes Nearby;
Acquaintance becomes Casual. Getting to know is retained as earlier context,
with current closeness unset because a stage does not establish felt closeness.
Existing rhythms, pauses, history, contact links, photos, notes, identities,
and personal text are retained. No reimport is required.

Opening an old journal normalizes it in memory without rewriting the original
file. The first successful edit keeps a protected before-update recovery copy
in addition to the normal previous-save backup. Later saves do not replace the
before-update copy. Settings offers explicit recovery with confirmation. Old
exported backups and previous local saves use the same decoding/migration path.
