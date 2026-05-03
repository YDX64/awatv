# RevenueCat + AdMob + Anti-tamper premium gate

Complete setup guide for the freemium economy. Once all secrets are in place, free tier shows ads, premium tier doesn't, and **the premium gate cannot be bypassed by LuckyPatcher / Frida / any client-side tampering**.

## Architecture overview

```
                                                  +------------------+
   1. User taps "Subscribe" in app                |                  |
              ↓                                   |  Apple App Store |
   2. purchases_flutter SDK (client) ───────────► |  / Google Play   |
                                                  |                  |
   3. Receipt validation server-side              +------------------+
              ↓                                            ↓
   4. RevenueCat receives purchase           ┌─────────────┴─────────────┐
              ↓                              │ RevenueCat servers        │
   5. RevenueCat webhook (signed) ──────────►│ (server-side validation)  │
              ↓                              └─────────────┬─────────────┘
                                                           ↓
   6. Supabase Edge Function:                +─────────────┴───────────+
      - validates HMAC                       │ supabase/functions/    │
      - upserts subscriptions row ──────────►│ revenuecat-webhook     │
                                             +─────────────┬───────────+
                                                           ↓
   7. RLS-protected subscriptions table      ┌─────────────┴─────────────┐
              ↑                              │ public.subscriptions      │
              │                              │ (SELECT-only RLS for      │
   8. Realtime stream → app premium flag     │  clients; service-role    │
                                             │  is the only writer)      │
                                             └───────────────────────────┘
```

**Key property:** the local Hive cache holds a copy of premium state for fast first-frame render, but **every signed-in boot re-fetches from Supabase** and overwrites. A LuckyPatcher write to Hive flips premium for ~1ms; the first server poll restores truth.

## Secrets setup checklist

