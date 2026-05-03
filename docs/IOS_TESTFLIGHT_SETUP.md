# iOS TestFlight setup

This is the one-time setup to wire AWAtv's GitHub Actions to push every push-to-main into TestFlight. After this is done once, every release tag triggers an automatic build → sign → upload → TestFlight.

## Prerequisites

- Apple Developer Program membership ($99/year). If you don't have one, enroll at <https://developer.apple.com/programs/enroll/>. Approval takes 1-2 days.
- A Mac with macOS 14+ to generate the certificate locally (Keychain Access lives there).

## Bundle id

The Flutter project ships with bundle id **`com.awatv.awatvMobile`** (read from `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`). The whole pipeline assumes this exact id — don't rename it during setup or downstream secrets won't match.

## Step 1 — Register the App ID in Apple Developer

1. Go to <https://developer.apple.com/account/resources/identifiers/list>.
2. Click **+ Register a new identifier** → App IDs → App.
3. **Description**: `AWAtv Mobile`
4. **Bundle ID**: Explicit, value `com.awatv.awatvMobile`
5. **Capabilities** to enable now (others can be added later):
   - Push Notifications (for the reminders feature)
   - Background Modes (for audio/background-playback)
   - Associated Domains (for magic link deep linking)
6. Click **Continue → Register**.

## Step 2 — Create the App in App Store Connect

1. Go to <https://appstoreconnect.apple.com/apps>.
2. Click **+ → New App**.
3. **Platforms**: iOS.
4. **Name**: AWAtv (this becomes the App Store listing name; you can change it later).
5. **Primary Language**: Turkish (or whatever you ship first).
6. **Bundle ID**: select the `com.awatv.awatvMobile` you just registered.
7. **SKU**: anything unique — `awatv-mobile-2026` works.
8. **User Access**: Full Access.
9. Click **Create**.

The app will live in App Store Connect as a draft — TestFlight uploads can happen before you ever submit to the App Store review.

## Step 3 — Generate a Distribution Certificate (.p12)

1. Open **Keychain Access** on your Mac.
2. **Keychain Access menu → Certificate Assistant → Request a Certificate from a Certificate Authority…**
3. **User Email**: your Apple ID email.
4. **Common Name**: `AWAtv Distribution`
5. Choose **Saved to disk**, click Continue. Save as `awatv.certSigningRequest`.
6. Go to <https://developer.apple.com/account/resources/certificates/list>.
7. Click **+** → **Apple Distribution**.
8. Upload the `.certSigningRequest` you just created.
9. Click **Continue → Download**. You now have an `.cer` file.
10. Double-click the `.cer` to import into Keychain Access.
11. In Keychain Access, find the certificate (named "Apple Distribution: <Your Name> (TEAMID)") under **Login** keychain → **My Certificates**. Make sure the disclosure triangle shows the matching private key under it.
12. **Right-click the cert → Export**. Choose Personal Information Exchange (.p12). Save as `awatv-distribution.p12`.
13. Set a password — pick something you'll remember (e.g. paste from a password manager). **Save this password — you'll need it as a GitHub secret.**

## Step 4 — Create a Provisioning Profile

1. Go to <https://developer.apple.com/account/resources/profiles/list>.
2. Click **+** → Distribution → **App Store**.
3. **App ID**: select `com.awatv.awatvMobile`.
4. **Certificates**: pick the Apple Distribution cert you just generated.
5. **Profile Name**: `AWAtv App Store` (must match exactly the name in `apps/mobile/ios/ExportOptions.template.plist`).
6. Click **Generate → Download**. You now have an `awatv_app_store.mobileprovision`.

## Step 5 — Create an App Store Connect API Key

