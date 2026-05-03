# Streas → Flutter Port: Shared Components Spec

**Source**: `/tmp/Streas/artifacts/iptv-app/` (React Native / Expo)
**Target**: `/Users/max/AWAtv` (Flutter monorepo)
**Scope**: 11 shared components (`components/*.tsx`)
**Theme tokens**: `constants/colors.ts` (Cherry-red Netflix-inspired palette, dark only)
**Responsive utils**: `utils/responsive.ts`

---

## 0. Foundation: Theme & Responsive Tokens

### Color tokens (`constants/colors.ts` → `awatv_ui/theme/streas_colors.dart`)

| Token | Hex | Use |
|---|---|---|
| `background` | `#0a0a0a` | Scaffold background |
| `card` | `#141414` | Card surface |
| `surface` | `#111111` | Lower tier surface |
| `surfaceHigh` | `#1c1c1c` | Higher tier (e.g. tag pill) |
| `secondary` / `muted` | `#1c1c1c` | Filled chips |
| `border` / `input` | `#282828` | Hairline borders / input border |
| `foreground` / `cardForeground` / `text` | `#ffffff` | Primary text |
| `mutedForeground` | `#808080` | Secondary text |
| `primary` / `tint` / `accent` / `tag` / `focus` / `live` | `#E11D48` (CHERRY) | CTAs, live dot, brand |
| `primaryForeground` | `#ffffff` | Text on primary |
| `primaryDark` | `#9F1239` | Pressed state |
| `destructive` | `#ef4444` | Errors |
| `gold` | `#f59e0b` | PRO/premium accents |
| `radius` | `8` | Default corner radius (other radii: 3, 4, 6, 10, 12, 24) |

There is **no light mode** — `colors.light === colors.dark === base`. In Flutter, expose a single `ThemeData` (dark) and a `StreasColors` extension class.

### Typography (Inter family used everywhere)

| Weight key (RN) | Flutter `FontWeight` |
|---|---|
| `Inter_400Regular` | `w400` |
| `Inter_500Medium` | `w500` |
| `Inter_600SemiBold` | `w600` |
| `Inter_700Bold` | `w700` |

Add `google_fonts` or bundle Inter via `pubspec.yaml`. Define `TextStyle` presets in `awatv_ui/theme/typography.dart` (already exists, extend it).

### Responsive (`utils/responsive.ts` → `awatv_ui/responsive/responsive.dart`)

```dart
const baseWidth = 390.0; // iPhone 14 Pro
double rs(BuildContext c, double size) =>
    ((MediaQuery.sizeOf(c).width / baseWidth) * size).roundToDouble();
double rf(BuildContext c, double size) => rs(c, size); // Flutter handles textScaleFactor natively
bool isTablet(BuildContext c) => MediaQuery.sizeOf(c).width >= 768;
bool isLandscape(BuildContext c) {
  final s = MediaQuery.sizeOf(c);
  return s.width > s.height;
}
int gridColumns(BuildContext c) {
  final w = MediaQuery.sizeOf(c).width;
  if (w >= 1200) return 6;
  if (w >= 900) return 5;
  if (w >= 768) return 4;
  if (w >= 480) return 3;
  return 3;
}
double cardWidth(BuildContext c) {
  final w = MediaQuery.sizeOf(c).width;
  final cols = gridColumns(c);
  const gap = 8.0, padding = 24.0;
  return (w - padding * 2 - gap * (cols - 1)) / cols;
}
```

Use `MediaQuery.sizeOf` (Flutter 3.10+) instead of `Dimensions.get('window')` — it auto-rebuilds on orientation change. Existing `device_class_provider.dart` in `apps/mobile/lib/src/shared/breakpoints/` already exposes form-factor classes; align this util with it.

---

## 1. ContentCard

### Anatomy
- **Visual structure**: `TouchableOpacity` → outer container with bottom margin, `View` (image container, clipped, rounded) containing `Image` (absolute fill, `resizeMode: cover`), optional NEW badge (top-left), optional progress bar (bottom). Optional title `Text` below the image container.
- **Props**:
  - `item: ContentItem` (required)
  - `onPress: (item) => void` (required)
  - `width?: number` — default `110`
  - `showProgress?: boolean` — default `false`
  - `showTitle?: boolean` — default `false`
  - `landscape?: boolean` — default `false`
- **Dimensions**:
  - **Portrait poster** (default): `width × width * 1.5` → aspect **2:3**. At default 110: 110×165.
  - **Landscape backdrop**: `width × width * 0.56` → aspect **~16:9** (1.78:1; 0.56 ≈ 1/1.78). At width 200: 200×112.
  - **Channel logo**: same component, used with custom `width` and either landscape or portrait depending on caller. There is no dedicated square variant; logos render inside a 16:9 or poster crop with `cover`.
- **Padding/margin/radius/shadow**:
  - Container: `marginRight: 10` (horizontal scroll spacing).
  - Image container: `borderRadius: 8` (`colors.radius`), `borderWidth: 0`, `overflow: hidden`.
  - NEW badge: `top: 6, left: 6`, `paddingHorizontal: 6, paddingVertical: 2`, `borderRadius: 3`.
  - Progress bar: absolute bottom, `height: 3`, track `rgba(255,255,255,0.2)`, fill `colors.primary`.
  - Title: `marginTop: 6`.
  - **No shadow**.
