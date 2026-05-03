# AWAtv — Required GitHub Secrets

> Every secret AWAtv's CI needs, with the **exact name**, what it's for, and where you get it. Mark items 🟢 once you've set them in <https://github.com/YDX64/awatv/settings/secrets/actions>.

---

## ✅ Already set (verified 2026-05-04)

These appear in `gh secret list` output and are wired into `release-desktop.yml` + `release-ios.yml` + `deploy-web.yml`.

| Secret | Used by | Last rotated |
|--------|---------|--------------|
| 🟢 `SUPABASE_URL` | desktop + iOS + web | 2026-05-03 |
| 🟢 `SUPABASE_ANON_KEY` | desktop + iOS + web | 2026-05-03 |
| 🟢 `WEB_PROXY_URL` | runtime config (CORS proxy worker) | 2026-04-28 |

`SUPABASE_URL` value: `https://ukulkbthsgkmihjcpzek.supabase.co` (AWATV-USER project, dedicated).
`SUPABASE_ANON_KEY` value: legacy anon JWT, ref `ukulkbthsgkmihjcpzek`, role `anon`, valid until 2036-05-02.

---

## ❌ Missing — required for iOS TestFlight pipeline

Set all 7 before triggering `release-ios.yml`. Detailed how-to: `docs/IOS_TESTFLIGHT_SETUP.md`.

| Secret | Format | How to get | Status |
|--------|--------|-----------|--------|
| 🔴 `APPLE_TEAM_ID` | 10-char string e.g. `ABCDE12345` | <https://developer.apple.com/account> → Membership Details → Team ID | not set |
| 🔴 `APPLE_CERTIFICATE_P12` | base64 (single line, no newlines) | Export distribution cert from Keychain Access as `.p12`, then `base64 -i awatv-distribution.p12 \| pbcopy` | not set |
| 🔴 `APPLE_CERTIFICATE_PASSWORD` | string | Whatever password you set when exporting `.p12` | not set |
| 🔴 `APPLE_PROVISIONING_PROFILE` | base64 | App Store provisioning profile for `com.awatv.awatvMobile`, named `AWAtv App Store`, then `base64 -i awatv_app_store.mobileprovision \| pbcopy` | not set |
| 🔴 `APP_STORE_CONNECT_API_KEY_ID` | 10-char string | App Store Connect → Users and Access → Integrations → App Store Connect API → Key ID column | not set |
| 🔴 `APP_STORE_CONNECT_ISSUER_ID` | UUID e.g. `69a6de70-1234-…` | Same screen → Issuer ID at the top | not set |
| 🔴 `APP_STORE_CONNECT_API_KEY_BASE64` | base64 | The `.p8` file you downloaded once-and-only-once when generating the API key, then `base64 -i AuthKey_XXX.p8 \| pbcopy` | not set |

**One-line generation reminder:**

```bash
echo "Team ID: visit https://developer.apple.com/account → Membership Details"
base64 -i ~/Downloads/awatv-distribution.p12 | pbcopy           # APPLE_CERTIFICATE_P12
echo "remember p12 password as APPLE_CERTIFICATE_PASSWORD"
base64 -i ~/Downloads/awatv_app_store.mobileprovision | pbcopy  # APPLE_PROVISIONING_PROFILE
echo "API Key ID: visit https://appstoreconnect.apple.com/access/integrations/api"
echo "Issuer ID: same screen, top of the page"
base64 -i ~/Downloads/AuthKey_XXX.p8 | pbcopy                   # APP_STORE_CONNECT_API_KEY_BASE64
```

---

## ❌ Missing — optional, for Cloudflare Pages auto-deploy

Without these the web build at <https://awatv.pages.dev> stays stale until someone manually `wrangler pages deploy`s. Set them and every push to main auto-deploys.

| Secret | Format | How to get | Status |
|--------|--------|-----------|--------|
| 🔴 `CLOUDFLARE_API_TOKEN` | string | <https://dash.cloudflare.com/profile/api-tokens> → Create Token → "Edit Cloudflare Pages" template | not set |
| 🔴 `CLOUDFLARE_ACCOUNT_ID` | string | <https://dash.cloudflare.com> → right sidebar → "Account ID" | not set |

Setting them flips `deploy-web.yml`'s `if: steps.cf.outputs.have_creds == 'true'` gate to `true` and the next push auto-deploys.

---

## Optional — for production AdMob (replaces test ad ids)

Without these, the app uses AdMob's universally-recognised TEST app id (`ca-app-pub-3940256099942544~3347511713` Android, `ca-app-pub-3940256099942544~1458002511` iOS) — real ads with a "Test Ad" watermark, no revenue. Replace with your real ids once you've created the AdMob app entries.

| Secret / .env key | Where to get it |
|-------------------|-----------------|
| `ADMOB_APP_ID_IOS` | <https://apps.admob.com> → Apps → AWAtv iOS → App ID |
| `ADMOB_APP_ID_ANDROID` | Same, Android entry |
| `ADMOB_BANNER_IOS` | Apps → AWAtv iOS → Ad units → Banner unit id |
| `ADMOB_BANNER_ANDROID` | Same, Android |
| `ADMOB_INTERSTITIAL_IOS` | Apps → AWAtv iOS → Ad units → Interstitial unit id |
| `ADMOB_INTERSTITIAL_ANDROID` | Same, Android |

These are read from the bundled `.env` (CI bakes from GitHub secrets), NOT from runtime config — changing them requires a release.

