# Improving Home people priorities

November 25, 2026. Review requested by Luis and performed with GPT 6.2 Astra, with independent source cross-checking. Luis approved the compact, filterable Home direction on November 25, 2026. The [current product design](../../design/relationship-app.md#home) owns the adopted behavior; this review preserves the findings and options considered.

Plenara currently answers two different questions on Home: who is due under a reminder rhythm, and who has been marked Grow closer. When little history or reminder setup exists, the first list can be empty and the second can choose the first name alphabetically. That can put Aaron ahead of close friends and family without any evidence that he needs attention more.

The recommendation is to add a useful starting list based on the closeness Luis has already chosen, preserve factual reminder scheduling, and make the reason for each invitation explicit. Missing interaction records mean unknown contact history, not that a conversation has never happened.

## Why Aaron can appear

The actual Home screen calls both selection paths in [HomeView.swift](../../ios/Plenara/HomeView.swift), lines 51–74.

| Home section | Actual selection | Consequence with little history |
| --- | --- | --- |
| Time to connect | A person needs an enabled rhythm, a known connection or stored reminder start, and enough elapsed days. Eligible Inner circle people come first. Other people rank by elapsed time divided by their chosen interval; exact ties use closeness, Grow closer, then stable identity. | A close friend or family member without a rhythm or starting date is absent, regardless of how important they are. |
| Make a little room | Only people marked Grow closer qualify. A remaining due grower is preferred; otherwise the first eligible name alphabetically wins. | Aaron can beat a closer person by name alone. A close friend marked Keep it steady cannot appear here at all. |
| A little care | People marked Needs care, alphabetically, with duplicate and suppression checks. | This is another optional list, not a measure of reminder urgency. |

The first path is [Journal.rankedSuggestions](../../ios/Plenara/Models.swift), lines 148–170. The second and third are [Journal.contextualSuggestions](../../ios/Plenara/Models.swift), lines 172–184. Family is not a ranking input in either path. Nearby changes the growth card's wording, not the selection order.

This explains a reproducible route to the reported behavior. It does not establish which card Aaron occupied or what is saved in Luis's private journal. A Grow closer badge can also appear on the main reminder card, so the badge alone does not identify the path.

## Other gaps in the queue

**Successful contact does not give the optional growth card a break.** The common eligibility check handles pause, snooze and recent unanswered outreach. A connected moment resets the due reminder but does not suppress the optional growth invitation. Someone contacted today can immediately reappear there. See [Models.swift](../../ios/Plenara/Models.swift), lines 120–135 and 172–184.

**The empty state can imply more knowledge than the app has.** If any rhythm exists but no one qualifies, Home says “Room to breathe” and “No one is due for a reminder.” It does not distinguish people whose rhythms have not elapsed from important people with missing setup. The separate setup button is generic. See [ReconnectionSection.swift](../../ios/Plenara/ReconnectionSection.swift), lines 25–31, and [HomeView.swift](../../ios/Plenara/HomeView.swift), lines 76–78.

**The remaining list is available, but the same people can dominate.** Only the first three due people show by default. The complete list can expand, but unresolved higher-ranked people keep their position. The growth fallback is also stable alphabetically. Expanding the due list changes which people are excluded from the growth card, so merely expanding can replace or remove that secondary invitation.

**Setup repeats the alphabetical bias.** The rhythm setup list is alphabetical and shows existing rhythm labels, without grouping close people first. This makes the work of turning important relationships into useful reminders harder than necessary. See [RhythmSetup.swift](../../ios/Plenara/RhythmSetup.swift), lines 13 and 38–50.

**An old setup date can make a newly enabled rhythm due immediately.** Source tracing found that the single-person rhythm editor sets a missing reminder start on Save even when the rhythm is Off, and retains that date when a rhythm is enabled later. Saving Off on November 1 and choosing weekly on November 25 can therefore use November 1 rather than the promised start from today. This is a separate source finding, not a UI-reproduced explanation of Aaron. The proposed correction is to start the clock on the explicit Off-to-On transition when contact history is unknown, while preserving legitimate existing schedules. See [Editors.swift](../../ios/Plenara/Editors.swift), lines 128–131.

## Recommended behavior

1. **Provide a starting list before enough history exists.** Show a clearly labeled invitation such as “Start with your closest people,” led by Inner circle, then Close. Include people whose intention is Keep it steady or unset; maintaining an important relationship should not require marking it for growth. If no such candidate is eligible, use explicitly labeled Family with unanswered closeness as a gentle fallback before a generic growth idea. A relative explicitly marked Casual stays Casual. If nothing is classified, offer a skippable “Choose your closest people” prompt instead of an arbitrary contact. A starter invitation must not silently enable a rhythm, invent a connection, or claim anyone is overdue.

2. **Make setup personal and short.** From each starter card, offer “Connected recently,” “Roughly when?” and “Choose a rhythm.” “Connected recently” must ask for a date or approximation before saving; it must not assume today. Group rhythm setup by closeness and show Family labels. Keep reminders off until explicitly chosen. Someone who chooses to start reminders today should see that starting point explained, even though no connection was recorded. Decide starter eligibility per person, so logging one moment does not hide every other relationship still needing a starting point.

3. **Keep due reminders factual and predictable.** Preserve the current Inner circle precedence and chosen intervals initially. Among other due people, the current elapsed-proportion policy can put a much-later Casual contact ahead of Close; that is deliberate policy, distinct from the alphabetical growth problem. Changing all due ranking to strict closeness bands would reduce that behavior but could keep casual friends hidden indefinitely.

4. **Use one selection plan for Home.** Compute each person's reason, eligibility, suppression and placement once, then present due reminders, starter invitations and optional growth/care ideas with different labels. Treat a due grower as part of the due list, rather than giving a fourth-ranked due person an extra growth slot. Keep everyone in the complete due list available. Expanding it should not silently replace the optional idea.

5. **Show why this person appears and make moving on easy.** Examples: “Inner circle · Last contact not set,” “Your weekly rhythm is ready,” or “You chose Grow closer · Optional idea.” Replace alphabetical growth priority with closeness followed by a stable tie-break. Offer “Another person” or a temporary dismissal that advances to another candidate at the same priority; do not shuffle the main due queue every day.

6. **Respect a completed connection everywhere.** Add a seven-calendar-day recent-connection cooldown for optional ideas, including every participant in a shared social event. An actually due shorter chosen rhythm still belongs in the reminder list. Keep unanswered outreach distinct from a reciprocal conversation, and preserve existing pause and snooze behavior.

For the starter list, an unanswered last-contact date or an unchosen rhythm is unfinished context, not urgency. Apply pause, snooze, recent-outreach and recent-connection suppression, and exclude everyone already in the due queue. A person with known contact and a configured, not-yet-due rhythm does not need a starter card. Respect a declined setup prompt rather than asking on every visit. The current `cadence = 0` does not distinguish “never configured” from “deliberately off”; remembering that distinction or a dismissal needs optional state with upgrade preservation.

Placement should also be explicit. Keep dated reminders separate. A due Inner circle person retains the leading invitation. Otherwise an eligible Inner circle or Close starter can be the first personal invitation, with the due queue immediately below and clearly labeled. For example, Zoe or Mei can lead as a starter while casual Aaron remains first in the factual due list. Family fallback and generic growth ideas follow actual reminders. This changes Home's composition, without pretending an unknown conversation date outranks an elapsed chosen interval mathematically.

## How family should count

Luis specifically expected closer friends or family. Family is already a supported classification, but it is currently only descriptive for these selectors. There are three credible approaches:

| Approach | Benefit | Cost and recommendation |
| --- | --- | --- |
| Closeness alone, with Family visible and easy to filter | Uses Luis's direct statement of importance and avoids assuming every relative is close | Simple, but a family member with unanswered closeness still gets no help. Insufficient by itself for the reported expectation. |
| Closeness first, Family as a fallback when closeness is unanswered | Makes family available when history and closeness provide little direction | Recommended for starter invitations. Never outrank an explicitly Inner circle or Close person, override an explicit Casual classification, or change reminder timing. |
| Family always precedes friends | Most directly guarantees family exposure | Can put a distant relative ahead of a close friend and substantially changes existing policy. Not recommended as a blanket default. |

The current design says “Family does not automatically mean inner circle” at [design/relationship-app.md](../../design/relationship-app.md), lines 205–208. That existing written choice is changeable. It should not be used to dismiss Luis's expectation. The recommendation uses Family as a starting hint without relabeling someone Inner circle or overruling Luis's explicit closeness choices. A stronger family-first policy remains a visible alternative in the table.

## Options and tradeoffs

| Option | What it solves | What it leaves | Decision |
| --- | --- | --- | --- |
| Change only the alphabetical growth fallback | A closer grower can beat Aaron | Close steady relationships still disappear when reminders are not configured; recent-contact repetition remains | Too narrow on its own |
| Add the starter list, useful setup, shared selection reasons and optional cooldown | Handles the reported first-use situation while retaining chosen reminder semantics | Adds Home states and requires old-journal and interaction verification; dismissal persistence may need an optional field | Recommended |
| Use one weighted score for closeness, family, elapsed time and growth | Produces one sortable queue | Arbitrary weights can hide why someone wins and give unknown history false precision | Avoid for this iteration |
| Rank every due person strictly by closeness | Makes Close always precede Casual | Lower groups may never surface, even far beyond their chosen rhythm | Separate policy decision; not required to fix the cold start |
| Rotate every day | More people get exposure automatically | Important reminders can disappear without action; conflicts with predictable ordering | Prefer deliberate next-person control |

The approved design currently specifies “optional alphabetical growth ideas” and “There is no daily rotation” at [design/relationship-app.md](../../design/relationship-app.md), lines 227–238. Replacing the alphabetical fallback requires a deliberate design change. Deliberate next-person controls can preserve the main queue's no-rotation behavior. This review leaves the approved design intact until the proposed behavior is chosen.

## Verification and implementation boundary

The review traces the shipped native selection functions and their tests. Existing [RankingTests.swift](../../ios/PlenaraTests/RankingTests.swift) intentionally verifies that a person with neither a known connection nor a reminder-start anchor is excluded from due reminders, that unknown contact can become due after an explicit reminder start matures, and that due growth outranks an optional alphabetical idea. Those tests describe the present policy; passing them does not establish that the first-use experience is useful.

### Synthetic results from the actual selectors

Astra compiled the production `Models.swift` and `WorkflowModels.swift` with `swiftc -O` and exercised six fixed-date scenarios. The fictional people were Aaron (Casual friend, Grow closer), Zoe (Inner circle friend, Grow closer), and Mei (Close family, Keep it steady). The probe calls Home's selection functions and applies its visible-person exclusions; it does not render the screen or inspect Luis's data.

[Probe source](../../verification/home-priority-review/main.swift), [observed output](../../verification/home-priority-review/output.txt), and [compiler, commands and source hashes](../../verification/home-priority-review/provenance.json) preserve the reproduction against reviewed commit `7c3015682bda70b39fda3ce356b5c3dd52755dc0`. A second optimized run reproduced all six results.

| Scenario | Due order | Optional growth person |
| --- | --- | --- |
| No history or rhythms | Empty | Aaron |
| Same state seven days later | Empty | Aaron |
| Connected with Aaron today | Empty | Aaron |
| Unanswered outreach to Aaron today | Empty | Zoe |
| Aaron has a weekly reminder started 21 days ago; Mei last connected 31 days ago on a monthly rhythm | Aaron, Mei | Zoe |
| Add a due Inner circle rhythm for Zoe | Zoe, Aaron, Mei | None, because all are already visible |

Aaron's contact history remains unknown in the reminder-start scenario. The queue can rank him using an explicitly chosen scheduling start without claiming a conversation occurred. This is another reason to show the actual scheduling reason. For real records, wording such as “Last logged connection” also acknowledges that unlogged conversations may exist.

Before implementing the proposal, cover the actual Home path with fictional people: no history or rhythms; only one partially configured person; close steady friends alongside casual growers; family with and without closeness; recent connected versus unanswered outreach; paused/snoozed people; shared social events; more than three due people; expansion; explicit dismissal; and save/reopen. Prove that changing a name cannot change relationship priority, and that adding one interaction does not falsely complete setup for everyone. Preserve old journal upgrade/edit/reopen coverage and atomic saves for any new optional fields.

The unchanged app's required `bash tool/precheck.sh` baseline passed: 61 native Release tests, the separately repeated Contacts-import test with broad access denied, six historical browser journeys, six TestFlight tooling tests, two workflow-calibration tooling tests, and all 926 archived-file checks. [Baseline results](../../verification/home-priority-review/baseline-checks.json). The dedicated simulator and test processes were stopped after verification. These results describe the current app, not acceptance of the proposed behavior.

No app code, private journal, reminder setting or approved design is changed by this report. No paid inference or physical-device verification is part of the review.
