# Streas → AWAtv Flutter Port Spec: Auth + Profile Flow

**Source:** `/tmp/Streas/artifacts/iptv-app/` (React Native / Expo)
**Target:** `/Users/max/AWAtv/apps/mobile/lib/` (Flutter / Riverpod)
**Scope:** Auth (`welcome`, `login`, `signup`, `account`) + Profile (`who-watching`, `add-profile`)

---

## 0. Design Tokens (from `constants/colors.ts`)

The Streas palette is "Cherry red Netflix-inspired" on near-black. Map these to a Flutter `ThemeExtension` named `StreasColors`:

| Token | Hex | Flutter Constant | Usage |
|---|---|---|---|
| `primary` / `tint` / `accent` (CHERRY) | `#E11D48` | `kCherry` | CTAs, switches active, links, lock badge, edit badge |
| `primaryDark` (CHERRY_DARK) | `#9F1239` | `kCherryDark` | Gradient start (paired with cherry as gradient end) |
| `cherryDim` | `#BE123C` | `kCherryDim` | (Reserved — currently unused in auth flow) |
| `background` | `#0a0a0a` | `kBgBase` | Scaffold background on every screen |
| `card` | `#141414` | `kSurfaceCard` | PIN sheet, account cards, mosaic dark tile |
| `surface` | `#111111` | `kSurface` | (Reserved) |
| `surfaceHigh` / `secondary` / `muted` | `#1c1c1c` | `kSurfaceHigh` | Numpad keys (`rgba(255,255,255,0.08)` overlay) |
| `border` / `input` | `#282828` | `kBorderDefault` | Divider lines, card borders |
| `mutedForeground` | `#808080` | `kFgMuted` | Section labels, secondary text |
| `destructive` | `#ef4444` | `kDestructive` | Error text, delete button, error border |
| `gold` | `#f59e0b` | `kGold` | (Reserved — premium tier) |
| Mosaic warm tile | `#0d1525` | `kMosaicWarm` | Welcome backdrop |
| Mosaic cool tile | `#0a1020` | `kMosaicCool` | Welcome backdrop |
| Foreground white | `#ffffff` | `kFg` | Primary text |
| Frosted overlay 7% | `rgba(255,255,255,0.07)` | `kInputFill` | Text input background |
| Frosted overlay 8% | `rgba(255,255,255,0.08)` | `kKeypadFill` | Numpad key fill |
| Border subtle | `rgba(255,255,255,0.2)` | `kInputBorder` | Default input border |
| Border error | `#ef4444` | `kDestructive` | Input border on error |

**Radius scale:** 6 (small), 8 (input/CTA), 10 (medium), 12 (card), 14 (modal), 16 (sheet), 18 (large profile), 20 (logo mark).
**Corner radius default** in `colors.ts` = `8`.

**Typography (Inter):**
- `Inter_400Regular` → `FontWeight.w400`
- `Inter_500Medium` → `FontWeight.w500`
- `Inter_600SemiBold` → `FontWeight.w600`
- `Inter_700Bold` → `FontWeight.w700`

Use `google_fonts: ^6.x` with `GoogleFonts.interTextTheme(...)`. Letter-spacing is significant on CTAs (1.5) and the wordmark (2). Map a `TextTheme` once in `awa_tv_app.dart`.

---

## 1. AuthContext State Machine

`AuthContext.tsx` exposes three states: `loading | guest | authenticated`. Riverpod equivalent: a `sealed` `AuthState` plus an `AsyncNotifier<AuthState>`.

**State transitions:**

```
[boot] ─► loading
loading ─(supabase null OR no session)─► guest
loading ─(session exists)──────────────► authenticated
guest ───(continueAsGuest no-op)───────► guest
guest ───(signIn ok / signUp ok)───────► authenticated
authenticated ─(signOut / deleteAccount)► guest
authenticated ─(token refresh fails)────► guest  // via supabase.onAuthStateChange
```

**Side effects on entry:**
- `loading → authenticated` triggers `ProfileController.loadProfiles()` keyed by `user.id`
- `authenticated → guest` triggers profile reset (key becomes `"guest"`), preserving local guest profiles
- Router redirects: `guest` → `/welcome`, `authenticated && needsProfileSelection` → `/who-watching`, otherwise `/(tabs)`

**Flutter port:**

```
File: lib/src/shared/auth/auth_state.dart                (existing — augment)
File: lib/src/shared/auth/auth_controller.dart           (existing — augment)
```

`AuthState` becomes a `sealed class` with three cases: `AuthLoading`, `AuthGuest`, `AuthAuthenticated(User user, Session session)`. `AuthControllerNotifier extends AsyncNotifier<AuthState>` listens to `Supabase.instance.client.auth.onAuthStateChange`. Gate construction with `SUPABASE_CONFIGURED = env.supabaseUrl.isNotEmpty && env.supabaseAnonKey.isNotEmpty`. Existing `auth_guard.dart` already provides a `GoRouter` redirect — extend its `redirect` to read `authControllerProvider` and respect `isConfigured`.

**Recommended Riverpod providers:**
- `authControllerProvider` — `AsyncNotifierProvider<AuthController, AuthState>` (existing, augment)
- `isAuthenticatedProvider = Provider<bool>` (selects `state is AuthAuthenticated`)
- `isGuestProvider = Provider<bool>` (selects `state is AuthGuest`)
- `isSupabaseConfiguredProvider = Provider<bool>` (reads env)
- `currentUserProvider = Provider<User?>` (extracts `user` from authenticated state)

---

## 2. WelcomeScreen (`app/welcome.tsx`)

### Visual layout
- **Backdrop:** 4-row × 3-col mosaic of solid color tiles (12 tiles total, each `33.33% × screenHeight/4`). Tile colors cycle: `#141414`, `#0d1525`, `#0a1020` based on `i % 3`. Overlaid with vertical `LinearGradient` from `rgba(5,9,18,0.3)` → `rgba(5,9,18,0.7)` → `rgba(5,9,18,0.95)` → `#0a0a0a`.
- **Content column:** centered, `paddingHorizontal: 28`, `paddingTop: insets.top + 20`, `paddingBottom: insets.bottom + 30`.
- **Logo block** (top, marginTop 40): vertical stack, gap 8.
  - `logoMark`: `72×72` cherry square, radius `20`, centers white text "AW" at `26pt Inter_700Bold` letter-spacing 1.
  - `logoText`: "Awa**TV**" (TV in cherry) at `38pt Inter_700Bold` letter-spacing 2, white.
  - `tagline`: "Your Entertainment Hub" at `14pt Inter_400Regular`, color `rgba(255,255,255,0.5)`, letter-spacing 1.