Add the secrets in [GitHub Settings](https://github.com/YDX64/awatv/settings/secrets/actions):

### Already set (from previous setup)
- ✅ `SUPABASE_URL`
- ✅ `SUPABASE_ANON_KEY`
- ✅ `WEB_PROXY_URL`

### iOS TestFlight
See `docs/IOS_TESTFLIGHT_SETUP.md`. 7 secrets.

### RevenueCat (anti-tamper premium)

1. Sign up at <https://www.revenuecat.com> (free up to $2.5K MTR).
2. Create a project: **AWAtv**.
3. Add iOS app (bundle id `com.awatv.awatvMobile`) + Android app (package `com.awatv.awatv_mobile`).
4. **Apple App Store Connect integration**: paste your `.p8` API key (same one from `docs/IOS_TESTFLIGHT_SETUP.md`).
5. **Google Play integration**: paste service-account JSON (Play Console → Setup → API access).
6. Create products in RC dashboard:
   - `awatv_premium_monthly` — auto-renewing monthly
   - `awatv_premium_yearly` — auto-renewing yearly
   - `awatv_premium_lifetime` — non-renewing one-time
7. Create entitlement `premium`, attach all three products.
8. Note the **Public SDK Keys** (one per platform).

**GitHub secrets:**
| Name | Value |
|------|-------|
| `REVENUECAT_API_KEY_IOS` | `appl_xxxxxx` from RC dashboard |
| `REVENUECAT_API_KEY_ANDROID` | `goog_xxxxxx` from RC dashboard |

### Webhook → Supabase

1. RC dashboard → Project → Integrations → **Webhooks**.
2. Webhook URL: `https://ukulkbthsgkmihjcpzek.supabase.co/functions/v1/revenuecat-webhook`
3. Copy the auto-generated **Authorization header value**.
4. Set as Supabase secret:
   ```bash
   export SUPABASE_ACCESS_TOKEN="sbp_..."
   supabase secrets set REVENUECAT_WEBHOOK_SECRET="<the value>" \
     --project-ref ukulkbthsgkmihjcpzek
   ```
5. The Edge Function is **already deployed** (verified 2026-05-04). Redeploy if you change `supabase/functions/revenuecat-webhook/index.ts`:
   ```bash
   supabase functions deploy revenuecat-webhook \
     --project-ref ukulkbthsgkmihjcpzek --no-verify-jwt
   ```
6. Test: RC dashboard → Webhooks → Send Test Event → expect a row in `subscriptions` within 2s.

### AdMob

1. Sign up at <https://apps.admob.com>.
2. Create iOS app + Android app entries.
3. Per app, generate ad units:
   - Banner (320×50 standard)
   - Interstitial (full-screen)
4. Note **App ID** + ad unit ids per platform.

**GitHub secrets:**
| Name | Value |
|------|-------|
| `ADMOB_APP_ID_IOS` | `ca-app-pub-XXX~YYY` |
| `ADMOB_APP_ID_ANDROID` | Same format |
| `ADMOB_BANNER_IOS` | `ca-app-pub-XXX/YYY` |
| `ADMOB_BANNER_ANDROID` | Same |
| `ADMOB_INTERSTITIAL_IOS` | Same |
| `ADMOB_INTERSTITIAL_ANDROID` | Same |

After secrets are set, **also update the platform meta-data**:

#### iOS Info.plist
Edit `apps/mobile/ios/Runner/Info.plist`:
```xml
<key>GADApplicationIdentifier</key>
<string>YOUR_REAL_IOS_APP_ID</string>  <!-- replace ca-app-pub-3940256099942544~1458002511 -->
```

#### Android manifest
Edit `apps/mobile/android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="YOUR_REAL_ANDROID_APP_ID" />  <!-- replace ca-app-pub-3940256099942544~3347511713 -->
```

The current values are AdMob's universally-recognised TEST ids — they serve real ads with a "Test Ad" watermark and never accumulate revenue. iOS rejects builds that ship a non-test id without a valid AdMob app, so leave the test ids in until prod ad units are ready.

### Android Play Store
See `docs/SECRETS_REQUIRED.md` § Android Play Store. 5 secrets.

## What changes when secrets land

| Before secrets | After secrets |
|----------------|---------------|
| AdMob test ads with "Test Ad" watermark | Real ads, real eCPM |
| RC purchases work in-app but no server flag | Real purchases flow through to `subscriptions` table |
| Premium UX activated only via debug `simulateActivate()` | Premium UX activated by real RC entitlement |
| `release-ios.yml` workflow_dispatch fails at signing | TestFlight uploads succeed |
| `release-android-playstore.yml` fails at keystore step | Play Store internal track receives AAB |

## Verifying anti-tamper

Once a real purchase has been made through RC:

1. Check `public.subscriptions` row in Supabase dashboard. Status should be `active`, expires_at populated, plan one of `monthly`/`yearly`/`lifetime`.
2. From the app, signed in as that user, premium UX activates within ~1s (realtime stream).
3. **Tamper test:** root the device, edit Hive prefs box at `~/Library/Containers/com.awatv.mobile/Data/Library/Application Support/awatv-storage/`, change `premium:tier` to `{"tier":"premium",...}`, restart app.
4. Premium UX shows briefly (~50ms first frame), then `_refreshFromServer()` runs and the realtime stream re-asserts the actual server state. Tampering is undone.
5. **Cancel test:** in RC dashboard, fire CANCELLATION webhook. Within 1s the app's banner / quota / ad slots return to free tier.

## What to do if it gets cracked

If a user reports they've found a way to permanently flip premium:

1. The exploit is almost certainly in the **Supabase JWT** — the user is forging a session that maps to another user's premium row.
2. Check Supabase auth logs for the offending `user_id`.
3. If confirmed, RLS is fine but Apple/Google receipt-replay attacks are possible. Mitigate with RC's "transaction validation" feature in webhooks.
4. As a worst case, you can roll the Supabase project's JWT signing key (rotates all sessions, force re-login).

## Cost ceiling

- **RevenueCat**: free until $2.5K MTR (monthly tracked revenue), then 1% of additional revenue
- **AdMob**: free, takes 30% revenue share by default
- **Supabase**: Free plan supports 50K MAU, 500MB DB, 5GB bandwidth — far above current scale
- **Apple Developer**: $99/year
- **Google Play**: one-time $25
