---
name: plenara-simulator-verification
description: Verify Plenara UI, voice, animation, integration, or runtime behavior on local simulators and render surfaces. Use for app launches and user-visible fixes; never use the physical iPhone as a test target.
---

# Verify Plenara on local surfaces

Read the relevant owning spec and [`WORK-CAPSULE.md`](../../../WORK-CAPSULE.md) before choosing the verification surface.

- Use widget/render tests for deterministic layout and interaction, a local iPhone simulator for iOS integration, and macOS only for behavior its platform can represent.
- Never install, launch, inspect, probe, or run a harness on Luis's physical iPhone. Installation is a separate `plenara-phone-deploy` workflow, triggered by an explicit request or by the permanent standing authorization for a completed, simulator-verified, committed, and pushed phone build.
- Drive the production entry point or real interaction boundary. Confirm the run actually reached the state under test.
- Run raw Xcode build/test commands through `tool/safe-xcodebuild.sh`; it clears ambient provider credentials before Xcode can dump its scheme environment.
- Treat simulator permission sheets and other system dialogs as harness state: confirm the host session is unlocked before a run that needs desktop interaction, inspect the visible surface, explicitly choose the intended response, and continue the run. Prefer simulator pre-authorization only when the permission decision itself is not under test. Never leave a test waiting behind a dialog, and never transfer this automation to the physical iPhone.
- For any new or changed test, screenshot gate, motion strip, log check, or threshold, restore the real broken behavior long enough to see the verifier fail; then restore the fix and see it pass.
- For animation, capture still keyframes across the full range and inspect the composite state a user actually sees.
- During every launched run, sample memory. Kill a process that climbs without plateauing. End all processes and shut down simulators started for the task; confirm there are no orphans.
- Report exactly which artifact and surface ran, what it proved, and any platform limitation. Never describe a short memory sample as proof of no leak.
- Before completion, run the proportional focused checks and `bash tool/precheck.sh`.
