# Making Plenara more effective at staying close

**Approved by Luis · November 9, 2026 · Astra review**

Luis approved the three recommended changes by asking “Add Astra’s suggestions,” and additionally requested shared social events, such as a dinner with five friends. The approved behavior is now owned by [the product design](../../design/relationship-app.md#following-through-and-social-events). This decision document preserves the options and reasoning considered; alternatives below were not selected merely by appearing in the comparison.

## Recommendation

Make the next approved iteration help someone **choose a person, reach out, and carry one useful thread forward**. Keep the private, personal journal, optional rhythms, and distinction between contact and unanswered outreach. Prioritize easier action and rhythm setup before adding more classification, dashboards, or automation.

At the build-1007 review, Plenara remembered people well, but its most prominent actions recorded conversations that had already happened. Contacting someone required going deeper into the app. Imports correctly started without rhythms, but users had to discover and configure them one person at a time. The following table records that pre-change implementation; these observations were not measured claims about Luis’s behavior.

A useful research signal is that people can underestimate how much another person appreciates an unexpected check-in. Liu and colleagues found that pattern in preregistered experiments. That supports exploring an easier invitation to act; it does **not** establish that a particular Plenara feature improves relationships or that any particular person wants contact. [Primary study](https://www.apa.org/pubs/journals/releases/psp-pspi0000402.pdf).

## What worked at the build-1007 review, and which gaps prompted this decision

| Experience at review | Actually wired in build 1007 | Gap or consequence |
| --- | --- | --- |
| Remember who is ready to reconnect | `Journal.rankedSuggestions` feeds Home, with inner-circle priority, elapsed rhythm, recent-outreach suppression, pause and snooze; the full due list can expand | Works when a rhythm exists. Imported people begin with no rhythm and no invented connection date, so a large untouched import produces few useful invitations |
| Remember what matters | Person pages show a pinned/current note, personal context, dated notes, and history | A note can be read and edited, but a logged conversation has no nearby way to resolve a discussed thread or save the next one |
| Act on an invitation | Home offers Log, Catch-up notes, and Another week; the person page has Reach out and opens system communication apps | Logging is easier to find than beginning contact; the preferred method is displayed in a chooser rather than reducing the decision |
| Give unanswered outreach space | Explicit Reached out moments leave the connection date unchanged and suppress invitations for seven days | The user must separately log outreach after leaving for another app. Opening an app cannot establish that a message was sent or answered |
| Make room for growth and care | One growth card and up to two care cards appear; filters reveal the full sets | Secondary invitations can repeatedly show the same alphabetical people when none are due; that is a limited prompt, not a plan for the relationship |
| Remember important dates | Birthday appears on the day; due/overdue dated threads appear on Home; opt-in notifications are scheduled locally | There is little advance notice for a card, gift, trip, or planned catch-up. Old unresolved threads can occupy the top of Home indefinitely |
| Keep the journal safe | Atomic local writes, local previous-save recovery, frozen legacy upgrade coverage, complete JSON export/restore | Export is manual; moving or losing the phone before exporting can lose newer context. Backup readiness is not visible during ordinary use |

## Approved first iteration

### 1. Turn the main invitation into an easy contact action

On the featured Home card, offer **Reach out to [name]** alongside **Log a moment**. Keep the factual reason, personal note, and snooze. Reach out should show the chosen preferred route first and keep other routes available. When there are multiple numbers or emails, show a labeled choice rather than guessing. With no saved method, open the contact-method editor.

On returning from the external app, offer a dismissible, optional choice: **We connected**, **I reached out**, **Nothing to record**. The app must never interpret opening Messages, elapsed time outside Plenara, or returning to the foreground as proof of contact. A draft should survive interruption without creating history; the user confirms any moment. Avoid asking again after a dismissed handoff.

This expands the build-1007 design’s global Log and person-specific Log with an initiation path. Both logging paths remain part of the approved design. Cost: a shared contact-action component, return-state handling, cancellation tests, and accessibility verification. No server, scraping, message access, or new paid dependency.

### 2. Make opt-in rhythms easy to establish

After importing, offer **Choose who you’d like a rhythm with** and **Not now**. Start with nobody selected and no cadence chosen. Show a searchable list, then let the user apply one explicitly chosen interval to selected people, with per-person adjustment available. Display which selected people already have rhythms, and leave those untouched unless the user explicitly includes them in a replacement action.

An unknown last contact remains unknown. **Start from today** sets the reminder anchor without creating a moment. A separate optional **Roughly when did we last connect?** sets the existing approximate starting date. This can reuse the current cadence and anchor fields without changing contact identity or classification.

Home’s zero-rhythm state should explain what is missing and open this chooser directly. It should not describe a fresh import as caught up merely because no rhythms exist. Cost: one small setup flow and atomic bulk-save/undo semantics. Benefit hypothesis: less setup work before the app can surface the people Luis actually chooses to remember.

### 3. Carry conversation threads forward without making logging slower

After saving a moment, offer a compact optional next step: **Keep something for next time**. Also show the person’s pinned or due threads with **Keep**, **Resolve**, and **Later**. Resolve clears the follow-up date and optionally unpins the thread; the note remains in the journal. Later asks for a date and changes only that thread. Dismissal saves nothing extra, and a zero-text moment remains a fast operation.

The existing note editor already holds text, pinning, archiving, and a follow-up date. Reuse those fields rather than introducing tasks or a second history. Cost: a post-save surface and careful preservation of existing note content; no AI or schema change required for this version. Benefit hypothesis: old prompts remain useful and the next conversation starts with real context.

## Other credible options

Costs below describe relative engineering and ongoing complexity, not a delivery-time or spending promise.

| Option | Benefit | Real cost or tradeoff | Recommendation |
| --- | --- | --- | --- |
| Keep the current product; ship only correctness fixes | Smallest change; current workflows remain familiar | Users still do the rhythm setup and follow-through themselves | Valid conservative option; less help with the stated relationship goal |
| Action + opt-in rhythm setup + thread completion | Improves the full invitation-to-contact loop using existing data | Several coordinated UI states; external-app return must remain optional and truthful | **Recommended first iteration**, with action and setup implemented before the optional thread step |
| Upcoming dates and specific contact plans | A quiet next-two-weeks view can help prepare for birthdays or agree a call time | Date editing, cancellation, notification lead times, and home prioritization; must distinguish plans from completed contact | Strong second increment after the first choice is approved; a separate “plan” entity is justified only if dated notes prove inadequate |
| More useful growth/care browsing | A See all entry and deliberate selection prevent a tiny alphabetical subset becoming the whole experience | Another queue can feel like obligation; automatic rotation can hide someone unexpectedly | Keep explicit user choice and explain ordering; do not turn Needs care into urgency |
| Backup readiness or private iCloud sync | Reduces loss of personal context during phone replacement | Manual reminder is modest; true sync adds conflicts, deletion propagation, recovery, account availability, and multi-device testing | A gentle manual-backup status is a smaller option; evaluate sync separately before changing the storage architecture |
| Notification/widget expansion | Reminders can reach the user without first opening the app | Lock-screen privacy, scheduling limits, additional extension lifecycle, and more interruption; a notification does not establish meaningful contact | Prefer making the existing weekly invitation useful before adding surfaces |
| Relationship scores, streaks, or mandatory targets | Clear numerical feedback | Optimizes countable logging; can imply emotional knowledge the app does not have | Do not choose for this product direction; Luis can revise that direction explicitly |
| AI-written messages or automatic summaries | Could reduce writing effort for some people | Personal-data exposure, recurring inference cost, authenticity and correction work; journal notes alone provide incomplete context | Not needed for the recommended iteration; any paid API or new data boundary needs a separate decision |
| Read messaging history or automatically infer contact | Less manual recording | Platform access constraints, privacy boundary, uncertain interpretation of “meaningful connection” | Do not choose; keep confirmation in the user’s hands |

No excluded vendor is required to deliver these options. An open-ended AI provider selection is not part of this proposal; any future selection must show relevant options and mark Musk-associated vendors excluded by Luis’s vendor policy.

## Decision

Luis chose the first iteration as a coherent product change: direct contact from Home, explicit optional rhythm setup, and an optional thread step after logging. He also chose shared social-event logging with multiple attendees and a description. Upcoming-date views, sync, widgets, AI, and other alternatives remain comparison options rather than part of this approval.

Implementation should retain the five optional independent relationship attributes, the current ranking policy, and no automatic notification from feeling. Any new field would need old/new decoding and upgrade preservation before adoption. The recommended first iteration can mostly reuse existing data; a persistent handoff draft should stay outside confirmed history.

## How to judge the approved implementation

Use fictional simulator journeys to establish that someone can import, deliberately choose a rhythm, contact a person from Home, return without creating false history, confirm outreach or a connection, and preserve or complete a thread. Exercise cancellation, a missing contact method, multiple methods, failed saves, restoration, large text and dark appearance. Verify reopening and the frozen old-journal fixture.

Product effectiveness is a separate question from passing tests. The useful feedback is whether Luis can act on a relevant invitation with less effort, find the right context, and avoid repeated stale prompts. More logged moments alone would not establish better relationships. The app should need no analytics service or emotional score to answer those questions through use.
