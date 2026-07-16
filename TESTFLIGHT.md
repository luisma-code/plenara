# TestFlight — deploy Plenara to the phone from anywhere

The goal: build + upload from the Mac, install/update on the iPhone **over cellular from anywhere**
(no same-WiFi requirement, and no container-wipe on every update — data + API key survive).

## What Claude does on the Mac (automated — no Apple login needed)
- `ITSAppUsesNonExemptEncryption=false` set in `Info.plist` (the app uses only standard HTTPS/TLS to
  Anthropic — export-exempt), so Apple never prompts export compliance per upload. ✅ done
- `flutter build ipa --release` builds the distribution **archive** (`app/build/ios/archive/…`). ✅ verified
- `tool/testflight-upload.sh` exports a **signed IPA** from that archive and uploads it — using ONLY
  the App Store Connect **API key** (`xcodebuild -allowProvisioningUpdates` auto-creates the iOS
  Distribution cert + App Store profile on first run; `altool` uploads). No interactive Xcode login.

## What only Luis can do (one-time, in his Apple account) — the batch
> Machine state today: only an *Apple Development* cert + **no Apple account in Xcode**, so the export
> can't sign yet. The API key below fixes ALL of that without you signing into Xcode.

1. **Create the app record:** App Store Connect → Apps → **+** → New App →
   - Platform: **iOS**, Bundle ID: **com.plenara.plenaraApp** (pick it from the list — if it's not
     there, it auto-registered on the first device build; create the identifier if needed),
     Name: **Plenara**, Primary language: English, SKU: `plenara` (any unique string).
   - Accept any pending Apple **agreements** it prompts for (free-apps / business).
2. **Generate an App Store Connect API key:** App Store Connect →
   **Users and Access → Integrations → App Store Connect API** → generate a key with **Admin**
   access (Admin so it can create the signing certificate) → **download the `.p8` once** (Apple
   only lets you download it a single time), and note the **Key ID** and **Issuer ID**.
3. Hand Claude the three values (drop them in `tool/.testflight.env`, gitignored):
   ```
   ASC_KEY_ID=XXXXXXXXXX
   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
   ```
4. **Add yourself as an internal tester:** App Store Connect → your app → TestFlight →
   Internal Testing → add your Apple ID. Install the **TestFlight app** on the iPhone and sign in.
   (You can do this while the first build processes.)

## Then, per release (Claude runs)
```
cd app && flutter build ipa --release   # builds the archive (its own export step may warn on signing — fine)
../tool/testflight-upload.sh            # exports a signed IPA + uploads via the API key
```
Apple processes the build (~5–15 min); it then appears in TestFlight on the phone to install/update.

## Notes
- **Export compliance** is pre-answered by the Info.plist key — no per-upload prompt.
- **Distribution signing** rides Xcode automatic signing on team `7V63BZ39HU`; the first archive
  creates the distribution cert + provisioning profile if missing.
- Bump `version:` in `app/pubspec.yaml` (`x.y.z+BUILD`) each upload — the `+BUILD` must strictly
  increase or App Store Connect rejects the binary as a duplicate.
