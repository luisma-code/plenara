# Plenara icon update

The new icon extends the approved app design: six soft petals in ivory,
lavender, and peach, arranged around a shared center on a plum field.
It echoes the six-part botanical motif and the colors of the relationship
cards. Broad filled shapes replace the former thin, overlapping orbital lines.

[Icon preview: light, dark, and small sizes](icon-preview.png)

The artwork is editable vector geometry, rendered deterministically by
`tool/render-icon.cjs`. Production assets are opaque 1024 × 1024 PNGs without
pre-rounded corners; iOS supplies the icon mask. Both appearances were visually
reviewed at full size and at 60, 40, and 29 pixels. No image-generation service
or paid operation was used.

[Light vector source](../design/icon/plenara.svg) · [Dark vector source](../design/icon/plenara-dark.svg)

The icon is packaged in native version **1.0.0 (1001)**. The complete precheck passed: archive integrity, six design-prototype checks,
three release-workflow checks, 16 native Release tests, and the extra Contacts
import/reimport journey with broad access denied. [Native test summary](icon-native-test-summary.json)
· [Source fingerprints](icon-source-hashes.json).

The [simulator Home Screen capture](icon-launcher-light.png) confirms that the
installed app displays the new icon at actual launcher size. Both icon artworks
were reviewed in the size sheet and compiled into the native asset catalog.
SpringBoard retained its light icon style when system appearance changed; its
separate customization menu could not be exercised because the host Mac was
locked. The dark artwork is therefore source/packaging reviewed, rather than
confirmed through the launcher customization UI.

No physical iPhone is launched or tested. TestFlight availability is recorded
below after Apple's processing and group readback.


## TestFlight delivery confirmed

Version **1.0.0 (1001)** passed Apple's validation and upload without errors.
Delivery UUID: `68d609ee-6576-49cd-8e73-5715bb0c41f8`.
Apple readback confirms **VALID**, not expired, assigned to the enrolled
**Internal** group, and **IN_BETA_TESTING**. The automatic upload/release
workflow completed successfully. Release notes were updated and verified.

[Distribution readback](icon-testflight-status.json) · [Signed artifact record](icon-device-artifact.json)

The native source remains exactly the simulator-verified candidate. Only the
delivery record was added afterward. The icon is available through TestFlight;
installation on the owner's remote phone is not observable from this Mac.
