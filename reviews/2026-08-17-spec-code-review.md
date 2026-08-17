# Plenara specification and code review

**Review date:** 2026-08-17  
**Revision reviewed:** `195f21fc75efaeaa177365324c0731766c36bd81` (`main`, equal to `origin/main`)  
**Scope:** the locked research baseline; every planning spec and companion review/assessment; the v0 Dart engine, Flutter app, seed data, tests, integration harnesses, release scripts, and current work capsule. This review did not change production code or specifications.

## Executive verdict

Plenara has a substantial, unusually well-tested deterministic core. The full credential-scrubbed gate passes, the host app builds, 1,828 engine tests and 97 Flutter tests pass, the real-engine desktop render smoke passes, global engine line coverage is 91.1%, record writes are atomic per file, definition writes are atomic, corrupt records are contained, and the declarative skill validator has meaningful depth.

It is not, however, conformant with the architecture its specifications describe. The largest gaps sit exactly under the product's trust proposition:

1. A test can print a live API credential into test output. This happened during this review. The credential must be rotated immediately.
2. The wired Settings export shares raw, content-bearing logs even though Spec 11 requires a derived, shape-redacted diagnostic bundle.
3. The distributed Flutter app still stores the API credential as plaintext in its Documents container, despite the spec calling secure-store migration a release blocker.
4. Act-then-describe has only a volatile in-memory undo ring. There is no durable execution record, crash resume, or all-or-nothing multi-record recovery.
5. Schema migration can mark an incompatible record current without applying its declared rename/retype/removal steps.
6. The intended local semantic router is not in the product. Retrieval is disabled by default, implemented only as a localhost development service, and consulted only after the cloud path rather than before it.

The right interpretation is not “the project is broken.” The shipped slice works for its corpus-covered paths. The issue is that several design documents describe target systems as if they were current, while current code has grown into a strong but narrower dogfood product. Release/readiness decisions should use the wired behavior documented here, not status labels or declarations.

### Severity scale

- **Critical:** a live secret or user data can escape, or immediate action is required.
- **High:** credible data-loss, privacy, safety, or core-product correctness failure.
- **Medium:** material functional/spec drift, misleading failure behavior, or a gate that can give false confidence.
- **Low:** packaging or documentation drift that can cause operational mistakes but does not currently corrupt user data.

## Scope and method

- Read the research baseline and the full planning suite: Specs 01–16, the 05a corpus/traces, gap register, Fable/cross-spec reviews, and storage/sync assessment.
- Inspected all engine/app source files, seed type/skill declarations, tests, scripts, platform manifests/entitlements, and current git/work-capsule state.
- Traced declarations to composition roots and call sites. Findings explicitly distinguish a wired product path from an interface, comment, or target-only spec.
- Ran the repository precheck, analyzer, import lint, engine tests with coverage, Flutter analyzer/tests, macOS debug build, real-engine integration smoke, secret scan, and conformance ratchet.
- Calibrated the analyzers and test runner with temporary known-good and known-bad files before treating their output as evidence. The bad states failed and the good states passed; the temporary files were removed.
- Reviewed generated outputs for credential material before completing this report. No credential value is reproduced here.

## Prioritized findings

### SC-01 — Critical — the config test is non-hermetic and can print a live API credential