- **Spacer:** `flex: 1`.
- **Buttons block** (bottom, gap 12, 100% width):
  - **Primary CTA** (`loginBtn`): `paddingVertical: 16`, radius `10`, full-width, gradient overlay `["#9F1239" → "#E11D48"]` left-to-right (`{x:0,y:0}→{x:1,y:0}`). Label: `15pt Inter_700Bold` letter-spacing 1.5 white.
  - **Secondary CTA** (`signupBtn`, only when `isConfigured`): same dims, transparent background, 1px border `rgba(255,255,255,0.25)`, label color `rgba(255,255,255,0.85)`.
  - **Tertiary** (`uploadBtn`): row icon + text, `paddingVertical: 14`, marginTop 8, no background. Icon: `Feather.upload` 14px / muted white. Label: `13pt Inter_500Medium` letter-spacing 1.
  - **Quaternary** (`guestBtn`, only when `isConfigured`): `12pt Inter_400Regular` `rgba(255,255,255,0.4)`.
- **Unconfigured banner:** `rgba(59,130,246,0.12)` fill, 1px `rgba(59,130,246,0.3)` border, radius 10, `padding: 12`, gap 10. `Feather.info` 14 cherry + body text `12pt Inter_400Regular` `rgba(255,255,255,0.6)` lineHeight 17.

### Animations
On mount: `Animated.sequence([parallel([spring(logoScale 0.8→1 tension 50 friction 8), timing(logoOpacity 0→1 600ms)]), timing(btnOpacity 0→1 400ms delay 200ms)])`.
Stack option: `animation: 'fade'` (default for root entry).

### Touchable feedback
All `TouchableOpacity` with `activeOpacity={0.88}` for primary, `0.7` for tertiary.

### Behavior
- `LOGIN` → `router.push("/login")`
- `CREATE AN ACCOUNT` → `router.push("/signup")`
- `BROWSE AS GUEST` (only when unconfigured) / `Continue as Guest` → `continueAsGuest(); router.replace("/(tabs)")`
- `UPLOAD YOUR PLAYLIST` → `pickPlaylistFile()` (DocumentPicker `*/*` for `.m3u`/`.m3u8`), then `addSourceFromFile(file)`, then `continueAsGuest()`, replace to tabs. On error: silent `console.warn`. Loading flag swaps label to "Loading playlist…".

### Data flow
- Reads `useAuth().isConfigured` and `continueAsGuest`.
- Reads `useContent().addSourceFromFile`.
- No Supabase call. No AsyncStorage write.

### Flutter port mapping
- **Closest existing file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/onboarding/welcome_screen.dart`. Currently exists but assume minimal — needs full rewrite.
- **Changes:** Replace any single-button welcome with the four-tier CTA stack. Add the mosaic backdrop and gradient overlay. Wire conditional rendering on `isSupabaseConfiguredProvider`.
- **Riverpod provider:** No new state — reads `authControllerProvider`, `isSupabaseConfiguredProvider`, and `playlistImportControllerProvider` (existing in `service_providers.dart` — verify and extend).
- **Widget tree:**
  ```
  Scaffold(backgroundColor: kBgBase)
    └─ Stack
        ├─ Positioned.fill: GridView.count(crossAxisCount: 3, ...) of Container tiles
        ├─ Positioned.fill: DecoratedBox(LinearGradient vertical)
        └─ SafeArea
            └─ Padding(horizontal: 28)
                └─ Column
                    ├─ AnimatedBuilder(scale + opacity): _LogoBlock
                    ├─ Spacer()
                    └─ AnimatedOpacity(_ButtonStack)
                        ├─ _GradientButton(label: "LOGIN") (when configured)
                        ├─ _OutlinedButton(label: "CREATE AN ACCOUNT") (when configured)
                        ├─ _InfoBanner(...) (when !configured)
                        ├─ _GradientButton(label: "BROWSE AS GUEST") (when !configured)
                        ├─ _TextButton(icon: upload, label: "UPLOAD YOUR PLAYLIST")
                        └─ _TextButton(label: "Continue as Guest") (when configured)
  ```
- Use `flutter_animate` for the entrance, or `AnimationController` with a `TweenSequence` (parallel scale + opacity, then opacity for buttons with 200ms delay).
- Use `file_picker: ^x.x` for the playlist upload. Existing playlist import logic in AWAtv (in `service_providers.dart`) handles `.m3u` parsing.
- Logo mark gradient: pure cherry fill (no gradient on the box itself); only the LOGIN button has the cherry-dark→cherry gradient.

---

## 3. LoginScreen (`app/login.tsx`)

### Visual layout
Two-step (email → password), shares input.

- **Header:** row, `paddingHorizontal: 16`, `paddingTop: insets.top + 12`, `paddingBottom: 8`. Single back button (`40×40` square, `Feather.chevron-left` size 24 white). On step 2, the back button reverts to step 1 instead of popping.
- **Content:** column, `paddingHorizontal: 28`, `paddingTop: 24`, gap 14.
  - **Title:** "Log in with your email" — `26pt Inter_700Bold` white.
  - **Subtitle:** explainer about cloud sync — `13pt Inter_400Regular` `rgba(255,255,255,0.5)` lineHeight 20.
  - **Email field:** row with TextInput inside `inputBox`. `borderRadius: 8`, `borderWidth: 1`, `paddingHorizontal: 16`, `paddingVertical: 16` (iOS) / `12` (Android), background `rgba(255,255,255,0.07)`. Border: `rgba(255,255,255,0.2)` default, `transparent` when on step 2 (locked), `#ef4444` on error. Placeholder color `rgba(255,255,255,0.35)`.
  - **Password field (step 2 only):** same input box plus trailing `Feather.eye` / `eye-off` (size 18, color `rgba(255,255,255,0.4)`), tap to toggle `secureTextEntry`.
  - **Error row:** `Feather.alert-circle` 13px destructive + `12pt Inter_400Regular` destructive text.
  - **"Forgot password?"** (step 2 only, alignSelf flex-start): `13pt Inter_500Medium` cherry.
  - **Email recap (step 2):** stack: label "You'll be logging in with:" `12pt regular muted` and value `14pt Inter_600SemiBold` white.
  - **CTA `ctaBtn`:** marginTop 8, `paddingVertical: 16`, `borderRadius: 8`, gradient `[#9F1239 → #E11D48]` left-to-right. Label "CONTINUE" (step 1) or "LOG IN" (step 2), `15pt Inter_700Bold` letter-spacing 1.5. Loading state: `ActivityIndicator` color white, `opacity: 0.7` on the button.
  - **Signup link row:** centered row, marginTop 8. "New to AwaTV? " muted + "SIGN UP" cherry `13pt Inter_700Bold`.