- **Colors used**:
  - bg fallback while image loads: `colors.card`
  - border: `colors.border` (referenced but width is 0 — placeholder for hover/focus border later)
  - NEW badge bg: `colors.primary`
  - Progress fill: `colors.primary`
  - Title: `colors.foreground`
- **Typography**:
  - Title: `12px / Inter_500Medium`, `numberOfLines: 1`
  - NEW label: `9px / Inter_700Bold`, white, `letterSpacing: 0.5`
- **Image handling**: `Image source={{ uri }}` with `resizeMode="cover"`. **No** lazy loading, **no** blur placeholder, **no** explicit fallback — relies on RN Image's default.
- **Icons**: none.

### Variants & states
- **Press feedback**: `activeOpacity={0.75}` (whole card fades to 75% on touch-down).
- **Selected/focused**: not implemented. Add for TV / web hover later.
- **Loading skeleton**: not in this component — caller uses `awatv_ui/shimmer_skeleton.dart`.
- **Empty / error**: not handled — caller's responsibility.
- **NEW indicator**: when `item.isNew === true`, top-left pill.
- **Progress overlay**: when `showProgress && item.progress != null`, bottom strip 0..1 fraction.

### Behavior
- **Touch**: tap → `onPress(item)`.
- **Long-press / swipe**: none.
- **Animations**: none beyond press opacity.
- **Accessibility**: no explicit `accessibilityLabel` — should add `item.title` in Flutter port.

### Flutter port mapping
- **Existing** in `awatv_ui`: `widgets/poster_card.dart` already exists. Audit it; if it covers portrait+landscape, extend it. Otherwise build a dedicated `StreasContentCard`.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/content_card.dart`

```dart
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 110,
    this.showProgress = false,
    this.showTitle = false,
    this.landscape = false,
  });
  final ContentItem item;
  final VoidCallback onTap;
  final double width;
  final bool showProgress;
  final bool showTitle;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<StreasColors>()!;
    final height = landscape ? width * 0.56 : width * 1.5;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: width,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedOpacity(
            opacity: 1.0, // wrap with InkWell or _PressOpacity for 0.75 on press
            duration: const Duration(milliseconds: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: width,
                  height: height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(imageUrl: item.thumbnail, fit: BoxFit.cover),
                      if (item.isNew) Positioned(
                        top: 6, left: 6,
                        child: _NewBadge(color: c.primary),
                      ),
                      if (showProgress && item.progress != null)
                        Positioned(left: 0, right: 0, bottom: 0,
                          child: _ProgressBar(value: item.progress!, color: c.primary),
                        ),
                    ],
                  ),
                ),
                if (showTitle) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Use `cached_network_image: ^3` for caching + placeholder. Wrap `GestureDetector` with a custom `_PressOpacity` to mimic RN's `activeOpacity`.

---

## 2. ContentRow

### Anatomy
- **Visual structure**: `View` container → header `View` (title + optional "See All") → horizontal `ScrollView` of `ContentCard`s.
- **Props**:
  - `title: string`
  - `data: ContentItem[]`
  - `onPress: (item) => void`
  - `onSeeAll?: () => void`
  - `showProgress?: boolean` — default `false`
  - `landscape?: boolean` — default `false`
  - `cardWidth?: number` — overrides default
- **Dimensions / layout**:
  - Container `marginBottom: 24`.
  - Header: `paddingHorizontal: 16`, `marginBottom: 12`, `flexDirection: row`, `space-between`, `align-items: center`.
  - Scroll content: `paddingHorizontal: 16`. **No snap** (`ScrollView` only).
  - Default card width: `200` if `landscape`, else `110`.
  - Card-to-card gap is provided by the card's own `marginRight: 10`.
- **Colors / typography**:
  - Title: `colors.foreground`, `16px / Inter_600SemiBold`.
  - "See All": `colors.mutedForeground`, `12px / Inter_500Medium`, `activeOpacity={0.7}`.
- **Icons**: none.

### Variants & states
- **No skeleton state** — caller renders shimmer rows separately.
- **Empty**: renders an empty row (no header suppression).
- "See All" only rendered when `onSeeAll` is provided.

### Behavior
- Horizontal scroll with `showsHorizontalScrollIndicator: false`. **No paging / no snap**. Inertial scroll only.
- "See All" tap → `onSeeAll()`.

