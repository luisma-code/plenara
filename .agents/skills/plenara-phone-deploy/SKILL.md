---
name: plenara-phone-deploy
description: Build and install a usable Plenara build on Luis's physical iPhone after an explicit deployment request or whenever a new phone build is complete under his permanent standing authorization. Do not trigger for testing, verification, debugging, or documentation-only changes.
---

# Deploy Plenara to Luis's iPhone

Luis granted permanent standing authorization on 2026-09-07 to install every new phone build once it
is complete, simulator-verified, committed, and pushed. Do not ask again at that boundary. An
explicit push/install/deploy request remains sufficient on its own. Documentation-only revisions do
not create a new phone build and do not trigger installation.

Read [`TESTFLIGHT.md`](../../../TESTFLIGHT.md), [`RELEASING.md`](../../../RELEASING.md), and the latest deployment facts in [`WORK-CAPSULE.md`](../../../WORK-CAPSULE.md). Use the current internal-channel signing and deployment path rather than reconstructing commands from memory.

- Finish all known code, simulator verification, signing checks, embedded-revision checks, and secret/channel scans before the single manual deployment cycle.
- Clear `ANTHROPIC_API_KEY`, `CARTESIA_API_KEY`, and `ELEVENLABS_API_KEY` before any Flutter/Xcode build; route raw Xcode commands through `tool/safe-xcodebuild.sh` so scheme output cannot expose them.
- Compare against the latest deployment record and install each ready revision at most once.
- Resolve the exact paired device and bundle identifier read-only before installation.
- Install the verified usable artifact. Do not launch it, run tests, automate it, inspect its container, collect logs, uninstall it, or reset its data.
- A separate explicit request may authorize a narrowly scoped log copy or recovery action; record that boundary precisely.
- Record version, revision, channel, artifact hash, signature/provisioning evidence, time, and the deployment-only limitation in `WORK-CAPSULE.md`.
