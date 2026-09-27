# Plenara guiding workflow implementation

Luis approved the [Astra review](2026-09-26-first-principles-review.md): “Please implement the changes suggested by the Astra design review.” This record describes the resulting implementation, its evidence and its operational limits. Current authority is [Spec 17](../planning/specs/17-living-planner.md).

## What changes in everyday use

Open Plenara to Today: a person to make space for, one actionable commitment, and a practice that fits your chosen rhythm. People, Tasks, and Routines remain one tap away. Talk to Plena and Message Plena have visible labels and follow you onto pushed detail screens. Voice and typing share one conversation and are available together. The latest dialogue remains there after reopening.

Tell a story or ask for help. Plena’s GPT guide can look up relevant people, commitments and routines, ask a question, and propose a combined set of updates. An expression such as “I feel disconnected…” stays a conversation; it does not silently become a mood log. Conversation does not require creating records.

Proposed updates appear in a receipt. Edit fields, remove unwanted items, or dismiss the whole proposal. Applying validates all selected changes and saves one atomic execution with undo. A receipt survives restart; its execution identity prevents applying it twice after an interrupted clear. Changed underlying records require a refreshed proposal. No direct sending or deleting is exposed to the model.

“No recorded update” means unknown. “We already caught up” records your acknowledgement, reduces nagging for your chosen rhythm, and does not invent an interaction date. Existing contact circles, independent proximity, actual dated interactions, and follow-up tasks remain useful.

Routines offers repeated practices and guided sequences. A practice can hold your reason, cue, normal version, minimum version, weekly rhythm and preferred days. Start, Done, Smaller version and Skip are distinct actions. A deliberate skip does not count as completion; a minimum version does. A missing report is unknown, and consecutive-day streaks no longer judge success.

## Selective evidence, without surveillance

Bring selected context into the conversation using the link button. Paste a message or note, or explicitly browse Calendar and Reminders under separate iOS permissions. Browsing remains local; choosing an item prepares a draft. Sending that draft is a separate action. Calendar entries are plans, not proof of attendance, and source text is treated as untrusted quoted evidence.

Shortcuts exposes Open Plena and Capture with Plenara. The latter accepts selected text and opens the app for review. A pending capture uses this device’s unlock-only keychain and cannot be overwritten by another capture. To use selected text from another app, create a Shortcut with Capture with Plenara taking Shortcut Input and enable that shortcut in the Share Sheet. No blanket Messages history or iPhone call-log API is claimed. No Mac history collector, background message monitoring, or automatic source ingestion is enabled.

Chosen reminder notifications use generic lock-screen copy and are silent by default. Tap or Discuss with Plena leads to the relevant conversation. This change introduces no daily notification campaign or catch-up debt.

## Connection, cost and storage

GPT is a separate optional connection. Settings → Plena guide takes an OpenAI API key, explicit context consent, and a monthly dollar limit. ChatGPT/Codex subscriptions and an existing Anthropic key do not supply this API connection. Zero pauses GPT; local actions remain available. Existing Anthropic command/authoring features retain their separate credential and admission gate.

The guide sends bounded recent dialogue and relevant contact, contact_fact, interaction, task, reminder, habit, habit_checkin, routine and routine_step records. It excludes journal, mood, diagnostics, and contact phone/email/system identifiers. A user-written note or selected message may still contain sensitive information. No context is claimed automatically nonsensitive merely because it has an allowed type.

Responses uses `store:false`; this does not promise zero provider abuse-monitoring retention. See [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state). The verified model is [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol), using [function tools](https://developers.openai.com/api/docs/guides/function-calling), with its full output allowance rather than an artificial character-dialogue length restriction.

Every request, including tool continuations, reserves its possible cost before HTTP. Measured usage settles the reservation; uncertain failures retain it. Exhaustion, corruption, clock rollback or inability to persist block another request. This is a per-device budget, not an account-wide cap across other apps/devices. The conservative full-output reservation means remaining budget must cover roughly $1.28 of possible output plus input before a request, even though typical actual requests cost much less. No live paid evaluation occurred without separate billing authorization and a configured credential.

Planner records and the bounded device-local conversation ledger remain readable JSON under the existing storage model. This change does not claim full database encryption. Selected Shortcut captures and API keys use secure device storage. Guide turn traces omit conversation and record content; internal native speech hypotheses retain their separately disclosed diagnostics policy.

## Screens

These renders use production widgets, synthetic records, real fonts and a phone-sized surface; they are implementation evidence, not predictions about Luis’s private data.

- [Today](2026-09-26-guide-implementation-evidence/01-today.png)
- [People](2026-09-26-guide-implementation-evidence/02-people.png)
- [Routines](2026-09-26-guide-implementation-evidence/03-routines.png)
- [Conversation](2026-09-26-guide-implementation-evidence/04-conversation.png)
- [Review receipt](2026-09-26-guide-implementation-evidence/05-receipt.png)

## Verification

The expressive-interception regression was calibrated against the actual old dispatch behavior: routing the help-seeking sentence back through the old interpreter fails the test; restoring the guide passes. Engine tests exercise real temporary files, mixed atomic receipts, forward references, stale/missing references, receipt restart/replay, undo, excluded context, relationship acknowledgement, practice outcomes and a local HTTP Responses fixture. No mocked-provider test is represented as an evaluation of GPT’s conversational quality.

Widget tests exercise default navigation, voice-plus-text access, person detail focus, resumable replies, receipt application/removal/undo, selected-text drafts, background cancellation, startup repair, large text and explicit guide consent/secure credential handling. Existing direct editor, planner, reminder, migration and capability contracts remain checked.

Native XCTest also exercised both App Intents and secure capture storage, plus the existing contact-picker bridge. All four passed. Its overwrite protection was calibrated against an actual overwrite mutation: the native assertion failed because the second write did not throw; production protection was then restored.

The iOS real-engine render/interaction suite passed all eight checks on the dedicated iPhone 17 Pro simulator. Calendar and Reminders were also exercised through the real native bridge with simulator permissions pre-granted; the OS permission-choice sheets were not evaluated. The receipt-related-person display regression was separately calibrated by restoring the omitted field and observing its expected assertion failure; the restored production display passed with all 13 focused guide/settings tests.

During the iOS interaction run, 38 one-second RSS samples ranged from 297–486 MiB and ended at 368 MiB; no ballooning threshold fired. This brief simulator observation is not proof against a slow leak or physical-device resource limits. No paid live GPT call or model comparison was performed: conversational quality and provider latency remain unmeasured without Luis’s key and billing authorization.

The final `bash tool/precheck.sh` completed ALL GREEN: 2,073 engine tests, 183 app tests, four external-channel checks and eight macOS real-engine interaction/render checks passed. The existing conformance baseline remains 24 passing / 36 explicitly skipped of 60; app tests retain four existing skips. Analysis is clean, seed assets match, documentation checks pass, and deterministic-core/product/transport coverage floors pass (95.7% / 89.1% / 85.6%). Native XCTest’s restored production run passed all four tests, without skips. macOS RSS samples remained approximately 343–412 MiB through the observed interaction window. Foreground activation was unavailable on the locked Mac; the real engine and automated interactions still completed successfully.
