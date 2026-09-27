# Universal iPhone and iPad experience

## User request

> I've onboarded a new iPad into xcode (called golden god). Can we have this app generate both an iPhone and iPad version, and deploy to each? For the iPad version I'd primarily expect it to take advantage of the added screen real estate, show things at high fidelity.

## Product and build decision

Xcode already configures Plenara as one universal iOS target for iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). A separate app target would duplicate release and product behavior without providing a device-specific benefit. Keep one signed universal app and adapt the layout at runtime; install the same build on both registered devices. The existing phone layout stays the compact layout.

## What changed

- At 840 logical points, the four primary roots use a persistent labeled side rail. Narrower windows retain bottom navigation.
- Today distributes relationship, commitment, and practice opportunities into as many as three readable columns. People and Routines arrange items into two columns when the available width supports them.
- Conversation and shared details keep maximum content widths. The Plena entry controls remain centered and compact on iPad; record details open in a centered dialog rather than a phone-style bottom sheet.
- The phone layout remains independently covered at a 402-point viewport, including the bottom navigation and single-column Today list.
- One release version is recorded as `0.14.1+21` for this universal install.

## Verification and delivery

- The calibrated widget test first failed when the tablet breakpoint was deliberately moved past the iPad viewport, then passed with the restored breakpoint. It checks the iPad rail, three distinct Today columns, People/Routines grids, no render exception, and phone navigation when returned to a phone-sized viewport.
- `integration_test/ipad_layout_test.dart` ran on the iPad Pro 13-inch (M5) iOS 26.5 simulator and checked the actual window width, side rail, Today grid, three opportunities, and render exceptions.
- Full `bash tool/precheck.sh` passed: 2,073 engine tests with 36 declared skips; 184 app tests with 4 declared skips; all 4 external-channel tests; 8 real-engine render tests; analyzer, coverage, host build, seed/doc consistency, secret scan, and the 24/60 conformance ratchet.
- The macOS render journey rose from about 290 MB to 459 MB RSS, then held around that level through eight cases and exited normally. This is cleanup evidence, not a long-run memory claim.
- The internal release is `0.14.1+21`, source revision `db6ee82`, for universal family `[1,2]`; signing team `7V63BZ39HU`; signature verification passed; AOT SHA-256 `7ea3fbb55016b58f2c3684adad0555668c697918735d768b3108e723b8a77f05`.
- The app installed successfully, without launch, on iPhone 16 Pro “Aluminum Monster” (UDID `00008140-000645442862201C`) on 2026-09-27.
- iPad Pro 13-inch (M5) “Golden God” (UDID `00008142-001265C90AFB401C`) is paired, reachable, and in developer mode. Installation was rejected because the embedded development profile authorizes only Aluminum Monster. Xcode automatic registration/profile refresh failed with `No Accounts: Add a new account in Accounts settings.` Sign into Xcode with the existing Apple developer team so the profile can include Golden God; the iPad install then needs a rebuild. The app was not launched on either physical device.

## Scope boundary

This device-layout change does not add message history or call-log surveillance. Existing selected-item Calendar/Reminders review, explicit pasted text, and Shortcut captures continue to be the deliberate evidence paths described in Spec 17.