1. Go to <https://appstoreconnect.apple.com/access/integrations/api>.
2. Click **+ → Generate API Key**.
3. **Name**: `AWAtv CI`.
4. **Access**: **App Manager** (this lets the key upload to TestFlight without granting App Store submission).
5. Click **Generate**. A `.p8` file downloads automatically — **you can only download this once**, so keep it.
6. Copy these three values from the resulting key row (you'll need all three as GitHub secrets):
   - **Key ID** (10 chars, e.g. `4FQRXP9V7K`)
   - **Issuer ID** (UUID at the top of the page, e.g. `69a6de70-…`)
   - The `.p8` file itself

## Step 6 — Find your Team ID

1. Go to <https://developer.apple.com/account>.
2. Top right corner: **Membership Details** card → look for **Team ID** (10 chars, e.g. `9X8Y7Z6W5V`).

## Step 7 — Encode binaries to base64 and copy

In Terminal on your Mac, run these one at a time (each copies the result to clipboard):

```bash
# Distribution cert
base64 -i ~/Downloads/awatv-distribution.p12 | pbcopy
# → Paste into GitHub secret APPLE_CERTIFICATE_P12

# Provisioning profile
base64 -i ~/Downloads/awatv_app_store.mobileprovision | pbcopy
# → Paste into GitHub secret APPLE_PROVISIONING_PROFILE

# App Store Connect API key
base64 -i ~/Downloads/AuthKey_4FQRXP9V7K.p8 | pbcopy
# → Paste into GitHub secret APP_STORE_CONNECT_API_KEY_BASE64
# (replace 4FQRXP9V7K with your actual key id)
```

## Step 8 — Set GitHub Secrets

Go to <https://github.com/YDX64/awatv/settings/secrets/actions> and add these one by one. Names must match **exactly** as listed in `.github/workflows/release-ios.yml`:

| Name | Value |
|------|-------|
| `APPLE_TEAM_ID` | Your 10-char team id from Step 6 |
| `APPLE_CERTIFICATE_P12` | base64 of `.p12` (single line, no newlines) |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting `.p12` |
| `APPLE_PROVISIONING_PROFILE` | base64 of `.mobileprovision` |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from Step 5 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from Step 5 |
| `APP_STORE_CONNECT_API_KEY_BASE64` | base64 of `AuthKey_<KEYID>.p8` |

The existing `SUPABASE_URL` / `SUPABASE_ANON_KEY` secrets are reused — no need to re-set them.

## Step 9 — First TestFlight upload

1. Go to <https://github.com/YDX64/awatv/actions/workflows/release-ios.yml>.
2. Click **Run workflow → main branch → Run workflow**.
3. Wait ~12-15 min. The job runs:
   - flutter pub get + code generation
   - bake `.env` from secrets
   - import cert into a temporary keychain
   - install provisioning profile
   - render `ExportOptions.plist` with team id
   - `flutter build ipa --release`
   - upload to TestFlight via `xcrun altool`
4. After the job finishes, watch <https://appstoreconnect.apple.com/apps>.
5. Click your app → TestFlight tab. The build will appear in **"iOS Builds"** ~5-10 min after upload (Apple does a server-side validation pass).
6. Once it shows **Ready to Test**, click into it, set **What to Test**, save, then add yourself as an internal tester at **Users and Access → TestFlight** if you haven't already.
7. Open the **TestFlight app** on your iPhone, log in with your Apple ID. The build appears under "Available Apps" within minutes of being marked Ready.

## Step 10 — Future releases

Every push to `main` that touches `apps/mobile/lib/`, `apps/mobile/ios/`, or `apps/mobile/pubspec.yaml` will (after we extend the workflow's `paths:` filter — currently only manual + release event) trigger an iOS build. For now, we keep it manual + tag-driven so you don't burn iOS minutes on every commit.

To ship a tagged release with both desktop and iOS attached:

1. Bump `apps/mobile/pubspec.yaml` version, commit, push.
2. Wait for `release-desktop.yml` to finish.
3. Create a GitHub Release with tag `awatv-vX.Y.Z`.
4. Release event triggers BOTH `release-desktop.yml` (`-recap` of binaries) AND `release-ios.yml` (.ipa upload).

## Troubleshooting

**`security import` errors with "MAC verification failed"**
The `APPLE_CERTIFICATE_PASSWORD` secret doesn't match the password you set when exporting the `.p12`. Re-export and reset the secret.

**`xcodebuild error: No profile for team 'XXXX' matching 'AWAtv App Store' found`**
The provisioning profile's Name doesn't match `provisioningProfiles[com.awatv.awatvMobile]` in `ExportOptions.template.plist`. Either rename the profile in Apple Developer to `AWAtv App Store` or edit the template's value to whatever you named it.

**`altool` errors with `A new bundle was uploaded but the latest version was not used`**
TestFlight rejects identical build numbers. Either bump `pubspec.yaml`'s build number suffix (`+11` → `+12`) and push, or trigger the workflow manually with a `build_number_suffix` value (e.g. `b1`).

**TestFlight shows "Build is not yet available for testing"**
Apple does a one-time export-compliance prompt the first time you upload an app. Go to App Store Connect → your app → TestFlight → Encryption: select "No" if you only use HTTPS, or "Yes — exempt" if you have a use-case statement. Once answered, the build flips to Ready to Test within a minute.

**Build fails on `flutter build ipa` with mysterious linker errors**
The macOS-15 runner ships Xcode 16; some Cocoapods may need a `pod update`. The workflow regenerates `Podfile.lock` automatically via `flutter build`; if you've checked it in with stale entries, delete `apps/mobile/ios/Podfile.lock` and re-push.

## Quick reference — secrets cheat sheet

```
APPLE_TEAM_ID=ABCDE12345
APPLE_CERTIFICATE_P12=<base64 of awatv-distribution.p12>
APPLE_CERTIFICATE_PASSWORD=<the password you set during .p12 export>
APPLE_PROVISIONING_PROFILE=<base64 of awatv_app_store.mobileprovision>
APP_STORE_CONNECT_API_KEY_ID=4FQRXP9V7K
APP_STORE_CONNECT_ISSUER_ID=69a6de70-1234-1234-1234-abcdef123456
APP_STORE_CONNECT_API_KEY_BASE64=<base64 of AuthKey_4FQRXP9V7K.p8>
```