### Behavior
- **Validation step 1:** email must be non-empty trimmed and contain `@` (no real regex). Failure → inline error.
- **Step 1 → 2:** sets `step="password"`, `setTimeout 100ms` then focuses password field.
- **Submit step 2:** requires non-empty password. Calls `signIn(email, password)`. Error → set `error` message from Supabase. Success → `router.replace("/who-watching")`.
- **Keyboard:** `KeyboardAvoidingView` with `behavior="padding"` on iOS, `"height"` on Android. `returnKeyType="next"` for email (submits step 1), `"done"` for password (submits sign-in).

### Data flow
- Reads `useAuth().signIn`.
- Calls `supabase.auth.signInWithPassword({ email, password })` → returns `{ error?: string }`.
- No AsyncStorage write here; Supabase auth client persists session via `ExpoSecureStoreAdapter` in `lib/supabase.ts`.

### Flutter port mapping
- **Closest existing file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/auth/login_screen.dart` (exists; replace).
- **Changes:** Replace single-form layout with two-step state. Existing screen likely uses magic-link only (see `magic_link_callback_screen.dart`) — switch to `signInWithPassword`. Reuse `auth_controller.dart`'s `signIn` method (add if missing).
- **Riverpod provider:**
  - `loginFormControllerProvider = AutoDisposeNotifierProvider<LoginFormController, LoginFormState>` where `LoginFormState` carries `{step: LoginStep, email, password, showPassword, error, isLoading}`.
- **Widget tree:**
  ```
  Scaffold(backgroundColor: kBgBase, resizeToAvoidBottomInset: true)
    └─ SafeArea
        └─ Column
            ├─ _BackButtonRow(onTap: step==password ? backToEmail : pop)
            └─ Expanded
                └─ SingleChildScrollView (keyboardDismissBehavior: onDrag)
                    └─ Padding(horizontal: 28, top: 24)
                        └─ Column(crossAxis: stretch, spacing: 14)
                            ├─ Text("Log in with your email", style: title)
                            ├─ Text(subtitle, style: muted)
                            ├─ _StreasInput(controller: email, locked: step==password)
                            ├─ if (step == password) _StreasInput.password(...)
                            ├─ if (error != null) _ErrorRow(error)
                            ├─ if (step == password) _ForgotLink()
                            ├─ if (step == password) _EmailRecap(email)
                            ├─ _GradientCta(label, isLoading, onTap)
                            └─ _SignupLinkRow()
  ```
- Build `_StreasInput` and `_GradientCta` as shared widgets in `lib/src/features/auth/widgets/`.
- Use `TextInputAction.next` / `done` to mirror `returnKeyType`.

---

## 4. SignupScreen (`app/signup.tsx`)

### Visual layout
Three-step wizard with progress bar.

- **Header:** row with back button left, "Step N of 3" label center (`13pt Inter_500Medium` muted), `40×40` placeholder right. `paddingHorizontal: 16`, `paddingBottom: 4`.
- **Progress track:** 2px height, full width, `rgba(255,255,255,0.1)` bg. Fill width = `(step/3)*100%`, fill color cherry.
- **Content:** scrollable, `paddingHorizontal: 28`, `paddingTop: 28`, gap 16.
  - **Step tag:** "SIGN UP" — `11pt Inter_700Bold` letter-spacing 2 `rgba(255,255,255,0.4)`.
  - **Step-specific title:** `26pt Inter_700Bold` white. Subtitle `13pt regular` muted lineHeight 20.

**Step 1 (email):**
- Email input (autofocus).
- **Marketing consent checkbox row:** custom 20×20 rounded-4 checkbox. Unchecked: transparent fill, border `rgba(255,255,255,0.3)` 1.5px. Checked: cherry fill, cherry border, white `Feather.check` 12px. Body text `12pt Inter_400Regular` `rgba(255,255,255,0.6)` lineHeight 18.
- **Legal blob:** `11pt Inter_400Regular` `rgba(255,255,255,0.4)` lineHeight 17. Inline cherry-colored "Subscriber Agreement" / "Privacy Policy" tokens (both currently inert).
- **CTA:** "AGREE & CONTINUE" gradient.

**Step 2 (password):**
- Password input with eye toggle.
- **Strength meter:** 4-segment row of 3px bars, gap 4, flex 1 each. Filled bars take `STRENGTH_COLORS[strength]`. Strength label (50px wide) right-aligned to bars. Algorithm:
  - +1 if `length ≥ 6`
  - +1 if `length ≥ 10`
  - +1 if uppercase letter present
  - +1 if digit present
  - +1 if special char present
  - Clamp to 4. Colors: `["#ef4444","#f97316","#eab308","#22c55e","#22c55e"]`. Labels: `["", "Weak","Fair","Good","Strong","Strong"]`.
- **Hint:** "Use a minimum of 6 characters…" `11pt Inter_400Regular` `rgba(255,255,255,0.4)`.
- **Email recap** (same component as login).
- **CTA:** "SIGNUP" gradient.

**Step 3 (birthdate):**
- **Pseudo-input:** TouchableOpacity styled like an input box. Shows placeholder "MM/DD/YYYY" (muted) or formatted "Month DD, YYYY" (white) when populated. Tap toggles a custom date picker.
- **Inline picker** (200px height, row of 3 ScrollViews): Months (`flex: 1`), Days (`flex: 0.6`), Years (`flex: 0.8`). Each item: `paddingVertical: 10`, `paddingHorizontal: 8`. Selected: background `rgba(59,130,246,0.3)` (note: this is a leftover blue tint — port to cherry tint `rgba(225,29,72,0.25)` for brand consistency), text cherry. Unselected text `rgba(255,255,255,0.7)`. "Done" floating link top-right (`#E11D48` 15pt semibold). Container: radius 12, 1px border `rgba(255,255,255,0.15)`, bg `rgba(15,26,46,0.98)`.
- **CTA:** "CONFIRM" gradient with `ActivityIndicator` while loading.