After replacing, also update the `GADApplicationIdentifier` in `apps/mobile/ios/Runner/Info.plist` and `com.google.android.gms.ads.APPLICATION_ID` in `apps/mobile/android/app/src/main/AndroidManifest.xml` from the test ids to the real ones (the meta-data tag values, not the env keys).

---

## Required for production RevenueCat (anti-tamper premium gate)

The Supabase `subscriptions` table is the **only authoritative source** of premium state — even if a user roots their device + LuckyPatcher-flips the local cache, the next app boot pulls from Supabase and overwrites the lie. RC's webhook is the only thing that writes to that table.

### One-time RC setup

1. Sign up at <https://www.revenuecat.com> (free up to $2.5K MTR).
2. Create a new project: **AWAtv**.
3. Add an iOS app: bundle id `com.awatv.awatvMobile`. Add an Android app: package name `com.awatv.awatv_mobile` (verify in `android/app/build.gradle`).
4. **Apple Developer integration**: paste your App Store Connect API key (same `.p8` you set up for TestFlight).
5. **Google Play integration**: paste a Google Play service-account JSON.
6. Create products in RC dashboard:
   - `awatv_premium_monthly` (auto-renewing, monthly)
   - `awatv_premium_yearly` (auto-renewing, yearly)
   - `awatv_premium_lifetime` (one-time, non-renewing)
7. Create entitlement `premium` and attach all three products.
8. Note the **Public SDK Keys** (one per platform) for the .env.

### Webhook setup

1. RC dashboard → Project → Integrations → **Webhooks**.
2. Webhook URL: `https://ukulkbthsgkmihjcpzek.supabase.co/functions/v1/revenuecat-webhook`
3. Copy the auto-generated **Authorization header value** (a random secret).
4. Set as a Supabase secret:
   ```bash
   supabase secrets set REVENUECAT_WEBHOOK_SECRET=<the value> \
     --project-ref ukulkbthsgkmihjcpzek
   ```
5. Deploy the edge function:
   ```bash
   supabase functions deploy revenuecat-webhook \
     --project-ref ukulkbthsgkmihjcpzek
   ```
6. Test in RC dashboard: Webhooks → Send Test Event. Should land in `subscriptions` table within 2s.

### Client-side .env keys

| Key | Where to get |
|-----|--------------|
| `REVENUECAT_API_KEY_IOS` | RC dashboard → Project → API keys → Apple Public SDK Key |
| `REVENUECAT_API_KEY_ANDROID` | Same, Google Public SDK Key |

Add these as GitHub secrets (CI bakes them into the bundled `.env`):

```
gh secret set REVENUECAT_API_KEY_IOS --body "appl_xxxxxxxx"
gh secret set REVENUECAT_API_KEY_ANDROID --body "goog_xxxxxxxx"
```

Anti-tamper guarantee: even with all the SDK keys leaked, an attacker can't fake a purchase because RC's signed webhook is the only path to write `subscriptions.status='active'`. The RLS policy `subscriptions_select_own` lets users read their own row but explicitly denies INSERT/UPDATE/DELETE.

---

## Optional — if you want Android Play Store releases

Currently `release-android.yml` exists but is not wired for store upload. To enable:

| Secret | Format | How to get |
|--------|--------|-----------|
| `ANDROID_KEYSTORE_BASE64` | base64 | Android keystore (`.jks`), `base64 -i awatv.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | string | Whatever you set during keystore creation |
| `ANDROID_KEY_PASSWORD` | string | Per-key alias password |
| `ANDROID_KEY_ALIAS` | string | The alias name |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | base64 | JSON service-account creds from Google Play Console |

Not currently needed.

---

## Adding a secret

1. Go to <https://github.com/YDX64/awatv/settings/secrets/actions>.
2. Click **New repository secret**.
3. Paste **exact name** from the table.
4. Paste value (no quotes, no trailing newline).
5. Click **Add secret**.

To rotate / overwrite an existing secret, click the secret name → **Update**.

To verify a secret exists without revealing the value:

```bash
gh secret list -R YDX64/awatv
```

To delete a secret:

```bash
gh secret delete SECRET_NAME -R YDX64/awatv
```

---

## What if a secret is wrong?

The workflow will fail loudly. Each common failure mode is documented in `docs/IOS_TESTFLIGHT_SETUP.md` § Troubleshooting. The most common:

- `security import: MAC verification failed` → `APPLE_CERTIFICATE_PASSWORD` doesn't match the .p12 password
- `xcodebuild error: No profile for team 'XXXX' matching 'AWAtv App Store'` → profile name in Apple Developer doesn't match `provisioningProfiles` map in `ExportOptions.template.plist`
- `altool: A new bundle was uploaded but the latest version was not used` → bump pubspec build number, or use `build_number_suffix` workflow input

---

## Security hygiene

- **Never commit secrets.** `.env` is in `.gitignore`; `.env.example` is the template.
- **Never paste a secret into a chat or PR description.** Use the GitHub Secrets UI.
- **Rotate certs annually.** Apple distribution certs expire after 1 year — `release-ios.yml` will start failing once the cert hits its expiry. Re-issue, re-export, re-base64, re-set.
- **API keys are revocable.** If a key leaks, revoke it in App Store Connect / Apple Developer → generate a new one → update the secret. No code changes needed.
- **`SUPABASE_ANON_KEY` is safe to expose** in compiled binaries — RLS policies enforce data isolation. Service-role keys are NEVER bundled.