### Flutter port mapping
- **Existing**: nothing equivalent in `awatv_ui` (rows are screen-specific in `apps/mobile/lib/src/features/home`). Build a shared widget.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/content_row.dart`

```dart
class ContentRow extends StatelessWidget {
  const ContentRow({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.onSeeAll,
    this.showProgress = false,
    this.landscape = false,
    this.cardWidth,
  });
  final String title;
  final List<ContentItem> items;
  final ValueChanged<ContentItem> onItemTap;
  final VoidCallback? onSeeAll;
  final bool showProgress;
  final bool landscape;
  final double? cardWidth;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<StreasColors>()!;
    final w = cardWidth ?? (landscape ? 200.0 : 110.0);
    final h = landscape ? w * 0.56 : w * 1.5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: Text('See All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.mutedForeground)),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: h + (showProgress ? 0 : 0), // title space added in card if shown
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (_, i) => ContentCard(
                item: items[i], width: w,
                landscape: landscape, showProgress: showProgress,
                onTap: () => onItemTap(items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

For TV / large screens, swap to `ListWheelScrollView`-style focus navigation later.

---

## 3. HeroBanner

### Anatomy
- **Visual structure**: full-screen-width `View` (height = 52% of window height) → backdrop `Image` (absolute fill, `cover`) → `LinearGradient` overlay (transparent → 50% black at 65% → 95% black at bottom) → bottom info block (badges, title, subtitle, meta row, action buttons).
- **Props**:
  - `item: ContentItem`
  - `onPlay`, `onInfo`, `onAddToList: (item) => void`
  - `isInList: boolean` — toggles "+" / "✓" icon + label.
- **Dimensions**:
  - `width: window.width` (full)
  - `height: window.height * 0.52`
- **Padding/margin/radius**:
  - Bottom block: `paddingHorizontal: 20, paddingBottom: 16`, `gap: 6`.
  - "NEW" badge: `paddingHorizontal: 8, paddingVertical: 3, borderRadius: 4`.
  - Rating pill: `borderWidth: 1, borderColor: rgba(255,255,255,0.5)`, `paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3`.
  - Play button: `paddingHorizontal: 24, paddingVertical: 12, borderRadius: 6`, gap 8.
  - Action row gap: 14.
- **Colors**:
  - Gradient: `transparent → rgba(0,0,0,0.5) at 0.65 → rgba(0,0,0,0.95) at 1.0`
  - "NEW" badge bg: `colors.primary`
  - Exclusive text: `#f0c040` (gold)
  - Play button bg: `colors.primary`
  - Title: `#fff`, subtitle: `rgba(255,255,255,0.65)`
  - Genre/meta text: `rgba(255,255,255,0.6 / 0.7 / 0.8)`
- **Typography**:
  - Title: `30px / Inter_700Bold`, `letterSpacing: 0.5`
  - Subtitle: `11px / Inter_500Medium`, `letterSpacing: 1`
  - "NEW": `10px / Inter_700Bold`, `letterSpacing: 1`
  - Exclusive: `10px / Inter_600SemiBold`, `letterSpacing: 1`
  - Rating: `10px / Inter_500Medium`
  - Genre: `12px / Inter_400Regular`
  - Play label: `13px / Inter_700Bold`, `letterSpacing: 0.5`
  - Icon label: `10px / Inter_500Medium`
- **Image**: backdrop from `item.banner ?? item.thumbnail`, `cover`. No blur placeholder.
- **Icons** (`@expo/vector-icons/Feather`):
  - `play` (18, white)
  - `plus` / `check` (22, white) — toggles on `isInList`
  - `info` (22, white)

### Variants & states
- "NEW" badge only when `item.isNew`.
- Exclusive star line only when `item.isExclusive`.
- Rating only when `item.rating`.
- Genre tags: first 2 only.
- "My List" button toggles label "Added"/"My List" + icon based on `isInList`.

### Behavior
- **Static** — no auto-play carousel in this component (single item).
- Tap on Play / +My List / Info → respective callbacks.
- `activeOpacity` 0.7-0.8 on each tappable.

### Flutter port mapping
- **Existing**: `awatv_ui/widgets/backdrop_header.dart` and `widgets/gradient_scrim.dart` cover gradient + backdrop.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/hero_banner.dart`. Compose from existing `BackdropHeader` + `GradientScrim`.
- For carousel use case (multi-item home banner), wrap `N` HeroBanners in `PageView` with auto-advance (5-7s) and `SmoothPageIndicator` dots. The source RN component itself is single-item; carousel is added in Flutter.

```dart
class HeroBanner extends StatelessWidget {
  // height = MediaQuery.sizeOf(c).height * 0.52
  // Stack: Image.network(cover) + DecoratedBox(LinearGradient) + Positioned(bottom: 0, child: _Info(...))
}
```

Icons: use `feather_icons` package or `phosphor_flutter` (closest match) or build a tiny `FeatherIcon` enum. Existing project may already use `cupertino_icons` + `material_icons` — reuse `Icons.play_arrow`, `Icons.add`, `Icons.check`, `Icons.info_outline`.

---

## 4. LiveChannelCard

### Anatomy
- **Visual structure**: `TouchableOpacity` (rounded card) → top thumbnail block (160px tall) with absolute LIVE badge (top-left) + viewers badge (top-right) → info block below (name, current show, category tag).
- **Props**:
  - `channel: LiveChannel` (`{ thumbnail, name, currentShow, category, viewers? }`)
  - `onPress: (channel) => void`
- **Dimensions**:
  - Card width: implicit (parent decides — typically full row or grid cell).
  - Thumbnail: `height: 160` (full width of card).
  - Info block padding: 12, gap 4.
  - Card `marginBottom: 12`.
- **Padding/margin/radius**:
  - Card: `borderRadius: 10`, `borderWidth: 1`, `overflow: hidden`.
  - LIVE badge: `top: 10, left: 10`, bg `rgba(0,0,0,0.7)`, `paddingHorizontal: 8, paddingVertical: 4, borderRadius: 4`, gap 4.
  - LIVE dot: `width/height: 7`, `borderRadius: 3.5`.
  - Viewers badge: same shape as LIVE badge but at `top-right`.
  - Category tag: `alignSelf: flex-start`, `paddingHorizontal: 8, paddingVertical: 3, borderRadius: 4`, `marginTop: 4`.
- **Colors**:
  - Card bg: `colors.card`, border `colors.border`.
  - LIVE dot: `colors.live` (= `#E11D48`).
  - LIVE / viewers badge bg: `rgba(0,0,0,0.7)`.
  - LIVE text white, viewers text `rgba(255,255,255,0.8)`.
  - Channel name: `colors.foreground`. Show: `colors.mutedForeground`.
  - Category tag: bg `colors.secondary` (`#1c1c1c`), text `colors.mutedForeground`.
- **Typography**:
  - Name: `14px / Inter_600SemiBold`, 1 line.
  - Current show: `12px / Inter_400Regular`, 1 line.
  - LIVE: `10px / Inter_700Bold`, `letterSpacing: 1`.
  - Viewers: `10px / Inter_500Medium`.
  - Category: `10px / Inter_500Medium`.

### Difference from ContentCard
- **Always portrait-card-like** but landscape-thumbnail (16:9-ish at 160px tall full-width).
- Has **persistent LIVE badge** with red dot (no `isNew` toggle).
- Has **viewers count** badge (optional).
- Has **info block below thumbnail** (name + current show + category) — ContentCard only shows optional title.
- Surrounded by a 1px border by default.

### Behavior
- Tap → `onPress(channel)` (`activeOpacity: 0.8`).
- LIVE dot is **static** in source (no pulse). For Flutter, add a subtle pulse `AnimationController` (1s loop, scale 0.9 ↔ 1.1) for visual punch.

### Flutter port mapping
- **Existing**: `awatv_ui/widgets/channel_tile.dart` may overlap. Audit and either extend or build new.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/live_channel_card.dart`
- Reuse `awatv_ui/widgets/rating_pill.dart` shape for badges if API matches.

```dart
class LiveChannelCard extends StatelessWidget {
  // Material InkWell card with:
  //   AspectRatio(aspectRatio: 16/9) {Stack: thumbnail + Positioned(LIVE) + Positioned(viewers)}
  //   Padding(12) {Column: name, show, _CategoryTag}
}
class _PulsingLiveDot extends StatefulWidget { ... }  // optional pulse animation
```

---

## 5. SearchBar

### Anatomy
- **Visual structure**: horizontal `View` row → search icon, `TextInput` (flex-1), optional clear button.
- **Props**:
  - `value: string`, `onChangeText: (text) => void`
  - `placeholder?: string` — default `"Search shows, movies, channels..."`
  - `onClear?: () => void`
- **Dimensions**: implicit width (parent), padding `paddingHorizontal: 14, paddingVertical: 11`, `borderRadius: 10`, `borderWidth: 1`, `gap: 10`.
- **Colors**:
  - bg `colors.card`, border `colors.border`.
  - Icons + placeholder: `colors.mutedForeground`.
  - Input text: `colors.foreground`.
- **Typography**: `14px / Inter_400Regular`.
- **Icons** (Feather):
  - `search` (18, mutedForeground) — left
  - `x-circle` (16, mutedForeground) — right, only if value not empty

### Variants & states
- **Clear button** appears only when `value.length > 0`.
- **No focus animation** (no border highlight, no shadow).
- **No voice input button** in source — add as Flutter enhancement (the project already has `features/voice_search/`).
- **No debounce in this component** — caller debounces via state. Recommend Flutter port include built-in `Timer`-based debounce (default 300ms).
- `returnKeyType: "search"`, `autoCorrect: false`, `autoCapitalize: none`.

### Behavior
- Typing → `onChangeText`.
- Clear tap → `onClear()` (`activeOpacity: 0.7`).

### Flutter port mapping
- **Existing**: nothing dedicated (mobile app has feature-specific search). Build shared.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/search_bar.dart`

```dart
class StreasSearchBar extends StatefulWidget {
  const StreasSearchBar({
    super.key,
    required this.controller,
    this.placeholder = 'Search shows, movies, channels...',
    this.onChanged,
    this.debounce = const Duration(milliseconds: 300),
    this.onVoice, // optional voice button (mic icon if provided)
  });
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final Duration debounce;
  final VoidCallback? onVoice;
  // ...
}
```

Use `TextField` with `decoration: InputDecoration(prefixIcon: Icon(Icons.search), suffixIcon: clearButton)`. Wrap in a `Container` for the rounded border to match RN exactly. Implement debounce with a `Timer?` field reset on each `onChanged`.

For voice integration, hook into existing `apps/mobile/lib/src/features/voice_search/`.

---

## 6. ProfileSheet

### Anatomy
- **Visual structure**: `Modal` (transparent) → backdrop `Pressable` (rgba(0,0,0,0.6)) → animated bottom sheet `View`:
  1. Drag handle (40×4, centered)
  2. Profile header row: avatar (52×52, cherry bg, user icon), name + sub, PRO badge OR Upgrade button
  3. Stats row: 4 `StatBox`es (Channels, Favorites, Playlists, Plan) with hairline dividers
  4. Premium banner (only if not subscribed): icon tile + title + sub + chevron, with horizontal cherry gradient overlay
  5. Menu list: 6 items (Favorites, TV Guide, Playlists, Search, Recently Watched, Settings) — each with icon tile (cherry tinted), label + description, chevron
  6. Close button (outlined)
- **Props**: `visible: boolean`, `onClose: () => void`. Internally pulls subscription state + content state from contexts.
- **Dimensions**:
  - Bottom sheet: anchored bottom, `borderTopLeftRadius: 24`, `borderTopRightRadius: 24`.
  - Avatar: 52×52, `borderRadius: 26` (full circle).
  - Menu item icon tile: 36×36, `borderRadius: 10`.
  - Premium icon tile: 34×34, `borderRadius: 10`.
  - Profile header padding: 18.
  - Stats row: `paddingVertical: 14, marginHorizontal: 18`.
  - Premium banner: `margin: 14, padding: 14, borderRadius: 12`.
  - Menu list: `paddingHorizontal: 14`.
  - Close button: `paddingVertical: 13, borderRadius: 12, borderWidth: 1`, `marginHorizontal: 14, marginTop: 8`.
  - Bottom safe-area inset + 16px bottom padding.
- **Colors**:
  - Sheet bg: `colors.card`.
  - Backdrop: `rgba(0,0,0,0.6)`.
  - Avatar bg: `colors.primary`.
  - PRO badge: bg `#f59e0b22`, border `#f59e0b55`, icon+text `#f59e0b` (gold).
  - Upgrade button bg: `colors.primary`.
  - Menu icon tile bg: `colors.primary + "18"` (≈ 9% alpha primary).
  - Menu icon: `colors.primary`.
  - Premium banner border: `colors.primary + "44"` (~27% alpha).
  - Premium banner gradient: `colors.primary + "30"` → transparent (left → right).
  - Hairlines / dividers: `colors.border`.
- **Typography**:
  - Profile name: `16px / Inter_700Bold`. Profile sub: `12px / Inter_400Regular`.
  - PRO badge text: `11px / Inter_700Bold, letterSpacing: 0.5`.
  - Upgrade button: `12px / Inter_700Bold`.
  - Stat value: `16px / Inter_700Bold`. Stat label: `10px / Inter_400Regular`.
  - Premium title: `13px / Inter_700Bold`. Premium sub: `11px / Inter_400Regular`.
  - Menu label: `14px / Inter_600SemiBold`. Menu desc: `11px / Inter_400Regular`.
  - Close button: `14px / Inter_600SemiBold`.
- **Icons** (Feather): `user`, `zap` (PRO + upgrade + premium banner), `chevron-right`, plus per-menu: `star, calendar, layers, search, clock, settings`.

### Variants & states
- **Subscribed**: shows PRO badge in header, hides Premium banner, "Plan" stat shows "PRO" in gold (`#f59e0b`).
- **Free**: shows Upgrade button + Premium banner.
- **No playlist**: profile sub reads "No playlist connected".
- **Animations**:
  - Open: backdrop fade 0→1 (200ms), sheet `translateY 600 → 0` via `Animated.spring` (`tension 65, friction 11`).
  - Close: reverse, both 200-220ms timing.
- **Navigation**: tapping a menu item calls `onClose()` then `setTimeout(180ms) → router.push(route)` to let the close animation finish.

### Behavior
- Tap backdrop or Close button → `onClose()`.
- Menu item tap → close + navigate.
- Upgrade / Premium banner → close + navigate to `/paywall`.

### Flutter port mapping
- **Existing**: nothing equivalent.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/profile_sheet.dart`
- Use Flutter `showModalBottomSheet` with `isScrollControlled: true, backgroundColor: Colors.transparent, useSafeArea: true`. Inside, build a custom panel with the rounded top corners and content. Avoid Material's default drag-down handle and rebuild the 40×4 pill manually.

```dart
Future<void> showProfileSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (_) => const ProfileSheetBody(),
  );
}

class ProfileSheetBody extends ConsumerWidget {
  // Read subscriptionProvider, contentProvider via Riverpod
  // Build all sections
}
```

For the menu navigation delay, just `Navigator.pop(context)` then `context.go(route)` directly — Flutter's `Navigator.pop` returns a Future you can await before pushing. The 180ms delay is unnecessary on Flutter (sheet dismissal awaits naturally).

For animations, Flutter's `showModalBottomSheet` uses Material spring built in. To match the cherry red brand exactly, set `transitionAnimationController` with custom `CurvedAnimation(curve: Curves.easeOutBack)`.

---

## 7. ErrorBoundary

### Anatomy
- React class component (must be class — error boundaries require lifecycle).
- **Props**: `children`, `FallbackComponent?`, `onError?: (error, stackTrace) => void`. Defaults `FallbackComponent` to `ErrorFallback`.
- **State**: `{ error: Error | null }`. Calls `getDerivedStateFromError` + `componentDidCatch`.
- Renders `<FallbackComponent error resetError />` on error, otherwise children.
- `resetError()` clears the captured error.

### Flutter port mapping
- Flutter does not need this concept literally — `ErrorWidget.builder` + `runZonedGuarded` + `FlutterError.onError` cover render-error capture globally.
- **New util/widget**: `packages/awatv_ui/lib/src/widgets/streas/error_boundary.dart`

```dart
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackBuilder,
    this.onError,
  });
  final Widget child;
  final Widget Function(BuildContext, Object error, StackTrace stack, VoidCallback reset)? fallbackBuilder;
  final void Function(Object error, StackTrace stack)? onError;
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error; StackTrace? _stack;
  void _reset() => setState(() { _error = null; _stack = null; });
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallbackBuilder != null
        ? widget.fallbackBuilder!(context, _error!, _stack ?? StackTrace.empty, _reset)
        : ErrorFallbackView(error: _error!, stack: _stack ?? StackTrace.empty, onRetry: _reset);
    }
    // Wrap child to catch build errors
    return _CaughtErrorWidget(child: widget.child, onCaught: (e, s) {
      widget.onError?.call(e, s);
      setState(() { _error = e; _stack = s; });
    });
  }
}
```

Combine with global `FlutterError.onError = (details) { ObservabilityService.recordError(details); }` (existing `apps/mobile/lib/src/shared/observability/awatv_observability.dart` likely already has this).

---

## 8. ErrorFallback

### Anatomy
- **Visual structure**: full-screen centered view with title, message, primary "Try Again" button. In `__DEV__` only, top-right alert-circle button opens a modal showing the full error stack trace.
- **Props**: `error: Error`, `resetError: () => void`.
- **Dimensions / spacing**:
  - Container: `flex: 1, padding: 24, center`.
  - Content: `gap: 16, maxWidth: 600`.
  - Try-Again button: `paddingVertical: 16, paddingHorizontal: 24, borderRadius: 8, minWidth: 200` + iOS shadow (`opacity 0.1, radius 4`) and Android `elevation: 3`.
  - Top button (dev only): 44×44, `borderRadius: 8`, top right with safe-area inset.
  - Modal: `90%` height bottom sheet, `borderTopLeftRadius: 16`.
- **Colors**:
  - Bg: `colors.background`.
  - Title: `colors.foreground`. Message: `colors.mutedForeground`.
  - Try-Again bg: `colors.primary`. Text: `colors.primaryForeground`.
  - Top button bg: `colors.card`. Modal: bg `colors.background`, header border `colors.border`, error container bg `colors.card`.
- **Typography**:
  - Title: `28px / 700`, line-height 40.
  - Message: `16px`, line-height 24.
  - Button: `16px / 600`.
  - Modal title: `20px / 600`.
  - Error text: `12px` line-height 18, **monospace** (`Menlo` on iOS, `monospace` elsewhere), `selectable` (copy-to-clipboard friendly).
- **Icons** (Feather): `alert-circle` (20, foreground) — dev top button. `x` (24, foreground) — close modal.

### Behavior
- "Try Again" → `reloadAppAsync()` from `expo`; on failure falls back to `resetError()`. In Flutter, equivalent is calling `Restart.restartApp()` from `restart_app` package, or routing to `/` and resetting state.
- Press feedback: `pressed ? 0.9/0.8 opacity` + button scale `0.98` on press.
- `__DEV__` checks: in Flutter, use `kDebugMode` from `package:flutter/foundation.dart`.

### Flutter port mapping
- **Existing**: `awatv_ui/widgets/error_view.dart` likely covers basic error rendering. Extend with the full-screen variant + dev modal.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/error_fallback_view.dart`