### Behavior
- **Step 1 → 2:** validate email contains `@`.
- **Step 2 → 3:** validate `password.length ≥ 6`.
- **Step 3 confirm:** call `signUp({email, password, birthdate, marketingConsent})`. On success → `router.replace("/who-watching")`. Error → inline destructive text.
- **Birthdate format:** `${year}-${MM}-${DD}` (ISO) only sent if all three fields filled.
- **Back button:** decrement step or pop if step 1.

### Data flow
- Reads `useAuth().signUp`.
- Calls `supabase.auth.signUp({email, password, options: { data: { birthdate, gender, marketing_consent }}})`.

### Flutter port mapping
- **Closest existing file:** none. Create `/Users/max/AWAtv/apps/mobile/lib/src/features/auth/signup_screen.dart`.
- **Riverpod provider:**
  - `signupFormControllerProvider = AutoDisposeNotifierProvider<SignupFormController, SignupFormState>` with `{step: 1|2|3, email, password, showPassword, marketing, birthMonth, birthDay, birthYear, isLoading, error}`.
  - `passwordStrengthProvider = Provider.family<int, String>((ref, pwd) => ...)` — pure function, but parameterizing makes it easy to test.
- **Widget tree:**
  ```
  Scaffold
    └─ SafeArea
        └─ Column
            ├─ _SignupHeader(step, onBack)
            ├─ LinearProgressIndicator(value: step/3, color: kCherry, backgroundColor: kBorderDefault)
            └─ Expanded
                └─ SingleChildScrollView
                    └─ Padding(horizontal: 28, top: 28)
                        └─ Column(spacing: 16)
                            ├─ Text("SIGN UP", style: stepTag)
                            └─ AnimatedSwitcher(child: _Step1 | _Step2 | _Step3)
  ```
  Each step is a `StatelessWidget` reading `signupFormControllerProvider`. Step 3 uses `showCupertinoModalPopup` with a `CupertinoDatePicker(mode: date, maximumDate: now)` — this is more idiomatic on iOS and provides accessibility on both platforms. Optionally, replicate the inline 3-column wheel using `ListWheelScrollView` to preserve the visual character.
- **Strength meter:** stateless `_StrengthMeter(strength: int)` widget — `Row` of 4 `Expanded(child: Container(height: 3, color: ...))` separated by `SizedBox(width: 4)`.
- **Marketing checkbox:** `GestureDetector` wrapping a `Container` (20×20, border 1.5px, radius 4) with conditional `Icon(Icons.check, size: 12)`. Avoid Material `Checkbox` (wrong padding).

---

## 5. WhoWatchingScreen (`app/who-watching.tsx`)

### Visual layout
- **Top bar:** row, `paddingHorizontal: 20`, `paddingTop: insets.top + 8`, `paddingBottom: 12`.
  - When editing: title "Edit Profiles" `24pt Inter_700Bold` left.
  - Right: edit toggle button. Idle: 1px border `rgba(255,255,255,0.4)`, padding `20×8`, radius 6, label "Edit Profile" `13pt Inter_600SemiBold` white. Active: white fill, label "Done" black.
- **Centered scroll body:** `paddingHorizontal: 20`, `paddingTop: 20`, `paddingBottom: 60`, `alignItems: center`.
  - **Title (idle only):** "Who's Watching?" `26pt Inter_700Bold` white, marginBottom 32.
  - **Profile grid:** `flexDirection: row`, `flexWrap: wrap`, `gap: 20`, `justifyContent: center`, full-width.
    - Each tile: 100px wide, gap 10, alignItems center.
    - **Avatar:** `90×90` rounded-10 square, fill = `profile.color`, border 2px transparent. Active profile (idle mode only): border 3px white. Edit-mode: 20px badge bottom-right with cherry fill and white `Feather.edit-2` 10px. PIN-locked profile (idle): 20px black-80% badge bottom-right with white `Feather.lock` 10px. Centered emoji `44pt`.
    - **Name:** `13pt Inter_600SemiBold` white, single-line with ellipsis.
  - **"Add Profile" tile:** same dims, border `rgba(255,255,255,0.2)`, fill `rgba(255,255,255,0.1)`, content = `Feather.plus` 32 `rgba(255,255,255,0.6)`. Label muted.

### PIN modal
Triggered when tapping a PIN-protected profile in idle mode.
- Full-screen `Modal` with `transparent`, `animationType="fade"`. Overlay `rgba(0,0,0,0.8)` centered.
- Sheet: 300px wide, radius 16, bg `#141414`, `padding: 24`, gap 12, alignItems center.
  - Title: "Enter Profile PIN" `17pt Inter_700Bold` white.
  - **Mini avatar:** 68×68 rounded-12 with profile's color, centered emoji `36pt`.
  - **Name:** `14pt Inter_600SemiBold` white.
  - **Dots row:** four 14×14 rounded-7 circles, gap 14. Filled = white, empty = `rgba(255,255,255,0.2)`.
  - **Error line:** "Incorrect PIN. Try again." destructive `12pt`.
  - **Numpad:** 4 rows × 3 cols, 220px wide, gap 4. Each key: 64×54, radius 10, bg `rgba(255,255,255,0.08)`, label `22pt Inter_400Regular` white. Layout: `1 2 3 / 4 5 6 / 7 8 9 / "" 0 ⌫`. Empty cell rendered with `opacity: 0` to preserve layout.
  - Cancel link: `14pt Inter_500Medium` `rgba(255,255,255,0.5)`.

### Behavior
- **Tap profile (idle):** if `profile.pin` set, open PIN modal; else `setActiveProfile(profile)` then `router.replace("/(tabs)")`.
- **Tap profile (edit mode):** push `/add-profile?profileId={id}`.
- **Tap "Add Profile":** push `/add-profile` (no profileId).
- **Numpad input:**
  - `⌫` deletes last digit.
  - Digits append (only if `length < 4`).
  - On reaching length 4: 200ms timeout, then call `setActiveProfile(pinProfile, pin)`. Wrong PIN → set error, clear input. Right PIN → close modal, replace to tabs.
- **Edit toggle:** flips local `isEditing` flag (no persistence).
- **Loading guard:** if `!isLoaded`, render nothing.

### Data flow
- Reads `useProfile().profiles`, `activeProfile`, `setActiveProfile`, `isLoaded`.
- `setActiveProfile` writes `AsyncStorage["awatv_active_profile_<userId>"] = profile.id`. PIN check is in-memory (`profile.pin === pin`).