**Wired behavior.** Configuration always prefers the process environment over the supplied test file: [`config.dart:87–96`](../v0/lib/config.dart#L87). The atomic-config test writes a dummy credential, then compares `loadConfig(...).apiKey` to that dummy: [`data_edit_test.dart:86–90`](../v0/test/data_edit_test.dart#L86). When a developer has the live environment variable set, the matcher reports the unexpected actual string verbatim.

**Observed impact.** An ordinary `bash tool/precheck.sh` failed at this test during the review and emitted the live credential into tool output. Re-running the same gate with the credential removed from the environment passed. This is test non-hermeticity rather than a product-logic failure, but the disclosure is real.

**Required response.**

1. Rotate the exposed Anthropic credential immediately. Rotation requires the credential owner; it cannot be completed by a code review.
2. Change the test seam so config tests receive an explicit environment map or a `preferEnvironment: false` option.
3. Never assert or interpolate a secret-bearing value. Assert only presence, source, or a one-way fingerprint generated inside the test.
4. Make the precheck begin by clearing credential variables for all hermetic steps, and add a log-output canary test proving failures cannot serialize a credential.

### SC-02 — High — “Share diagnostics” sends raw utterances, responses, paths, and exception text

**Wired behavior.** The app logs the exact utterance and up to 140 characters of the response on every turn: [`main.dart:489–507`](../app/lib/main.dart#L489). Essential logs remain enabled in release builds: [`app_log.dart:17–29`](../app/lib/app_log.dart#L17). Settings reads every `.log`, concatenates it without redaction, writes a temporary text file, and hands it to the platform share sheet: [`settings_view.dart:245–288`](../app/lib/settings_view.dart#L245).

**Spec contract.** User content and exception messages must never leave the device, and outbound structures must have no arbitrary-string field: [`11-feedback-diagnostics.md:81–102`](../planning/specs/11-feedback-diagnostics.md#L81). The diagnostic bundle must be derived, shape-redacted, previewed with a manifest, and the raw-log option is explicitly declined: [`11-feedback-diagnostics.md:173–203`](../planning/specs/11-feedback-diagnostics.md#L173).

**User impact.** A normal share action can disclose conversations, contact names, personal records reflected in replies, usernames in paths, and exception-interpolated data to any selected recipient. This is a shipped outbound path, not an unimplemented declaration.

**Fix.** Replace `_shareLogs` with a typed `DiagBundle` builder that accepts only closed enums, built-in ids, counts, timings, and shape descriptors. Drop exception messages and home paths, generalize authored ids, show the exact rendered payload before invoking the share sheet, add canaries across every source field, and prune logs after the documented retention window.

### SC-03 — High — the distributed app stores a spendable credential in plaintext, inside a Files-visible container

**Wired behavior.** On iOS/Android, `homeOverride` is the Documents directory: [`main.dart:76–87`](../app/lib/main.dart#L76). Config is written below that home in `.plenara/config.json`, and its own comment confirms plaintext storage: [`config.dart:50–57`](../v0/lib/config.dart#L50), [`config.dart:104–107`](../v0/lib/config.dart#L104). iOS enables both document opening in place and file sharing: [`Info.plist:31–32`](../app/ios/Runner/Info.plist#L31), [`Info.plist:60–61`](../app/ios/Runner/Info.plist#L60).

**Spec contract.** The target is Keychain/DPAPI/Keystore, and plaintext config is “not shippable” and a release blocker for any distributed build: [`08-ai-cost-privacy.md:258–261`](../planning/specs/08-ai-cost-privacy.md#L258), [`08-ai-cost-privacy.md:297–310`](../planning/specs/08-ai-cost-privacy.md#L297). The app is already version `0.12.0+18`: [`pubspec.yaml:21`](../app/pubspec.yaml#L21), and the capsule says TestFlight is live.

**User impact.** Device backups, Files access, same-user processes, or a copied app container expose a credential that can incur spend. The current single-user TestFlight audience reduces reach, not consequence.

**Fix.** Introduce one secure-credential interface, migrate the existing value into Keychain/Keystore/DPAPI, verify the secure write, then remove the legacy plaintext field atomically. Keep plaintext fallback behind an explicit development-only build flag. Rotate the currently exposed credential as part of SC-01.

### SC-04 — High — act-then-describe has no durable execution journal or crash-safe multi-write recovery

**Wired behavior.** The “journal” is a 25-entry in-memory list explicitly described as volatile: [`session.dart:420–427`](../v0/lib/session.dart#L420), [`session.dart:499–500`](../v0/lib/session.dart#L499). A turn mutates the whole in-memory store, pushes an undo entry, then persists each write/delete sequentially: [`session.dart:2608–2638`](../v0/lib/session.dart#L2608). If the third write fails after two succeed, the response says the change “will be lost” on restart even though the persisted prefix survives. Undo itself also replays repository operations sequentially with no failure transaction: [`session.dart:952–962`](../v0/lib/session.dart#L952). Automation approval follows the same execute-then-sequential-persist pattern: [`automations.dart:354–388`](../v0/lib/automations.dart#L354).

**Spec contract.** The execution record is one durable device-local file per in-flight execution, containing frozen inputs, action plan, progress, and before-images: [`02-skill-dsl.md:667–724`](../planning/specs/02-skill-dsl.md#L667). Startup must recover an executing record, and a partial turn must never remain invisible: [`04-architecture.md:735–741`](../planning/specs/04-architecture.md#L735), [`04-architecture.md:769–775`](../planning/specs/04-architecture.md#L769).

**User impact.** The exact multi-record flows that make Plenara valuable—people facts, compound capture, routine creation—can become partly durable after storage failure or process death. Restart loses the only undo record, so the user cannot reliably reverse or even identify the partial turn.

**Fix.** Put every mutation route through a serial execution coordinator. Persist the resolved plan and before-images before the first record write; checkpoint the op index after each atomic record operation; on launch either complete idempotently or reverse the persisted prefix. Keep the existing in-memory ring as a cache over durable recent `done` entries, not the source of truth.

### SC-05 — High — migration can silently strand data while stamping it current

**Wired behavior.** `migrateRecord` only adds current attributes and then writes the target schema version. It deliberately does not apply rename, removal, or type-coercion descriptors: [`migration.dart:1–7`](../v0/lib/migration.dart#L1), [`migration.dart:24–35`](../v0/lib/migration.dart#L24). Startup automatically applies and persists that result for every older record: [`session.dart:615–641`](../v0/lib/session.dart#L615).

**Spec contract.** Breaking changes require a version bump plus an ordered declarative migration chain with renames, coercions, defaults, and removals: [`01-meta-schema-type-system.md:374–440`](../planning/specs/01-meta-schema-type-system.md#L374). A failed record must stay at its old version, be excluded from typed reads, and surface for repair: [`06-data-sync.md:304–326`](../planning/specs/06-data-sync.md#L304).

**User impact.** Rename `cals` to `calories`, for example, and the current code adds `calories: null`, preserves `cals`, then marks the record current. The declared migration can never run later because the version now says it already did. This is silent semantic data loss.

**Fix.** Refuse to advance a record unless a complete contiguous migration chain exists and every step succeeds. Implement the four declared operations in their fixed order, validate the result against the target schema, persist atomically, and retain/surface the old record on any failure. Add destructive calibration tests: each rename/retype/removal test must fail against the current additive-only runner.

### SC-06 — High — startup trusts type files without the registry validation the specs rely on

**Wired behavior.** Startup parses all type definitions directly into a map, creates the interpreter from them, and validates only skills: [`session.dart:600–608`](../v0/lib/session.dart#L600), [`session.dart:649–687`](../v0/lib/session.dart#L649). `validateType` itself checks only that `typeId` and `attributes` have basic shapes, that `valueType` is recognized, and that an entity reference names a `refType`: [`interpreter.dart:448–464`](../v0/lib/interpreter.dart#L448). The authored/template paths call this thin validator, but manual edits and synced files bypass even that at startup.

**Spec contract.** Hydration must parse and validate each definition, register only valid types, then run cross-reference checks and surface degraded definitions: [`01-meta-schema-type-system.md:298–308`](../planning/specs/01-meta-schema-type-system.md#L298). Required invariants include filename/id agreement, positive schema version, unique ids, reference resolution, authoring assessment, presentation eligibility, and automation closure: [`01-meta-schema-type-system.md:310–324`](../planning/specs/01-meta-schema-type-system.md#L310).

**User impact.** A hand edit, conflict copy, or future authored artifact can become active with duplicate attributes, invalid enum definitions, missing metadata, dangling references, or unusable presentation hints. The error appears later as a runtime resolve, migration, or UI failure rather than a repair item.

**Fix.** Implement a real `SchemaRegistry` hydration boundary. Validate filenames and full local invariants before registration; perform the cross-reference pass after all definitions load; keep degraded capabilities inert where specified; expose a structured hydration/repair report. Use the same one validator for startup, template installation, authoring preview, and activation.

### SC-07 — High — the specified local semantic router is not wired, and the implemented fallback order is reversed

**Wired behavior.** Both production composition roots default retrieval off: [`main.dart:127–135`](../app/lib/main.dart#L127), [`main.dart:154–180`](../app/lib/main.dart#L154). The only embedder calls a localhost development server: [`embed.dart:1–28`](../v0/lib/embed.dart#L1). Even when enabled, the router's embedding result is only a suggestion: [`router.dart:464–523`](../v0/lib/router.dart#L464). On a corpus miss, `Session` calls Claude first and consults retrieval only after cloud abstention/failure to word a clarification: [`session.dart:2381–2433`](../v0/lib/session.dart#L2381).

**Spec contract.** The deterministic cascade is corpus → retrieval top-1-with-margin → deterministic slot extraction → Haiku only for a genuine tie, with offline clarify as the floor: [`03-nlu-intent.md:687–695`](../planning/specs/03-nlu-intent.md#L687). The architecture says all common-path free-tier NLU is local: [`04-architecture.md:745–756`](../planning/specs/04-architecture.md#L745).

**User impact.** Novel natural phrasing—the central promise of an uncompromising voice interface—either spends a cloud call or clarifies. Offline users are effectively constrained to corpus wording, and the product cannot learn gracefully from phrasings it never routes. This also amplifies planner discoverability problems: the user has no rich UI fallback and the semantic voice path is absent.

**Fix.** Ship an in-process on-device embedding backend and build the merged capability index during normal startup. Move retrieval before cloud routing and let a calibrated top-1/margin result dispatch. Keep corpus matching first, slot resolution deterministic, and cloud as the measured residual only. Treat index unavailability as a surfaced degraded mode, not the default product mode.

### SC-08 — Medium — cloud NLU has no app-side rate/cost guard

**Wired behavior.** Every corpus miss reaches `routeResidual`; the HTTP seam checks only credential presence and provider/network response kinds. It has token counters but no hourly/daily admission counter: [`claude.dart:343–405`](../v0/lib/claude.dart#L343), [`claude.dart:473–500`](../v0/lib/claude.dart#L473).

**Spec contract.** Cloud NLU must be capped inside `ClaudeClient` so no call site can bypass it: [`04-architecture.md:653–658`](../planning/specs/04-architecture.md#L653). Spec 08 also says the BYOK gate and cost guard live inside the seam: [`08-ai-cost-privacy.md:297–302`](../planning/specs/08-ai-cost-privacy.md#L297). The old 20/hour value is itself marked for measured resizing, but “no cap” is not an allowed resolution.

**User impact.** Retrieval-off cold start makes almost every novel phrase billable. A loop, UI retry, or enthusiastic onboarding session has no local bound on spend or egress.

**Fix.** Add a single persisted/session-aware cloud admission controller inside the seam, with a burst budget and daily ceiling derived from measured beta use. Return the existing typed `rateLimited` value locally before creating a request, and expose actual usage in Settings.

### SC-09 — Medium — interpreter schema enforcement accepts invalid typed values

**Wired behavior.** The write validator coerces `number` and `decimal` to Dart numbers, booleans from a few strings, and passes text, entity refs, dates, datetimes, tags, attachments, enums, durations, and JSON through unchanged: [`interpreter.dart:955–990`](../v0/lib/interpreter.dart#L955). It checks required fields only for creates, not nulling on update, and does not reject unknown fields: [`interpreter.dart:993–1019`](../v0/lib/interpreter.dart#L993). Manual boolean editing maps every unrecognized string to `false`: [`session.dart:1126–1148`](../v0/lib/session.dart#L1126).

**Spec contract.** Decimal is an exact base-10 string on disk, enum values must be declared members, dates/datetimes have fixed storage forms, durations are integer seconds, and entity refs are typed ids: [`01-meta-schema-type-system.md:69–90`](../planning/specs/01-meta-schema-type-system.md#L69). Resolve must validate all of these and prevent a required attribute being nulled on update: [`02-skill-dsl.md:620–634`](../planning/specs/02-skill-dsl.md#L620).

**User impact.** Authored skills can store out-of-enum strings, malformed dates, wrong entity ids, floating-point money, or arbitrary JSON shapes while still producing a success sentence. Later queries, aggregation, migration, and archetype rendering then operate on corrupt-but-accepted data.

**Fix.** Centralize value validation in a total schema codec shared by interpreter writes and manual edits. Validate unknown fields, exact decimal serialization, enum membership, ISO/date rules, integer duration, tag/list shape, attachment path containment, entity existence/refType, and required-null updates before the plan is executable.

### SC-10 — Medium — several mutation paths can change memory and then tell the user “I didn't do anything”

**Wired behavior.** Reference delete/complete/correct and undo mutate the store and journal before synchronous repository operations, with no local error translation: [`session.dart:952–1074`](../v0/lib/session.dart#L952). The outer catch converts any exception to “I didn't do anything”: [`session.dart:1713–1719`](../v0/lib/session.dart#L1713). A disk failure can therefore leave memory changed and undo state consumed while the response claims no action. Manual edit/delete mostly improve this, but their post-success `logTurn` calls remain outside a catch: [`session.dart:1184–1221`](../v0/lib/session.dart#L1184).

**Spec contract.** Errors are translated at boundaries into caller vocabulary; raw filesystem exceptions never escape, and the surfaced statement must match the applied state: [`04-architecture.md:731–737`](../planning/specs/04-architecture.md#L731).

**Fix.** Route every mutation—including reference commands, correction, manual edits, automation approval, and undo—through the coordinator from SC-04. Return a typed result containing applied/persisted/recoverable state. Remove exception strings from user responses and never use the blanket “nothing happened” sentence after mutation begins.

### SC-11 — Medium — long cloud work blocks the only interactive turn instead of detaching

**Wired behavior.** `Session.handle` awaits generative calls inline: [`session.dart:2267–2300`](../v0/lib/session.dart#L2267), and authoring awaits up to two 120-second attempts inside the same call: [`session.dart:2820–2873`](../v0/lib/session.dart#L2820). Flutter holds `_busy = true` until that future returns and ignores new sends: [`main.dart:471–499`](../app/lib/main.dart#L471).

**Spec contract.** Authoring and generation must emit a `Detached` event, release the turn lock immediately, and report through an operation center: [`04-architecture.md:662–674`](../planning/specs/04-architecture.md#L662).

**User impact.** A voice-first assistant becomes unavailable for 10–120 seconds during its most interesting paid features. The animation may show thinking, but barge-in or a new planning command cannot progress.

**Fix.** Add an operation center with stable operation ids, cancellation/discard semantics, persistence across app backgrounding, and result delivery. Keep the interaction queue available while the operation runs.

### SC-12 — Medium — the current iPhone data path is local Documents, not the user-chosen synced folder

**Wired behavior.** Mobile config always overrides a persisted `dataDir` with `<Documents>/Plenara`: [`config.dart:82–89`](../v0/lib/config.dart#L82). `StorageRepository` exposes no watcher or merge API: [`storage_repository.dart:14–43`](../v0/lib/storage_repository.dart#L14). Records have per-field stamps and tombstones, but no version vector, no merge function, and no external-change reconciliation: [`store.dart:121–174`](../v0/lib/store.dart#L121).

**Spec status.** Spec 06 says the user-chosen cloud folder is the transport: [`06-data-sync.md:64–80`](../planning/specs/06-data-sync.md#L64). It deliberately stages the merge engine for P2, but also states the v0 format should already carry its full future metadata: [`06-data-sync.md:28–40`](../planning/specs/06-data-sync.md#L28), while its own delta table acknowledges the missing version vector/watcher-era work: [`06-data-sync.md:404–420`](../planning/specs/06-data-sync.md#L404).

**User impact.** Current iPhone data survives ordinary app use but not reinstall, device loss, or a second-device workflow through the promised user-controlled sync transport. The architecture's strongest ownership story is not yet a product behavior.

**Fix.** Be explicit in UI/onboarding that current iOS storage is device-local. Then implement the iOS document-provider/folder-bookmark flow, storage watch/reconcile seam, record version vectors, pure merge with conflict stashing, and a real-device cold-bootstrap spike before claiming sync or multi-device readiness.

### SC-13 — Medium — planner information architecture and weekly review do not implement the functional spec

**Wired behavior.** A task contains only description, due date, completion flag, and creation date: [`task.json:1–9`](../v0/data/types/task.json#L1). “List tasks” orders by creation time and speaks only descriptions: [`list-tasks.json:10–38`](../v0/data/skills/list-tasks.json#L10). The wired weekly review collects recent workouts, moods, interactions, and completed tasks, then asks for reflective prose: [`generative.dart:120–180`](../v0/lib/generative.dart#L120).

**Spec contract.** The weekly priority review gathers open tasks and goals, returns keep/defer/drop recommendations, and renders a grouped review card: [`05-functional.md:753–769`](../planning/specs/05-functional.md#L753). The UI checklist is grouped by overdue/today/week/later: [`07-ui-design-language.md:102–106`](../planning/specs/07-ui-design-language.md#L102).

**User impact.** Plenara can capture and recite to-dos, but it cannot represent priority, estimate, project/area, scheduled slot, status, dependency, or rich notes. It therefore cannot help answer “what should I do next?” or perform the specified planning review. Voice-first magnifies this: the sparse data model gives neither speech nor UI enough structure to reveal.

**Fix.** Evolve the task schema and migration chain first, then build a planning projection that distinguishes inbox, next actions, scheduled work, waiting, and someday/deferred. Preserve voice capture as the primary write path, but make planning a persistent visual workspace with direct manipulation and a structured weekly-review result.

### SC-14 — Medium — spoken replies are intentionally hidden despite the always-on subtitle contract

**Wired behavior.** When TTS is available, the app sets the reply display to `null`; only unspoken extras remain: [`main.dart:523–535`](../app/lib/main.dart#L523). Captions clear 1.6 seconds after speech finishes: [`main.dart:546–576`](../app/lib/main.dart#L546).

**Spec contract.** The research baseline says spoken output is simultaneously displayed: [`plenara_research.md:94–105`](../planning/plenara_research.md#L94). Spec 05 notation repeats that guarantee: [`05-functional.md:47–59`](../planning/specs/05-functional.md#L47). Spec 07 requires the assistant subtitle to be always on, to linger four seconds, and to remain in the Conversation Stream: [`07-ui-design-language.md:291–298`](../planning/specs/07-ui-design-language.md#L291).

**User impact.** A missed word, noisy room, hearing difference, or unfamiliar name leaves no visual recovery. The home also lacks the specified lingering Done/Undo threshold and visited Conversation Stream, so the completed action disappears instead of building trust.

**Fix.** Restore simultaneous assistant captions, retain the four-second linger, and keep the most recent Done line with visible undo. Add the Stream/history surface before relying on ephemeral voice output as the planner's only state explanation.

### SC-15 — Medium — the quality gate is broad, but it can still report green over false-green and unclassified behavior

**Evidence.**

- The conformance harness has 60 named cases but currently passes 24 and skips 36. The baseline is only `24`, so the gate protects 40% exact-utterance conformance, not full spec conformance: [`spec05a_test.dart:173–211`](../v0/test/spec05a_test.dart#L173), [`conformance-baseline.txt:1`](../v0/test/conformance-baseline.txt#L1). The test spec still says 20/60 and baseline 21: [`09-test.md:177–189`](../planning/specs/09-test.md#L177), [`09-test.md:222–224`](../planning/specs/09-test.md#L222).
- One test named “session passes existing contact display-names to the router” ignores the turn response and asserts only the captured contacts: [`session_test.dart:750–763`](../v0/test/session_test.dart#L750). During the passing full run its generated turnlog recorded that the turn actually ended in a caught type error at the raw-map `updateAll` call: [`session.dart:2496–2510`](../v0/lib/session.dart#L2496). The test passes while the exercised behavior fails.
- Import lint treats unclassified files as layer zero, emits only a note, and still exits success: [`import_lint.dart:24–37`](../v0/bin/import_lint.dart#L24), [`import_lint.dart:40–65`](../v0/bin/import_lint.dart#L40). The current `routines.dart` is unclassified.
- The gate enforces only a global 80% coverage floor. The passing report contains `embed.dart` 35.3%, `replay_cloud.dart` 44.1%, `claude.dart` 61.4%, and `router.dart` 88.6%, despite Spec 09's per-tier targets: [`09-test.md:209–220`](../planning/specs/09-test.md#L209).
- The test credential leak in SC-01 shows the suite is not fully hermetic despite Spec 09 P9.6.

**Fix.** Fail import lint on every unclassified production file; enforce the documented per-tier coverage floors; make the conformance count generated and split free/paid totals; audit skips against resolved gaps; and require behavior-bearing tests to assert the response/state outcome, not only that a seam was called. Add failure-injection tests for every storage mutation route and crash checkpoints for multi-write plans.

### SC-16 — Low — operational documentation and packaging metadata are materially stale

**Evidence.**

- `WORK-CAPSULE.md` was last updated 2026-07-28: [`WORK-CAPSULE.md:1–8`](../WORK-CAPSULE.md#L1). It says G-46 is done in Current state but Phase 2 is still to do in Open threads: [`WORK-CAPSULE.md:49–59`](../WORK-CAPSULE.md#L49), [`WORK-CAPSULE.md:146–162`](../WORK-CAPSULE.md#L146). It says TestFlight works, later says it is not set up, and carries old test counts: [`WORK-CAPSULE.md:28–35`](../WORK-CAPSULE.md#L28), [`WORK-CAPSULE.md:78`](../WORK-CAPSULE.md#L78), [`WORK-CAPSULE.md:173–175`](../WORK-CAPSULE.md#L173). Its placeholder-icon warning remains accurate and should not be removed until the icon changes.
- Spec 14's amendment says user-delimited capture, while the body and testing summary still describe engine finalization, auto-send, and second-tap abort: [`14-voice-input.md:1–19`](../planning/specs/14-voice-input.md#L1), [`14-voice-input.md:49–108`](../planning/specs/14-voice-input.md#L49), [`14-voice-input.md:123–137`](../planning/specs/14-voice-input.md#L123). The production comment is stale too, although the actual code correctly performs second-tap stop-and-send: [`main.dart:596–617`](../app/lib/main.dart#L596).
- App version is `0.12.0+18`, but Windows MSIX metadata is still `0.8.0.0`: [`pubspec.yaml:21`](../app/pubspec.yaml#L21), [`pubspec.yaml:81–88`](../app/pubspec.yaml#L81). This risks invalid upgrade/downgrade behavior when Windows packaging resumes.

**Fix.** Reconcile current-state documents and comments in the same change as the governing rule; derive test/version counters mechanically; generate MSIX version from `pubspec.yaml`. Preserve the capsule's true placeholder-icon item until the asset is replaced.

## Spec-alignment matrix

| Area | Declared contract | Wired product behavior | Alignment |
|---|---|---|---|
| Meta-schema / registry | Validated registry, cross-reference degradation, presentation checks | Maps loaded directly; skills validated; type startup validation/cross-reference registry absent | **Major drift** |
| Skill DSL | Closed declarative vocabulary, resolve/execute split, schema-safe plans | Closed vocabulary and meaningful static skill validation are real; value/schema validation and re-verification are incomplete | **Partial** |
| Execution / undo | Durable execution record, crash resume, atomic turn undo | Volatile 25-turn memory ring; sequential per-file persistence | **Major drift** |
| NLU | Corpus + local capability index + deterministic slots; cloud only residual | Corpus is real; retrieval default-off, localhost-only, suggestion-after-cloud | **Major drift** |
| Cloud seam | Typed errors, BYOK, in-seam spend guard | Typed error mapping and token accounting are real; app-side admission cap absent | **Partial** |
| Functional free tier | Ten free tasks, all offline, full subtitle parity | Corpus-covered task/people/reminder/tracker flows are strong; 24/60 exact conformance overall; novel offline phrasing weak | **Partial** |
| Paid generation | Detached structured result cards and exact per-kind grounding | Grounded prompt assemblers exist for a subset; calls are synchronous strings; weekly review semantics differ | **Major drift** |
| Authoring | Reconcile → capable structured model → independent safety review → preview/refine/activate | Validate/retry and preview/activate are real; similarity/refine/Layer-3 review/structured output are absent | **Dogfood-only partial** |
| Data storage | Per-record human-readable JSON, atomic writes, stamps, tombstones | These are real and well tested | **Strong for one device** |
| Sync | User-chosen cloud folder, watcher, merge, conflict/repair surface | Mobile forces local Documents; watcher/merge/version vector absent | **Not wired** |
| Migration | Declarative ordered chains with failure parking | Additive defaults only, then stamps current | **Unsafe drift** |
| Privacy / diagnostics | Secure key, typed redacted outbound bundle, consent manifest | Plaintext key; raw log sharing; no outbound manifest | **Release blocker** |
| UI / presence | Living Stage, always-on captions, ambient cards, lingering Done/Undo, Stream, 10 archetypes + lenses | Presence home and ephemeral exchange are real; captions hidden during TTS; DataView has simplified five archetypes; cards/Stream/undo threshold absent | **Partial** |
| Voice input | User-delimited, on-device primary/fallback, cancel distinct from stop | Actual second-tap stop/send code is real; surrounding comments/spec bodies are stale | **Behavior aligned; docs drift** |
| Reference KB / routines | Deterministic reference lookup; catalogue-grounded routine mode | Both are wired with focused tests; import classification omitted for routines | **Strong, gate gap** |
| Tests | Hermetic integration-first suite, per-tier coverage, full N/60 metric | Large effective suite and build/render smoke; credential inheritance, skips, false-green assertion, global-only coverage | **Strong base, misleading edges** |

## Verification results

### Full gate

The first ordinary run of `bash tool/precheck.sh` **failed** because a live environment credential overrode the dummy config value in `data_edit_test.dart`. The failure output disclosed the credential. No value from that output is reproduced in this artifact.

The same full gate was then run as `env -u ANTHROPIC_API_KEY bash tool/precheck.sh` and **passed**:

- bundled seed assets: in sync;
- `dart analyze lib bin test`: clean;
- import lint: passed, with `routines` reported as unclassified;
- engine tests: **1,828 passed, 36 skipped**;
- engine coverage: **91.1% (3,295/3,616)**, global 80% floor passed;
- Flutter analyze: clean;
- Flutter/widget tests: **97 passed**;
- macOS debug build: succeeded;
- real-engine/GPU integration smoke: **3 passed** (the harness reported that foregrounding via `open` returned 1, but tests executed and passed);
- tracked-file secret scan: passed;
- 05a conformance ratchet: **24 passing, baseline 24**;
- post-run process check: no Plenara or `flutter_tester` instance left running.

Coverage detail from the passing run: `embed.dart` 35.3%, `replay_cloud.dart` 44.1%, `claude.dart` 61.4%, `router.dart` 88.6%, `session.dart` 92.2%, `store.dart` 92.9%, and `interpreter.dart` 96.7%.

### Repository state

- `HEAD` and `origin/main` both resolve to `195f21fc75efaeaa177365324c0731766c36bd81`.
- The pre-review worktree contained an untracked `AGENTS.md`; it was preserved.
- Other review artifacts were produced by the parallel efforts. This effort created only this Markdown report.

### What the passing gate does and does not prove

It proves the tested deterministic engine paths, widget behaviors, build, and desktop render smoke work in the scrubbed environment at this revision. It does not prove full 60-example conformance, secure diagnostics, durable crash recovery, local semantic routing, cloud spend bounding, real iOS sync, or an interactive native launch beyond the automated integration surface.

## Remediation sequence

### 0. Immediate credential containment

Rotate the exposed credential; invalidate the old one; remove secret values from matcher output; make the test/precheck environment hermetic. This is the only item requiring the credential owner's action.

### 1. Close outbound privacy holes

Ship secure credential storage and the typed/redacted diagnostic builder together. Delete the plaintext legacy value only after verified migration. Add canary tests covering local logs, generated bundles, previews, exception paths, and test failure output.

### 2. Make act-then-describe truthful under failure

Build one durable serial execution coordinator and route all mutation paths through it. Persist plan/before-images/op progress, recover at startup, and replace blanket exception prose with typed applied/persisted/recoverable results.

### 3. Repair schema authority before evolving planner data

Implement `SchemaRegistry`, a complete value codec, and real migration descriptors. Only after these land should the task type gain the richer planning fields; otherwise the planner evolution will write data the current migration system cannot safely transform.

### 4. Restore the voice-first promise with a real local router

Embed an on-device retrieval model, build the capability index by default, move retrieval ahead of cloud, and add the in-seam spend guard. Measure top-1/margin dispatch and offline clarify rates against held-out and dogfood phrasing.

### 5. Build the planner as a complementary visual workspace

Keep voice as the fastest capture/command channel. Add persistent task grouping, state, priority/energy/estimate, project/area, schedule, dependencies, and direct manipulation; return a structured keep/defer/drop weekly review card. Restore always-on captions, lingering Done/Undo, and history so voice actions remain inspectable.

### 6. Finish storage ownership and sync claims

Until synced-folder access exists, label mobile storage honestly as device-local. Then implement the folder/document-provider flow, watch/reconcile, version vectors, merge/conflict repair, and cold-bootstrap measurements before calling the product multi-device or loss-resilient.

### 7. Tighten the gate and reconcile the corpus

Fail on unclassified production files, enforce per-tier coverage, remove false-green tests, generate conformance counts, audit resolved skip reasons, and update the work capsule/spec bodies/comments in the same changes that settle their rules. Generate platform package versions from one source.

## Final assessment

The engine is beyond a throwaway prototype: task, people, reminder, tracker, reference, routine, storage, and many failure paths have real implementation and a serious test corpus. The next quality jump does not come from adding more isolated capabilities. It comes from making the trust spine real—credential privacy, redacted diagnostics, durable execution, schema authority, migration safety, and local routing—then using that spine to support a planner that is visually inspectable without surrendering voice-first capture.
