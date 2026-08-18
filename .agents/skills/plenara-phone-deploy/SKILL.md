---
name: plenara-phone-deploy
description: Build and install a usable Plenara build on Luis's physical iPhone only when he explicitly asks for deployment. Do not trigger for testing, verification, debugging, or general shipping requests.
---

# Deploy Plenara to Luis's iPhone

This skill does not grant deployment authority. Continue only when Luis explicitly asks to push, install, or deploy a usable app to his phone.

Read [`TESTFLIGHT.md`](../../../TESTFLIGHT.md), [`RELEASING.md`](../../../RELEASING.md), and the latest deployment facts in [`WORK-CAPSULE.md`](../../../WORK-CAPSULE.md). Use the current internal-channel signing and deployment path rather than reconstructing commands from memory.

- Finish all known code, simulator verification, signing checks, embedded-revision checks, and secret/channel scans before the single manual deployment cycle.
- Resolve the exact paired device and bundle identifier read-only before installation.
- Install the verified usable artifact. Do not launch it, run tests, automate it, inspect its container, collect logs, uninstall it, or reset its data.
- A separate explicit request may authorize a narrowly scoped log copy or recovery action; record that boundary precisely.
- Record version, revision, channel, artifact hash, signature/provisioning evidence, time, and the deployment-only limitation in `WORK-CAPSULE.md`.