```dart
class ErrorFallbackView extends StatelessWidget {
  // Scaffold(body: Center(Column[ Title, Message, FilledButton('Try Again') ]))
  // if (kDebugMode) Positioned top-right IconButton → showModalBottomSheet(_StackTraceSheet)
}
```

---

## 9. PremiumGate

### Anatomy
Two render modes:

**Mode A — Banner** (`overlay: false`, default): inline card prompting upgrade.
- Visual: row → lock icon tile (36×36, primary @ ~13% alpha) → flex content (title "Premium Feature" + sub from `PREMIUM_FEATURES[feature]`) → upgrade tag pill (cherry).
- Padding 14, `borderRadius: 12, borderWidth: 1, margin: 16`, gap 12.
- bg `colors.card`, border `colors.border`.

**Mode B — Overlay** (`overlay: true`): wraps `children` and dims them at 25% opacity, places a centered overlay (lock icon, "Premium feature" text, "Unlock" button).
- Children rendered with `opacity: 0.25, pointerEvents: 'none'`.
- Overlay: absolute fill, centered, `gap: 8, borderRadius: 12`, bg `colors.background + "cc"` (80% alpha).
- Unlock button: `paddingHorizontal: 20, paddingVertical: 8, borderRadius: 8, marginTop: 4`.