### Flutter port mapping
- **Closest existing file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/profiles/profile_picker_screen.dart` (exists; needs upgrade for edit mode + PIN modal styling).
- **Companion file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/profiles/widgets/pin_entry_sheet.dart` already exists — adapt to the spec dimensions above.
- **Riverpod providers:**
  - `profileControllerProvider = AsyncNotifierProvider<ProfileController, List<Profile>>` (existing in `profile_controller.dart` — verify CRUD methods).
  - `activeProfileProvider = NotifierProvider<ActiveProfileNotifier, Profile?>`.
  - `whoWatchingEditModeProvider = StateProvider<bool>` (auto-dispose, scoped to screen lifetime).
- **Widget tree:**
  ```
  Scaffold(backgroundColor: kBgBase)
    └─ SafeArea(top: true, bottom: false)
        └─ Column
            ├─ _TopBar(isEditing, onToggle)
            └─ Expanded
                └─ SingleChildScrollView
                    └─ Padding(horizontal: 20, top: 20, bottom: 60)
                        └─ Column
                            ├─ if (!isEditing) Text("Who's Watching?", title)
                            ├─ const SizedBox(height: 32)
                            └─ Wrap(spacing: 20, runSpacing: 20, alignment: center,
                                    children: [
                                      ...profiles.map((p) => _ProfileTile(profile: p, isEditing, isActive)),
                                      _AddProfileTile(),
                                    ])
  ```
- PIN modal: `showDialog(barrierColor: Colors.black.withOpacity(0.8), barrierDismissible: true, builder: (_) => Center(child: PinEntrySheet(profile: p)))`. Use `HapticFeedback.lightImpact()` on each digit and `mediumImpact()` on success/error.
- Numpad: implement as `GridView.count(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, children: [...])` or a `Wrap` with 12 fixed-size children. The empty cell should be `Visibility(visible: false, maintainSize: true, ...)`.

---

## 6. AddProfileScreen (`app/add-profile.tsx`)

### Visual layout
- **Header:** row, `paddingHorizontal: 20`, `paddingBottom: 16`. Left "Cancel" `15pt Inter_500Medium` `rgba(255,255,255,0.6)`. Center title "Add Profile" / "Edit Profile" `17pt Inter_700Bold`. Right "Save" / "Done" `15pt Inter_700Bold` white.
- **Primary-profile note** (edit mode + isPrimary): margin 16, padding 12, radius 10, 1px border `rgba(255,255,255,0.1)`, bg `rgba(255,255,255,0.06)`. Body `12pt Inter_400Regular` `rgba(255,255,255,0.55)` lineHeight 18.
- **Big avatar section:** centered, marginTop 16, marginBottom 8.
  - 90×90 rounded-18 box, fill = `selectedColor`, centered emoji 50pt.
  - 26×26 cherry-fill rounded-13 edit badge at `bottom: 0, right: 35%` (visually clipped to tile corner) with white `Feather.edit-2` 12px.
- **Avatar picker (collapsible)**, `paddingHorizontal: 20`, marginBottom 8.
  - Section label "Choose Avatar" — `11pt Inter_700Bold` letter-spacing 1.5 `rgba(255,255,255,0.45)`, marginBottom 10.
  - **Emoji grid:** `flexWrap: row`, gap 10. Each cell: 52×52 rounded-12, default fill `rgba(255,255,255,0.08)`, emoji 28pt. **Selected cell:** fill = `selectedColor`, 2px white border. Layout: 24 emojis flow ~6 per row depending on screen width (375px: 6 per row).
  - Section label "Choose Color" (marginTop 16).
  - **Color grid:** 12 circles, each 36×36 rounded-18, fill = the color hex. Selected: 3px white border. Layout: 7 per row on 375 width.

  **Avatar inventory** (24 emojis, indexed):
  ```
  0  🎭   1  🎮   2  🎵   3  🎨
  4  🚀   5  🌟   6  🦋   7  🐉
  8  🎪   9  🌈  10  🎯  11  🏆
  12 🦁  13  🐺  14  🦊  15  🐼
  16 🌊  17  🔥  18  ⚡  19  ❄️
  20 🌙  21  ☀️  22  🌴  23  🎸
  ```

  **Color inventory** (12 hex):
  ```
  0  #E11D48   1  #8b5cf6   2  #ec4899   3  #ef4444
  4  #f97316   5  #eab308   6  #22c55e   7  #14b8a6
  8  #E11D48   9  #06b6d4  10  #a855f7  11  #f43f5e
  ```
  Note: indices 0 and 8 are duplicates — port preserves the duplication for parity (or de-dupes if AWAtv design system says so — flag for product decision).

- **Name input:** `paddingHorizontal: 20`, marginBottom/Top 8. 1px border, radius 8, padding `16/15`, bg `rgba(255,255,255,0.06)`, text 16pt regular white. Border destructive on error. `maxLength: 20`.
- **Section label:** "PLAYBACK AND LANGUAGE SETTINGS" — `11pt Inter_700Bold` letter-spacing 1.5 `rgba(255,255,255,0.4)`, paddingHorizontal 20, marginBottom 8, marginTop 16.
- **Setting card:** marginHorizontal 16, radius 12, 1px border `rgba(255,255,255,0.08)`, bg `rgba(15,26,46,0.8)`, overflow hidden.
  - **Junior Mode row** (hidden when editing primary profile): row gap 12, padding `16/14`, hairline bottom border `rgba(255,255,255,0.07)`. Label "Junior Mode" `14pt Inter_500Medium` white. Description `11pt regular` `rgba(255,255,255,0.45)` lineHeight 16. Right: native `Switch` with track `rgba(255,255,255,0.15)` off / cherry on, thumb white.
  - **Profile PIN row:** same template. Toggle controls visibility of the PIN entry section.
  - **PIN entry section** (when enabled): `padding: 16`, alignItems center, gap 12.
    - Label "Limit access to this profile with a 4-digit PIN." center muted.
    - Dots row: same 14×14 circles but with 1px `rgba(255,255,255,0.3)` border. Filled = cherry.
    - Numpad: 200px wide, key 58×48, radius 8, bg `rgba(255,255,255,0.08)`, label 20pt regular white.
- **Delete profile button** (edit + non-primary): `paddingVertical: 18`, marginTop 20, label destructive `15pt Inter_600SemiBold` center.
- **Delete confirm box** (replaces button after first tap):
  - margin 16, bg `rgba(15,26,46,0.9)`, radius 14, padding 20, alignItems center, gap 8.
  - Title "Delete this profile?" `16pt Inter_700Bold`.
  - Sub "All watch history and settings will be lost." `13pt regular` `rgba(255,255,255,0.5)` center.
  - Two buttons row, gap 12, full width: "Cancel" 1px white-20 border / "Delete" destructive fill, both `paddingVertical: 12`, radius 8.

