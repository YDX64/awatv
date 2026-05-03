# AWAtv Flutter codebase audit

## TL;DR

AWAtv Flutter codebase has **~30 feature directories** vs Streas' 22 screens. Almost every Streas screen has a Flutter equivalent already. The primary gap is **visual** (palette + typography + component spacing match Streas), not functional.

This shifts the porting strategy from "build new screens" to **"re-skin existing screens to match Streas' Cherry-red Netflix aesthetic"**.

## Existing Flutter file mapping (Streas → AWAtv)

| Streas screen | AWAtv Flutter equivalent | Status |
|--------------|---------------------------|---|
| `app/welcome.tsx` | `apps/mobile/lib/src/features/onboarding/welcome_screen.dart` | ✅ exists, needs visual port |
| `app/login.tsx` | `apps/mobile/lib/src/features/auth/login_screen.dart` | ✅ exists, needs visual port |
| `app/signup.tsx` | inline in `onboarding/wizard_screen.dart` Step 2 | ⚠️ standalone screen missing — port from wizard |
| `app/who-watching.tsx` | `apps/mobile/lib/src/features/profiles/profile_picker_screen.dart` | ✅ exists, needs visual port |
| `app/add-profile.tsx` | `apps/mobile/lib/src/features/profiles/profile_edit_screen.dart` | ✅ exists, needs visual port |
| `app/account.tsx` | `apps/mobile/lib/src/features/auth/account_screen.dart` | ✅ exists, needs visual port |
| `app/paywall.tsx` | `apps/mobile/lib/src/features/premium/premium_screen.dart` | ✅ exists, needs visual port |
| `app/subtitle-picker.tsx` | `apps/mobile/lib/src/features/player/widgets/player_track_picker_sheet.dart` | ⚠️ partial — needs OpenSubtitles UI |
| `app/(tabs)/index.tsx` | `apps/mobile/lib/src/features/home/home_screen.dart` | ✅ exists, needs visual port |
| `app/(tabs)/channels.tsx` | `apps/mobile/lib/src/features/channels/` | ✅ exists, needs visual port |
| `app/(tabs)/movies.tsx` | `apps/mobile/lib/src/features/vod/` | ✅ exists, needs visual port |
| `app/(tabs)/series.tsx` | `apps/mobile/lib/src/features/series/` | ✅ exists, needs visual port |
| `app/(tabs)/search.tsx` | `apps/mobile/lib/src/features/search/` | ✅ exists, needs visual port |
| `app/(tabs)/guide.tsx` (EPG) | `awatv_ui/lib/src/widgets/epg_grid.dart` + features/channels | ✅ exists, needs polish |
| `app/(tabs)/favorites.tsx` | `apps/mobile/lib/src/features/favorites/` | ✅ exists, needs visual port |
| `app/(tabs)/settings.tsx` | `apps/mobile/lib/src/features/settings/` | ✅ exists |
| `app/detail/[id].tsx` | VOD detail screen (in vod/ dir) | ✅ exists, needs visual port |
| `app/player/[id].tsx` | `apps/mobile/lib/src/features/player/player_screen.dart` | ✅ exists |
| `app/tv-player.tsx` | `apps/mobile/lib/src/features/player/player_screen.dart` | ✅ exists, may need live-mode polish |
| `app/add-source.tsx` | `apps/mobile/lib/src/features/playlists/` | ✅ exists, needs visual port |

## Existing Riverpod providers (state management)

| Streas Context | AWAtv Riverpod | Status |
|---------------|----------------|---|
| `AuthContext` | `auth/auth_controller.dart` | ✅ richer than Streas (magic link + password + signUp) |
| `ProfileContext` | `shared/profiles/*` + `profile_scoped_providers.dart` | ✅ exists |
| `ContentContext` | distributed across home/channels/vod/series/playlists providers | ✅ exists |
| `SubtitleContext` | `shared/player/*` (subtitle handling inside player engine) | ⚠️ no dedicated subtitle context — verify if OpenSubtitles search exists |
| `SubscriptionProvider` (RevenueCat mock) | `shared/premium/*` | ⚠️ different model — uses Remote Config + manual tier flag, no RevenueCat |

## Design tokens delta (current AWAtv → Streas)

| Token | AWAtv current | Streas target | Delta |
|-------|--------------|--------------|-------|
| `primary` | `#6C5CE7` (electric purple) | `#E11D48` (cherry red) | **HARD SWITCH** |
| `secondary` | `#00D4FF` (cyan) | `#E11D48` (same as primary, no separate accent) | remove or repurpose |
| `background` | `#0A0D14` (indigo black) | `#0a0a0a` (true black) | shift |
| `surface` | `#14181F` | `#141414` | shift |
| `surfaceHigh` | `#1C2230` | `#1c1c1c` | shift |
| `outline` | `#2A3040` | `#282828` | shift |
| `liveAccent` | `#FF3B5C` | `#E11D48` | match primary in Streas |
| `success` | `#26DE81` | (no separate green) | keep |
| `warning` | `#FFA502` | `#f59e0b` (gold) | shift |
| `radius` | 12 (`DesignTokens.radiusM`) | 8 | reduce |
| Font | system default | Inter (400/500/600/700) | add Inter |
| Theme modes | light + dark | dark-only | force dark when in Streas mode |

### Gradient changes

- Streas: no `auroraGradient` — flat black background
- Streas: no separate `brandGradient` (cherry only)
- AWAtv aurora gradient should be replaced with flat `background` for Streas-mode panels

## Features unique to AWAtv (NOT in Streas — keep as bonus)

- `catchup`, `downloads`, `multistream`, `parental`, `recordings`, `reminders`, `smart_alerts`, `stats`, `themes`, `voice_search`, `watch_party`, `watchlist`
- Background playback, PiP, cast, channel history, network info, observability
- Custom theme builder (user-selectable accent/radius)
- Magic link auth callback
- Update boot check (auto-updater)

These are **competitive advantages** — Streas doesn't have them. Keep them but ensure they don't fight the new visual language.

## Features in Streas not (yet) in AWAtv

- **OpenSubtitles search** — Streas has free/premium gating. AWAtv player has SRT loading but no search-by-show metadata flow.
- **External player deep linking** — Streas can hand off to VLC/MX/nPlayer for unsupported formats. AWAtv uses media_kit + flutter_vlc_player internally.
- **RevenueCat integration** (mock or real) — AWAtv uses its own premium tier system via Remote Config.
- **Standalone signup screen** — currently only inside wizard.

## Recommendations

1. **Phase 1 — design tokens (1 commit)**: Update `BrandColors` to Cherry red palette, add Inter font, drop aurora.
2. **Phase 2 — layout polish (multiple commits)**: For each Streas screen, open the corresponding Flutter screen and adjust layout to 1:1 match. Use the agent-produced spec docs as the visual spec.
3. **Phase 3 — feature gaps**: OpenSubtitles search UI in subtitle picker; standalone signup screen (extract from wizard); RevenueCat integration if user wants real billing.
4. **Phase 4 — verification**: Side-by-side screenshot comparison via Streas web export vs Flutter web build.

The user's phrase "birebir görünüm ve özellikleri" is satisfied if Phase 1 + 2 land — feature parity is mostly already there.
