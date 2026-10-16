# Plenara TestFlight delivery

October 16, 2026. Remote delivery of the native relationship app requested by Luis.

- App Store Connect app: Plenara, `6795650460`, bundle `com.plenara.plenaraApp`.
- Native version: **1.0.0 (1000)**; iPhone only, iOS 18+.
- Optimized Release archive and App Store Connect distribution export succeeded.
- Apple validation: **VERIFY SUCCEEDED with no errors**.
- Apple upload: **UPLOAD SUCCEEDED with no errors**.
- Delivery UUID: `8833f59e-243a-4485-b20c-c5da5edaa1f1`.
- Uploaded IPA: 882,937 bytes; SHA-256 `840681349cfd322ab39e0884067cf128cc899c681db7d528e8a218b1b36a85bd`.
- Native source hashes match the simulator-verified implementation. The physical-device IPA has no fictional demo people or simulator launch controls.
- Existing internal group and owner enrollment were verified through Apple's API. No new invitations or public tester links were created.

## Confirmed availability

Apple readback confirms **VALID**, not expired, assigned to **Internal**, with internal state **IN_BETA_TESTING**. The owner is enrolled in that group. [Distribution readback](testflight-status.json).

Open **TestFlight → Plenara → Update** (or **Install**) and select **1.0.0 (1000)**. This is the new relationship app. The previous planner data is not automatically imported.

TestFlight release notes were saved and read back. The complete repository precheck passed again: archive integrity, six design-prototype checks, 16 native Release tests, and the extra Contacts-denied import journey. The app source remained unchanged during this delivery; only delivery tools and documentation were added.

Remote installation and launch on the owner’s iPhone cannot be observed from this Mac. Availability is confirmed through Apple’s processing, group assignment, and tester enrollment readback.

[App Store Connect TestFlight](https://appstoreconnect.apple.com/apps/6795650460/testflight/ios)

The remote owner installs through the TestFlight app on their iPhone. No physical phone launch, automated test, or layout probe was performed.

For repeatable operations, see [native delivery instructions](../ios/README.md). Upload logs and the signed IPA remain local under ignored `.tmp/testflight/` and `.build/testflight/` paths.

## Automatic delivery preference

Luis requested automatic pushes on October 16, 2026. The standing project
instruction now authorizes TestFlight upload and release after every completed,
validated app change, without asking again. The deployment command waits for
Apple's actual status, assigns the exact build to the enrolled group, and
requires `IN_BETA_TESTING` before success. It stops with a named blocker on
rejection, expiration, or a 20-minute processing deadline.

The release command was exercised against the existing live build 1000 and
confirmed its availability without another binary upload. Three orchestration
checks cover delayed processing, Apple rejection, and timeout. The complete
precheck passed after the workflow change, including all 16 native checks and
the additional denied-access Contacts journey. All three workflow checks rejected a
known-broken premature-success control, then passed with the source restored.
[Calibration record](testflight-automation-calibration.json).

On-device automatic installation is a separate TestFlight setting controlled
by the owner. In **TestFlight → Plenara**, turn on **Automatic Updates**.
[Apple's TestFlight instructions](https://testflight.apple.com/) describe this
setting. The remote deployment API cannot change that phone setting.