### Behavior
- **Save:** if `name.trim().empty` → set name error and abort. Build patch `{name, avatar, color, juniorMode, pin: enablePin && pin.length===4 ? pin : null}`. Call `updateProfile(id, patch)` or `createProfile(patch)`. `router.back()`.
- **Toggle PIN off:** clears `pin` to `""`.
- **Toggle Junior Mode:** local state only until save.
- **Delete:** if `existingProfile.isPrimary` → no-op (button is hidden). Otherwise call `deleteProfile(id)`, then `router.replace("/who-watching")`.
- **Primary profile constraints:** cannot delete, cannot enable Junior Mode (row hidden).

### Data flow
- Reads `profileId` from route params.
- Reads/writes via `useProfile()`: `profiles`, `createProfile`, `updateProfile`, `deleteProfile`.
- Writes `AsyncStorage["awatv_profiles_<userId>"]` (JSON list) and best-effort `supabase.from("profiles").upsert(...)` per profile.

### Flutter port mapping
- **Closest existing file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/profiles/profile_edit_screen.dart` (exists; replace).
- **Companion:** `/Users/max/AWAtv/apps/mobile/lib/src/features/profiles/widgets/profile_avatar.dart` — extend to support the big variant (90×90 with edit badge).
- **Riverpod provider:**
  - `profileEditControllerProvider = AutoDisposeNotifierProviderFamily<ProfileEditController, ProfileEditState, String?>` keyed by `profileId` (null = create).
  - `ProfileEditState` carries `{name, selectedAvatar, selectedColor, juniorMode, pin, enablePin, showAvatarPicker, showDeleteConfirm, nameError}`.
- **Widget tree:**
  ```
  Scaffold
    └─ SafeArea
        └─ Column
            ├─ _ProfileEditHeader(isEditing, onCancel, onSave)
            └─ Expanded
                └─ SingleChildScrollView (keyboardDismissBehavior: onDrag)
                    └─ Column
                        ├─ if (isPrimary) _PrimaryNote()
                        ├─ _BigAvatarTrigger(emoji, color, onTap)
                        ├─ if (showPicker) _AvatarPicker(selectedAvatar, selectedColor, ...)
                        │     ├─ _SectionLabel("CHOOSE AVATAR")
                        │     ├─ Wrap(spacing: 10, children: AVATAR_OPTIONS.map(_AvatarChip))
                        │     ├─ _SectionLabel("CHOOSE COLOR")
                        │     └─ Wrap(spacing: 10, children: AVATAR_COLORS.map(_ColorChip))
                        ├─ _NameField(controller, error)
                        ├─ _SectionLabel("PLAYBACK AND LANGUAGE SETTINGS")
                        ├─ _SettingsCard(
                        │     children: [
                        │       if (!isPrimary) _SettingRow(label: "Junior Mode", switch),
                        │       _SettingRow(label: "Profile PIN", switch),
                        │       if (enablePin) _PinEntryBlock(pin, onKey),
                        │     ])
                        └─ if (canDelete) _DeleteAction(showConfirm)
  ```
- The PIN entry numpad here is the same widget as the who-watching modal but smaller dims — extract `PinNumpad(size: PinNumpadSize.small | medium)`.
- The big-avatar edit-badge positioning trick (`right: 35%`) is wonky in Flutter; better: use `Align` + `Padding` or a `Stack` with `Positioned(bottom: 0, right: -8)` to clip out of the avatar bounds.

---

## 7. AccountScreen (`app/account.tsx`)

### Visual layout
- **Header:** row, `paddingHorizontal: 16`, `paddingBottom: 14`, hairline bottom border (`StyleSheet.hairlineWidth`, color `colors.border`). Back chevron left, "Account" `17pt Inter_700Bold` center, 40px placeholder right.
- **Section label:** "ACCOUNT DETAILS" — `11pt Inter_700Bold` letter-spacing 1.5 muted, paddingHorizontal 16, marginTop 24, marginBottom 8.
- **Account card** (only when authenticated): marginHorizontal 16, radius 12, 1px border, overflow hidden, bg `colors.card`.
  - **Email row:** padding `16/14`, hairline bottom border. Left label = `user.email` truncated. Right "Change" `14pt Inter_600SemiBold` cherry (currently inert).
  - **Password row:** label `Password: ••••••••••••`. Right "Change" cherry (inert).
  - **Logout-all row:** padding `16/14`, single label "Log out of all devices" cherry (inert).
- **PLAN section** (always shown):
  - Section label "PLAN".
  - Card with single row. Label "AwaTV Premium" or "Free Plan" depending on `useSubscription().isSubscribed`. Right "Manage" or "Upgrade" cherry → `router.push("/paywall")`.
- **Delete-account button** (authenticated only): `paddingVertical: 20`, marginTop 8, center label "Delete My Account" destructive `15pt Inter_600SemiBold`.
- **Guest banner** (unauthenticated only): margin 16, radius 12, 1px border, padding 16, row gap 12. `Feather.user` 20px cherry + stack [title "Guest Mode" `14pt Inter_700Bold` / sub "Log in to sync your data across devices" `12pt regular` muted] + cherry-filled "Login" pill (paddingHorizontal 16, paddingVertical 8, radius 8, label `13pt Inter_700Bold` white).

### Modals
Two transparent fade modals share a layout:
- Overlay `rgba(0,0,0,0.6)`, padding 32, centered.
- Box: full-width-of-padding, radius 14, padding 24, gap 12, bg `colors.card`.
- Title `17pt Inter_700Bold` center.
- Sub `13pt Inter_400Regular` muted center lineHeight 19.
- Buttons row, justify space-around, marginTop 8.
  - "Cancel" `15pt Inter_600SemiBold` cherry (no fill).
  - "Log out" / "Delete" `15pt Inter_600SemiBold`. Logout = cherry. Delete = destructive. Loading state on delete: label becomes "Deleting…".

### Behavior
- **Sign out:** `await signOut(); router.replace("/welcome")`. Note: source code wires the danger button to `setShowDeleteConfirm` instead of the logout modal — `showLogoutConfirm` state is declared but its trigger is missing. Port should add an explicit "Sign out" row above "Delete My Account" and wire the logout modal to it (pre-existing UX intent).
- **Delete account:** call `deleteAccount()` → calls `supabase.rpc("delete_user")` then `signOut()`. On success → `router.replace("/welcome")`.
- **Guest "Login" pill:** push `/login`.

### Data flow
- Reads `useAuth().user`, `signOut`, `deleteAccount`, `isAuthenticated`.
- Reads `useSubscription().isSubscribed, monthlyPackage` (from `lib/revenuecat`).
- Calls `supabase.rpc("delete_user")` — expects a Postgres function on the Supabase side that deletes the auth user and cascades data.

### Flutter port mapping
- **Closest existing file:** `/Users/max/AWAtv/apps/mobile/lib/src/features/auth/account_screen.dart` (exists; full re-skin).
- **Riverpod providers:**
  - `subscriptionControllerProvider = AsyncNotifierProvider<SubscriptionController, SubscriptionState>` (RevenueCat wrapper) — likely already present as part of paywall feature.
  - `accountActionsProvider = Provider<AccountActions>` exposing `signOut()` and `deleteAccount()` callable methods.
- **Widget tree:**
  ```
  Scaffold(appBar: _AccountAppBar(), backgroundColor: kBgBase)
    └─ ListView(padding: zero)
        ├─ if (isAuth) _SectionLabel("ACCOUNT DETAILS")
        ├─ if (isAuth) _AccountCard(email)
        ├─ _SectionLabel("PLAN")
        ├─ _PlanCard(isSubscribed)
        ├─ if (isAuth) _SignOutTile()         // NEW — fills missing wiring
        ├─ if (isAuth) _DeleteAccountTile()
        └─ if (!isAuth) _GuestBanner()
  ```
- Confirm modals: `showAdaptiveDialog` with custom shape (radius 14) and the content layout above. On Cupertino, native `CupertinoAlertDialog` would be tempting but the Streas design is custom — keep it Material with the Streas tokens.
- Use `go_router`'s `context.push('/paywall')`, `context.go('/welcome')` after sign-out.

---

## 8. ProfileContext State Machine

`ProfileContext.tsx` manages multi-profile CRUD with online/offline strategy:

**Load order on `userId` change:**
1. Set `isLoaded = false`.
2. If authenticated + Supabase available → `select * from profiles where user_id = ? order by created_at`. Map DB rows via `dbToProfile`.
3. If empty → fall back to `AsyncStorage.getItem("awatv_profiles_<userId>")` and JSON-parse.
4. If still empty → create a default profile (`makeDefaultProfile`) with id `local_<timestamp>`, name "Me", emoji "🎭", color cherry, `isPrimary: true`.
5. Restore active profile from `AsyncStorage.getItem("awatv_active_profile_<userId>")` lookup.
6. Set `isLoaded = true`.

**Mutations:**
- `createProfile(patch)`: generate id `local_<ts>_<rand>`, randomize avatar/color if not provided, push to list, save local + best-effort upsert to Supabase.
- `updateProfile(id, patch)`: spread merge in list, refresh `activeProfile` if affected, save local + upsert.
- `deleteProfile(id)`: filter out, reassign active to primary or first, save local + Supabase delete.
- `setActiveProfile(profile, pin?)`: PIN check (string equality), persist active id to AsyncStorage. Returns `{error}` on PIN mismatch.
- `verifyPin(profileId, pin)`: pure read.

**Computed: `needsProfileSelection = isLoaded && activeProfile === null && profiles.length > 1`.**

### Flutter port

- **Existing files (verify and augment):**
  - `lib/src/shared/profiles/profile.dart` — `Profile` model (`freezed`).
  - `lib/src/shared/profiles/profile_controller.dart` — controller with CRUD.
  - `lib/src/shared/profiles/profile_scoped_storage.dart` — keyed local storage.
  - `lib/src/shared/profiles/profile_scoped_providers.dart` — `Profile`-scoped derived state.
- **Riverpod providers:**
  - `profileControllerProvider = AsyncNotifierProvider<ProfileController, ProfileState>` where `ProfileState = ({List<Profile> profiles, Profile? active, bool isLoaded})`.
  - `needsProfileSelectionProvider = Provider<bool>` — derives from `profileControllerProvider`.
  - Per-profile scoped providers (history, favorites, settings) re-key on `active.id` change.
- **Storage keys** (port verbatim):
  - `awatv_profiles_<userId>` (JSON list).
  - `awatv_active_profile_<userId>` (string id).
  - Use `flutter_secure_storage` for the active ID (since it can leak which profile a user prefers); use `shared_preferences` for the list (or `hive` if larger).
- **Supabase table:** `profiles` with columns matching `DbProfile` interface in `lib/supabase.ts`:
  ```
  id (uuid|text PK), user_id (uuid FK auth.users), name, avatar, color,
  pin (nullable text), is_primary (bool), junior_mode (bool),
  language (text), birthdate (nullable date), gender (nullable text),
  created_at (timestamptz), updated_at (timestamptz)
  ```
  RLS: `user_id = auth.uid()` for all CRUD. Add a unique partial index `where is_primary` per `user_id` to enforce single primary.

**Security note (port-time fix):** The current Streas implementation stores PINs in plain text both in AsyncStorage and Supabase. **For Flutter port, hash PINs** with `crypt` (Argon2id via `cryptography` package) before storing, with the salt embedded. Store `pin_hash` (not `pin`) in DB. Compare via constant-time check on `setActiveProfile`. This is a 0-cost security upgrade and the verify path (`profile.pin === pin`) is the single touchpoint.

---

## 9. Supabase Client (`lib/supabase.ts`)

- Reads `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` from env. `SUPABASE_CONFIGURED` boolean derived from non-empty env.
- Custom storage adapter: `expo-secure-store` on native, `localStorage` on web.
- Auth options: `autoRefreshToken: true, persistSession: true, detectSessionInUrl: false`.

### Flutter equivalent
- Use `supabase_flutter: ^2.x`. Already wired in AWAtv (see `lib/src/app/env.dart`).
- Storage: `supabase_flutter` uses `SharedPreferences` by default. For session secrecy, override with `flutter_secure_storage`-backed adapter (matching SecureStore parity). Pass via `Supabase.initialize(authOptions: AuthClientOptions(localStorage: SecureStorageAdapter()))`.
- Init in `main.dart` before `runApp`. `SUPABASE_CONFIGURED` becomes `env.supabaseUrl.isNotEmpty && env.supabaseAnonKey.isNotEmpty`.
- DB type interfaces (`DbProfile`, `DbPlaylistSource`, etc.) become `freezed` data classes with `JsonSerializable`. Run `supabase gen types dart` if available, or hand-write to mirror `lib/supabase.ts` exactly.

---

## 10. Routing summary (port to `go_router`)

```
/welcome             → WelcomeScreen        (animation: fade)
/login               → LoginScreen          (animation: slide_from_right)
/signup              → SignupScreen         (animation: slide_from_right)
/who-watching        → WhoWatchingScreen    (animation: fade — fullscreen takeover)
/add-profile?profileId={id?}  → AddProfileScreen (animation: slide_from_bottom — sheet feel)
/account             → AccountScreen        (animation: slide_from_right)
/(tabs)/...          → main app shell
```

`auth_guard.dart`'s `redirect` should:
1. Block all `/(tabs)` and `/who-watching` and `/add-profile` if `state is AuthLoading` (show splash).
2. Force `/welcome` if `state is AuthGuest` AND `isConfigured`.
3. Force `/who-watching` if `state is AuthAuthenticated` AND `needsProfileSelection`.
4. Otherwise allow.

For Flutter `slide_from_bottom`, override `pageBuilder` with a `CustomTransitionPage` using `SlideTransition` with offset `Offset(0, 1) → Offset.zero`. For `fade`, `FadeTransition`. `slide_from_right` is the default `MaterialPage`.

---

## 11. Cross-cutting widgets to extract

Place in `lib/src/features/auth/widgets/` (or `lib/src/shared/ui/` if generic):

| Widget | Used by | Notes |
|---|---|---|
| `StreasInput` | login, signup, add-profile | Bordered text field with destructive error state, optional trailing icon (eye toggle). |
| `GradientCta` | welcome, login, signup, add-profile-save | `[#9F1239 → #E11D48]` left-to-right, radius 8, paddingVertical 16, label letter-spacing 1.5. Loading state shows white `CircularProgressIndicator`. |
| `OutlinedCta` | welcome | 1px white-25 border, transparent fill, same dims as gradient CTA. |
| `SectionLabel` | account, add-profile, who-watching | `11pt Inter_700Bold` letter-spacing 1.5, color muted. |
| `StreasSwitch` | add-profile | iOS-style switch with cherry track and white thumb. Use Material `Switch` with `activeColor: kCherry`. |
| `PinDots` | who-watching modal, add-profile | 4 14×14 circles, 14px gap. Variants for "modal" (no border, white fill) and "form" (1px border, cherry fill). |
| `PinNumpad` | who-watching modal, add-profile | 12-cell grid (3 cols), `1-9 / "" 0 ⌫`. Sizes: large (64×54) and small (58×48). |
| `ProfileAvatar` | who-watching, add-profile, pin-modal | Sizes: small 68, medium 90. Optional badges: `lock` / `edit`. Rounded 10/12/18 by size. Centered emoji 36/44/50pt. |
| `MosaicBackdrop` | welcome | 12-tile grid + gradient overlay. |
| `StreasModal` | account, who-watching, add-profile-delete | `showDialog` with overlay 60-80% black, custom box with title/sub/actions. |

---

## 12. Acceptance checklist (functional parity)

- [ ] User can boot the app with no Supabase env → lands on Welcome with "Browse as Guest" CTA + info banner.
- [ ] User can boot the app with Supabase env → sees Login + Signup CTAs + tertiary upload + "Continue as Guest".
- [ ] Tap Login → 2-step form, valid email gates step 2, wrong password shows Supabase error inline.
- [ ] Tap Signup → 3-step wizard with progress bar, password strength meter, marketing checkbox default true, birthdate optional.
- [ ] After successful auth → lands on Who's Watching, default "Me" profile present (auto-created).
- [ ] Tap profile (no PIN) → enters tabs.
- [ ] Tap PIN-locked profile → modal with numpad, 4-digit auto-submit on completion, wrong PIN shakes-or-shows error and clears.
- [ ] Tap "Edit Profile" → enters edit mode (badge changes from lock to edit pencil), tapping a profile pushes the edit screen.
- [ ] Tap "Add Profile" → blank edit screen, name required, picks emoji/color, optional Junior Mode, optional 4-digit PIN.
- [ ] Save creates profile in local list AND upserts to Supabase if authenticated.
- [ ] Edit primary profile → Junior Mode row hidden, delete button hidden, primary-note shown.
- [ ] Delete non-primary profile → 2-step confirm, removes from list and Supabase, navigates back to Who's Watching.
- [ ] Account screen → shows email, plan tier, sign-out + delete buttons (auth) OR guest banner (guest).
- [ ] Sign out → returns to Welcome.
- [ ] Delete account → calls `delete_user` RPC, returns to Welcome.
- [ ] Color tokens map exactly: `#E11D48` cherry primary, `#9F1239` cherry-dark for gradients, `#0a0a0a` background, `#141414` cards, `#ef4444` destructive.

---

## 13. Open questions / port-time decisions

1. **Magic-link vs password sign-in:** AWAtv's existing `magic_link_callback_screen.dart` suggests magic-link is the planned auth mode. Streas uses password. Recommendation: keep both — password as primary, magic link as a "Forgot password?" / passwordless fallback.
2. **PIN hashing:** as noted in §8, port should hash PINs at rest. Decide on Argon2id parameters now (memory 19 MiB, iterations 2, parallelism 1 is a sane mobile baseline).
3. **Avatar/color duplicate at index 0/8:** confirm with design — likely an accident in Streas. Suggest replacing index 8 with a fresh hue (e.g. `#3b82f6` blue) to give the picker 12 distinct colors.
4. **Date picker style:** Streas uses an inline 3-column wheel (idiosyncratic). Port suggestion: Cupertino native picker on iOS, Material `showDatePicker` on Android, gated behind the same trigger.
5. **Color blue tint on selected date item** (`rgba(59,130,246,0.3)`): legacy from a pre-cherry palette. Replace with cherry-tinted `rgba(225,29,72,0.25)`.
6. **`continueAsGuest` semantics:** Streas treats guest as a first-class state with its own profile bucket. Port preserves this — but ensure the `ProfileController` correctly migrates guest profiles into the user's bucket if they sign up later (currently Streas does NOT — flagged as a feature gap to track).
7. **Account screen logout wiring:** `showLogoutConfirm` modal exists but no button triggers it. Port should add the explicit "Sign out" tile (see §7 widget tree).

---

End of spec.