### Props
- `feature: PremiumFeatureKey` — used to look up description in `PREMIUM_FEATURES` map.
- `children: ReactNode`
- `overlay?: boolean` — default `false`.

### Behavior
- If `isLoading || isSubscribed` → render children unwrapped.
- Else: tap → `router.push("/paywall")`.

### Icons / typography
- Feather `lock` (20 banner / 22 overlay), color `colors.primary`.
- Banner title: `13px / Inter_600SemiBold`. Sub: `11px / Inter_400Regular`.
- Tag text: `11px / Inter_700Bold`, white.
- Overlay text: `13px / Inter_600SemiBold`. Unlock text: `12px / Inter_700Bold`, white.

### Flutter port mapping
- **Existing**: `apps/mobile/lib/src/features/premium/` likely has helpers; reuse `subscriptionProvider`.
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/premium_gate.dart`

```dart
class PremiumGate extends ConsumerWidget {
  const PremiumGate({super.key, required this.feature, required this.child, this.overlay = false});
  final PremiumFeatureKey feature;
  final Widget child;
  final bool overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    if (sub.isLoading || sub.isSubscribed) return child;
    return overlay ? _OverlayMode(child: child, feature: feature) : _BannerMode(feature: feature);
  }
}
```

For the dim-on-overlay, use `IgnorePointer + Opacity(0.25)` wrapping `child`, then `Stack` an overlay container with `BackdropFilter(blur: 8)` + 80%-alpha background for a richer Flutter-native feel (RN version has no actual blur, just opacity; Flutter can do real blur cheaply).

---

## 10. SubtitleOverlay

### Anatomy
- Absolutely positioned subtitle layer over the video player. Reads cue + settings from `SubtitleContext`.
- **Props**: `bottomOffset?: number` — default `60` (distance from bottom; reused for top mode at `top: 80`).
- **Layout**: absolute fill horizontally (`left: 0, right: 0`), `alignItems: center`, `paddingHorizontal: 20, gap: 2, zIndex: 50`. Anchored top:80 or bottom:`bottomOffset` based on `subtitleSettings.position`.
- **Each line**: `Text` with `textAlign: center, paddingHorizontal: 8, paddingVertical: 2, borderRadius: 4, lineHeight: 24, letterSpacing: 0.2`.
- **Style sources**:
  - `fontSize` from `SUBTITLE_SIZE_MAP[size]`.
  - `color` from `SUBTITLE_COLOR_MAP[color]`.
  - `backgroundColor` from `SUBTITLE_BACKGROUND_MAP[background]`.
  - `fontWeight: '700' | '600'` from `bold`.
  - `textShadowColor: rgba(0,0,0,0.9), textShadowOffset: (1,1), textShadowRadius: 3` always.
- **`pointerEvents: none`** so taps pass through to player controls.

### Behavior
- Returns `null` if disabled or no active cue.
- `activeCue.text.split('\n')` → one `<Text>` per line.

### Flutter port mapping
- **New widget**: `packages/awatv_ui/lib/src/widgets/streas/subtitle_overlay.dart`
- Use `Positioned.fill` inside a `Stack` placed above the player. Use `IgnorePointer` to avoid blocking gestures. Each line is a `Text` with `Shadow`s and a `Container` for background pill.

```dart
class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({super.key, this.bottomOffset = 60});
  final double bottomOffset;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(subtitleSettingsProvider);
    final cue = ref.watch(activeCueProvider);
    if (!settings.enabled || cue == null) return const SizedBox.shrink();
    final isTop = settings.position == SubtitlePosition.top;
    return Positioned(
      left: 0, right: 0,
      top: isTop ? 80 : null,
      bottom: isTop ? null : bottomOffset,
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: cue.text.split('\n').map((line) => /* styled Text */).toList(),
          ),
        ),
      ),
    );
  }
}
```

For `flutter_video_player` / `media_kit` integrations, this overlay sits in the same `Stack` as `Video()`. Subtitle parsing already happens in `utils/subtitles.ts` (port to `apps/mobile/lib/src/features/.../subtitles.dart` if not already done).

---

## 11. KeyboardAwareScrollViewCompat

### Anatomy
- Simple compatibility wrapper over `react-native-keyboard-controller`'s `KeyboardAwareScrollView`. On `web`, falls back to plain `ScrollView`.
- **Props**: extends `KeyboardAwareScrollViewProps & ScrollViewProps`. Default `keyboardShouldPersistTaps = "handled"`.

### Flutter port mapping
- **Not needed in Flutter** — Flutter's `Scaffold(resizeToAvoidBottomInset: true) + SingleChildScrollView` handles keyboard avoidance natively. For cases where the default isn't enough (focused field obscured by keyboard), wrap in `Scrollable.ensureVisible(context)` on focus, or use `flutter_keyboard_visibility` to drive padding.
- **No new widget required**. If consistency with the RN API is desired:

```dart
class KeyboardAwareScroll extends StatelessWidget {
  const KeyboardAwareScroll({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: (padding ?? EdgeInsets.zero).copyWith(bottom: (padding?.bottom ?? 0) + bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: child,
    );
  }
}
```

Use `MediaQuery.viewInsetsOf(context).bottom` to get keyboard height.

---

## Cross-cutting Flutter recommendations

### Package additions to `awatv_ui/pubspec.yaml`
- `cached_network_image` — `Image.network` replacement with disk cache + placeholder.
- `shimmer` — already implied via `shimmer_skeleton.dart`.
- `google_fonts` (or bundle Inter `.ttf` files in `awatv_ui/assets/fonts/`).
- `feather_icons` or rely on Material's built-ins (mapping below).

### Feather → Flutter icon mapping
| Feather | Material |
|---|---|
| `play` | `Icons.play_arrow_rounded` |
| `plus` | `Icons.add` |
| `check` | `Icons.check` |
| `info` | `Icons.info_outline` |
| `search` | `Icons.search` |
| `x-circle` | `Icons.cancel_outlined` |
| `x` | `Icons.close` |
| `lock` | `Icons.lock_outline` |
| `zap` | `Icons.bolt` |
| `chevron-right` | `Icons.chevron_right` |
| `user` | `Icons.person` |
| `star` | `Icons.star_outline` |
| `calendar` | `Icons.calendar_today_outlined` |
| `layers` | `Icons.layers_outlined` |
| `clock` | `Icons.schedule` |
| `settings` | `Icons.settings_outlined` |
| `alert-circle` | `Icons.error_outline` |

If pixel-fidelity to Streas matters, install `feather_icons` and use `FeatherIcons.play` etc.

### Press feedback helper

RN's `activeOpacity` is consistently 0.7-0.85. Build a single `PressOpacity` widget so every tap has the same feel:

```dart
class PressOpacity extends StatefulWidget {
  const PressOpacity({super.key, required this.child, required this.onTap, this.opacity = 0.75});
  final Widget child; final VoidCallback onTap; final double opacity;
  @override State<PressOpacity> createState() => _PressOpacityState();
}
```

Wrap `GestureDetector(onTapDown/onTapUp/onTapCancel)` toggling an `AnimatedOpacity`.

### File layout proposal

```
packages/awatv_ui/lib/src/widgets/streas/
  content_card.dart
  content_row.dart
  hero_banner.dart
  live_channel_card.dart
  search_bar.dart
  profile_sheet.dart
  premium_gate.dart
  subtitle_overlay.dart
  error_boundary.dart
  error_fallback_view.dart
  press_opacity.dart           # shared press feedback
packages/awatv_ui/lib/src/theme/
  streas_colors.dart           # ThemeExtension<StreasColors>
packages/awatv_ui/lib/awatv_ui.dart
  # add:
  export 'src/widgets/streas/content_card.dart';
  export 'src/widgets/streas/content_row.dart';
  ...
```

`KeyboardAwareScrollViewCompat` does not get a port — call sites in `apps/mobile` should use plain `SingleChildScrollView`.

### Existing widgets to reuse / audit

| Streas component | Reuse from `awatv_ui` |
|---|---|
| ContentCard | `widgets/poster_card.dart` (audit / extend) |
| LiveChannelCard | `widgets/channel_tile.dart` (audit / extend) |
| HeroBanner | compose `widgets/backdrop_header.dart` + `widgets/gradient_scrim.dart` |
| ErrorFallback | extend `widgets/error_view.dart` |
| (loading skeletons used by ContentRow) | `widgets/shimmer_skeleton.dart` |
| Genre pill in HeroBanner / LiveChannelCard | `widgets/genre_chip_row.dart`, `widgets/rating_pill.dart` |

### Accessibility

The RN components are sparse on a11y (no explicit `accessibilityLabel` / `accessibilityRole` on cards). Fix in Flutter port:
- Wrap each tappable in `Semantics(button: true, label: <descriptive label>)`.
- `Image` → use `semanticLabel: item.title`.
- LIVE badge → `Semantics(label: 'Live now')`.
- For TV / Apple TV target, every focusable card needs `Focus` + visible focused border (ring 2px `primary`).

### Differences worth flagging to product

1. **No light mode** in source — confirm Flutter port should also be dark-only (matches Netflix-style brand).
2. **No image placeholder/blurhash** in RN — Flutter port should add `CachedNetworkImage(placeholder: shimmer, errorWidget: muted-foreground icon)` for production quality.
3. **No card snap on horizontal scroll** — keep parity (free scroll). For TV/desktop, consider snap with `PageScrollPhysics`.
4. **Single-item HeroBanner** in RN — common pattern is a carousel; Flutter port should add an optional `HeroBannerCarousel` widget that takes `List<ContentItem>` and auto-advances every ~6s with `SmoothPageIndicator` dots underneath.
5. **No real "voice search" button** in `SearchBar` — wire the existing `voice_search/` feature into the Flutter port via an optional `onVoice` callback.
6. **`ProfileSheet` 180ms navigation timeout** is a RN workaround — drop in Flutter (use `await Navigator.pop()` or `WidgetsBinding.instance.addPostFrameCallback`).

---

**End of spec.** Total widgets to ship in `awatv_ui`: 10 new + 1 theme extension + 1 press helper. Estimated effort 3-5 days for one Flutter dev to land all of these with tests against `apps/mobile/lib/src/features/home`.
