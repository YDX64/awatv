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
