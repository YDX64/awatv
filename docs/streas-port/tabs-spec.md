# Streas → AWAtv Flutter Port Spec — Tab Screens

> Source: `/tmp/Streas/artifacts/iptv-app/` (React Native + Expo Router, Cherry-red Netflix-inspired palette).
> Target: `/Users/max/AWAtv/apps/mobile/lib/src/features/*` (Flutter monorepo, Riverpod, GoRouter).
> Scope: tab navigation shell + 5 visible tabs + 3 hidden routes.

---

## 0. Design Tokens (port to a Flutter `AwaThemeData` extension)

From `constants/colors.ts`:

| Token | Hex | Flutter equivalent |
|---|---|---|
| `primary` / `tint` / `accent` / `live` / `tag` / `focus` | `#E11D48` (Cherry crimson) | `theme.colorScheme.primary` |
| `primaryDark` | `#9F1239` | `colorScheme.primaryContainer` |
| `primaryDim` (referenced in QUICK_LINKS) | `#BE123C` | custom extension |
| `background` | `#0a0a0a` | `colorScheme.surface` (M3 dark) |
| `card` | `#141414` | custom `surfaceContainerLow` |
| `surface` | `#111111` | custom `surfaceContainer` |
| `surfaceHigh` | `#1c1c1c` | `surfaceContainerHigh` |
| `border` / `input` | `#282828` | `colorScheme.outlineVariant` |
| `mutedForeground` | `#808080` | `colorScheme.onSurfaceVariant` |
| `foreground` / `cardForeground` | `#ffffff` | `colorScheme.onSurface` |
| `gold` | `#f59e0b` | star-favorite accent |
| `destructive` | `#ef4444` | `colorScheme.error` |
| `radius` | `8` | `BorderRadius.circular(8)` baseline |

**Typography** — RN uses `Inter_400Regular` / `Inter_500Medium` / `Inter_600SemiBold` / `Inter_700Bold`. Port as `GoogleFonts.inter()` with `FontWeight.w400/.w500/.w600/.w700`. Title sizes: 11/12/13/14/16/22/28 (px → logical px in Flutter, 1:1 on mobile).

**Tab bar height** in RN: `56 + safeBottomInset`. Flutter equivalent: `NavigationBar(height: 56)` + `MediaQuery.padding.bottom`.

---

## 1. Tab Bar Shell (`app/(tabs)/_layout.tsx`)

### Visual layout
- 5 visible tabs ordered: **Live TV** (`tv`), **Movies** (`film`), **Search** (`search`), **TV Shows** (`monitor`), **Settings** (`user`).
- 3 routes registered with `href: null` (hidden from bar but reachable by deep-link / push): `index` (Home), `guide` (EPG), `favorites`.
- iOS: `BlurView intensity=95 tint="dark"` over `position: absolute` so screen content shows behind. Border-top hairline `colors.border` (`#282828`).
- Android: solid `rgba(10,10,10,0.97)` background + same hairline border.
- Active tint: `colors.primary` (#E11D48). Inactive: `rgba(255,255,255,0.38)`.
- Label: 10px Inter Medium under icon. No badges.
- `tabBarHeight = 56 + insets.bottom (or 8)`. `paddingTop: 6`.

### Behavior
- `headerShown: false` — every screen renders its own header. Some headers are floating overlays on top of a hero image (`movies`, `series`).
- No badge counts. No haptic on tab change. Initial route is `channels` (because `index` is hidden).
- Note: the Home (`index`) screen is reachable only by other navigation calls (e.g., a deep link or "Go home" button). The QUICK_LINKS row on Home points to `(tabs)/movies`, `(tabs)/series`, `(tabs)/search`, `(tabs)/guide`. So if Home is being used as the de-facto landing on a fresh build, the routing layer must push it on top of the tab shell.

### Flutter port mapping
- Closest existing file: `/Users/max/AWAtv/apps/mobile/lib/src/shared/home_shell.dart` (mobile) and `/Users/max/AWAtv/apps/mobile/lib/src/routing/app_router.dart` (GoRouter `StatefulShellRoute`).
- Recommended: extend `home_shell.dart` to use `NavigationBar` (M3) with a `BackdropFilter(filter: ImageFilter.blur(sigmaX:30, sigmaY:30))` overlay on iOS and a flat opaque container on Android. Use `StatefulShellRoute.indexedStack` to keep each branch alive (RN keeps state via React, Flutter must explicitly preserve).
- Hidden routes: declare as sibling top-level GoRoutes on the same shell branch using `redirect: null` and not registering destinations in the bar.
- Recommended widget tree skeleton:
  ```
  StatefulShellRoute.indexedStack
    └── ScaffoldWithNavBar
         ├── IndexedStack(children: [ChannelsScreen, MoviesScreen, SearchScreen, SeriesScreen, SettingsScreen])
         └── _GlassTabBar(items: 5)
              └── ClipRect → BackdropFilter → DecoratedBox(border-top hairline) → NavigationBar
  ```

---

## 2. Home (`index.tsx`) — hidden tab, used as launcher

### Visual layout
- **Floating header** (`position: absolute`): `paddingTop = safeTop + 10`, height `topPad + 56`. Gradient bg `rgba(10,10,10,0.97) → transparent`.
  - Left: 30×30 cherry-red rounded-square (radius 8) with text "AW" + wordmark "AwaTV" (20px Inter Bold, letterSpacing 1).
  - Right: two 36×36 round buttons (radius 18, border 1px `#282828`, bg `#141414`): search icon → push search tab; user icon → opens `ProfileSheet` modal.
- **Hero carousel** (`FEATURED` data, paged FlatList): full-width pages, height ~420 (defined via the `HeroBanner` component in `components/`). Indicator dots below: inactive 6px, active 20px elongated, cherry color, gap 5, marginTop 10.
- **Quick links row**: 4 pills (Movies / TV Shows / Search / TV Guide). Each `flex: 1`, radius 12, padding 12, border 1px, bg `#141414`. Inside: 36×36 rounded icon tile (`color + "22"` overlay = primary at 13% alpha) + 11px label. Horizontal padding 16, gap 8.
- **Live Now section header**: padding-x 16, mt 20, mb 12. Title 16px Inter SemiBold + 8×8 cherry pulse dot. "See All" link in cherry on the right.
- **Live channels row** (horizontal `ScrollView`, gap 10): cards `width 120`, radius 10, border 1px. Top half = `liveLogoBox` height 70 with `surface` bg. Logo 80×48 contain. Fallback: 26px cherry capital initial. Bottom-left "LIVE" tag (cherry, 8px white bold, padding 5/2). Below the box: channel name (11px SemiBold) + program name (10px regular, mutedForeground).
- **No-source banner** (when `channels.length === 0`): 16px h-margin, radius 14, padding 16, gradient `primary 20% → transparent` left-to-right. 40×40 cherry icon tile + title + sub. Two buttons: "Try Free" (cherry filled) + "Add Own" (surface w/ border).
- **Continue Watching row** (`ContentRow` with `showProgress`).
- **Trending Now row** (`ContentRow`).
- **Movies header + row** (`ContentRow` of `MOVIES`).
- **TV Shows header + row** (`ContentRow` of `DRAMA`).
- **TV Guide banner** (full-width card, 16px h-margin, padding 16, gradient `primary 27% → primary 7%`): calendar icon + "TV Guide" / "Full EPG schedule for all channels" + chevron-right. Tappable → push `(tabs)/guide`.
- Bottom padding = `insets.bottom + 80` (clears the floating tab bar).

### Behavior
- Hero pager: paging FlatList, `pagingEnabled`, snap to `width`. Index tracked via `onMomentumScrollEnd`. Tap dot to `scrollToIndex`. **No autoplay** — user-driven only.
- Live channel tap → `addRecentChannel` + `setActiveChannel` + push `/tv-player?channelId=`.
- Quick link tap → `router.push(route)`.
- "Try Free" loads `https://iptv-org.github.io/iptv/categories/news.m3u` via `loadSamplePlaylist`. Spinner shown while loading. "Add Own" pushes `/add-source`.
- `ProfileSheet` modal opens on user-button tap.
- Pull-to-refresh: **not implemented** in source — single `ScrollView`.

### Data flow
- Reads from `useContent()`: `myList` helpers (`addToList/removeFromList/isInList`), `channels`, `getCurrentProgram`, `addRecentChannel/setActiveChannel`, `isFavorite`, `loadSamplePlaylist`, `isLoadingSource`.
- Hero/Continue Watching/Trending/Movies/Drama from static `data/content.ts`.
- No HTTP triggered on mount aside from optional sample playlist. No react-query — context manages state.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/home/home_screen.dart` + `home_hero.dart` + `home_row.dart` + `home_row_item.dart` + `home_data.dart`.
- Port required:
  - **New**: floating `AwaTopBar` with cherry "AW" mark, blur header gradient (use `Stack` + `IgnorePointer` + `LinearGradient`).
  - **New**: paged `PageView.builder` for FEATURED hero with `SmoothPageIndicator` (already a common dep) showing the elongated active dot.
  - **Adapt**: `home_row.dart` already produces horizontal lists — extend with `showProgress` flag for Continue Watching (thin 2px progress bar at card bottom, cherry fill).
  - **New**: `_LiveChannelStrip` widget (120-wide cards) consuming `ChannelsRepository.liveChannels()` + `EpgService.currentProgram(channelId)`.
  - **New**: `_NoSourceBanner` widget; tied to `playlistsControllerProvider`.
  - **New**: `_QuickLinksRow` (4 `Expanded` `Material` cards routing via `context.go(...)`).
  - **New**: `_GuideBanner` with `LinearGradient` + `context.go('/guide')`.
- Recommended widget tree:
  ```
  Scaffold
    body: Stack
      ├── CustomScrollView (slivers)
      │    ├── SliverPadding(top: insets.top + 56)  // make space for floating header
      │    ├── SliverToBoxAdapter(_HeroCarousel)
      │    ├── SliverToBoxAdapter(_QuickLinksRow)
      │    ├── SliverToBoxAdapter(_LiveNowSectionHeader)
      │    ├── SliverToBoxAdapter(_LiveChannelStrip OR _NoSourceBanner)
      │    ├── SliverToBoxAdapter(HomeRow.continueWatching)
      │    ├── SliverToBoxAdapter(HomeRow.trending)
      │    ├── SliverToBoxAdapter(_MoviesHeader + HomeRow.movies)
      │    ├── SliverToBoxAdapter(_TvShowsHeader + HomeRow.drama)
      │    └── SliverToBoxAdapter(_GuideBanner)
      └── _FloatingHeader  // Positioned, uses BackdropFilter
  ```

---

## 3. Live TV / Channels (`channels.tsx`) — visible tab #1

### Visual layout
- **Two-column layout**: left sidebar (110px) = group list, right column = channel list.
- **Sidebar** bg `surface` (`#111111`), `borderRightWidth: hairline`. Each group button: padding 12/10, centered 11px Inter SemiBold text. Active state: bg `primary + "22"` (13% alpha cherry tint), `borderRightWidth: 3`, `borderRightColor: primary`. Group count 10px regular below name. The first three pseudo-groups are `All Channels`, `★ Favorites`, `⟳ Recent`.
- **Right column header**: `card` bg, hairline bottom border, padding 12. Top row: "Live TV" (16px Inter Bold) + count "{N} ch" (11px regular, mutedForeground). Below: search input row — `surface` bg, border 1px, radius 8, padding 10/7, search icon left + TextInput + clear-X (only when text present).
- **Channel row** (FlatList item): height ~64px, padding 10/12, hairline bottom border, gap 10. Layout: `[chNumber 28×28 rounded-6 surface bg]` + `[logoBox 44×44 card bg radius 8]` + `[chInfo flex:1]` + `[chActions star + livedot]`.
  - chNumber: index+1 in 11px medium.
  - logoBox: 40×40 contain image; fallback 18px cherry initial.
  - chInfo: name 13px SemiBold + below either `programRow` (program name 11px + 2px progress bar w/ cherry fill) or "No EPG data" (11px in border-color).
  - chActions: star (size 16, gold if fav, border-color else) + 7×7 cherry live dot.

### States
- Loading: centered spinner (large, cherry) + "Loading channels..." 14px regular muted.
- Error: alert-circle 40px in `live` color + "Load Error" 16px SemiBold + error message + "Using demo channels" hint.
- Empty: tv icon 40px border-color + "No channels found" 14px regular muted.

### Behavior
- `activeGroup` state: `useState(ALL_GROUP)`. `filtered` useMemo over `channels`, applying group + search filters.
- Tap channel → haptic medium (non-web) + `addRecentChannel` + `setActiveChannel` + push `/tv-player`.
- Tap star → `toggleFavorite(item.id)` (hit slop 10px each side).
- Search debounce: none — instant filter on every keystroke.
- No infinite scroll, no pull-to-refresh.

### Data flow
- Reads: `channels`, `isLoadingSource`, `sourceError`, `favorites`, `isFavorite`, `toggleFavorite`, `recentChannels`, `addRecentChannel`, `setActiveChannel`, `getCurrentProgram`.
- Groups derived as `Set` of `c.group`. Recent stored separately, foreground-only display.
- Per-row `progress = (now - prog.startTime) / (prog.endTime - prog.startTime)`.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/channels/channels_screen.dart` + `group_filter_chips.dart` + `channels_providers.dart` + `epg_providers.dart`.
- AWAtv currently uses chips (top horizontal) instead of side rail — needs **redesign to side rail** to match Streas. Add `SortModeProvider` reuse for ordering.
- New widgets:
  - `_GroupRail` (110-wide, `ListView.builder`, selected state with `border(right: 3px, color: primary)` and 13% alpha tint).
  - `_ChannelTile` (replace any current tile to match: number badge + logo + name + EPG progress + star + live dot).
  - `_EpgProgressBar` reusable (2px tall, `LinearProgressIndicator(minHeight: 2, valueColor: ..primary, backgroundColor: outlineVariant)`).
- Should be wired to `channelsControllerProvider` (Riverpod). Group filter from `selectedGroupProvider`. Search from a `searchQueryProvider` (`StateProvider<String>`).
- Skeleton:
  ```
  Scaffold(body: Row(children: [
    SizedBox(width: 110, child: _GroupRail()),
    Expanded(child: Column(children: [
      _ChannelsHeader(query, onChanged),
      Expanded(child: AsyncValueWidget(filtered, builder: ListView.separated(...)))
    ])),
  ]))
  ```

---

## 4. Movies (`movies.tsx`) — visible tab #2

### Visual layout
- **Hero block**: 420 tall, full-width image of `FEATURED[0].banner || .thumbnail`, `cover` fit. 3-stop bottom gradient (`transparent → rgba(10,10,10,0.7) → #0a0a0a`). Content padded 20:
  - Optional "NEW RELEASE" badge (cherry pill, 10px white bold letterSpacing 1).
  - Title 30px Inter Bold white.
  - Genre row (13px regular muted).
  - Action row: white "Play" pill (icon + 14px black bold) + "My List" outlined pill (border `rgba(255,255,255,0.3)`, bg `rgba(255,255,255,0.1)`, 16px plus icon + 14px white SemiBold).
- **Header overlay** (`position: absolute`, `paddingTop: safeTop + 8`): just "Movies" title 22px Inter Bold, no actions.
- **Genre filter** horizontal scroll: pills padding 14/7, radius 20, border 1px. Selected = cherry bg + white text; idle = `card` bg + `border` outline + muted text. 8 genres: All, Action, Drama, Sci-Fi, Horror, Comedy, Thriller, Animation. Padding-left 16.
- **Section header**: title (16px Bold, "All Movies" or selected genre) + count "{N} titles" (12px regular muted).
- **Grid**: 3 columns, `width: 31%`, aspectRatio 2/3, radius 10, gap 8, h-padding 12. Each `MovieCard`:
  - poster cover image (`thumbnail`).
  - bottom gradient `transparent → rgba(0,0,0,0.85)` from y=0.5.
  - "NEW" badge top-left if `isNew` (cherry, 8px bold).
  - Bottom info: title (11px SemiBold white) + meta row (year + rating pill `rgba(255,255,255,0.15)` + duration), 9px regular.

### Behavior
- Tap card → push `/detail/{id}`.
- Tap hero "Play" → push `/detail/{heroMovie.id}` (note: maps to detail, not direct play in current source).
- Tap "My List" on hero is decorative — no handler (TODO upstream).
- Tap genre pill → set state, list re-filters via `genre.includes(selectedGenre)`.

### Data flow
- Static: `MOVIES` + `EXTRA_MOVIES` (12 hardcoded) + `FEATURED[0]` for hero.
- No actual VOD context use — Streas mock in this file. The real Xtream VOD data is read on Search and on Settings.
- Pagination: none (full grid rendered, ~22 items).

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/vod/vod_screen.dart`.
- AWAtv already has `vodControllerProvider` returning real Xtream VODs. The Streas hardcoded mock list should be **replaced with the real `vodControllerProvider`** filtered by genre.
- Build `_VodHero` from a featured VOD (or from a separate `featuredVodProvider`).
- Genre filter: simple `String?` provider; `Wrap`/`SingleChildScrollView` of `ChoiceChip`s using the cherry palette.
- Grid: `SliverGrid` with `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2/3, mainAxisSpacing: 8, crossAxisSpacing: 8)`.
- Skeleton:
  ```
  CustomScrollView(slivers: [
    SliverToBoxAdapter(_VodHero),
    SliverPersistentHeader(_GenreFilterBar),
    SliverPadding(SliverGrid(_VodCard)),
  ])
  ```
- The "Movies" title overlay should be a `Positioned` `Text` over the hero, blending into the gradient — use `Stack`.

---

## 5. TV Shows / Series (`series.tsx`) — visible tab #4

### Visual layout
Mostly identical structure to Movies, with these differences:
- Hero uses `FEATURED[1]`, has a **"TV SHOWS"** badge in **gold (`#f59e0b`)** (not cherry) with 10px black bold letterSpacing 1.
- Hero CTAs: "Watch Now" (filled white) + "Watchlist" (outlined, bookmark icon).
- **New Episodes** horizontal row (above genre filter). Section header has live cherry dot + 16px Bold + "See All" cherry text. Cards `width 130 × height 190`, radius 10, with gradient overlay, "NEW" badge, title 12px + sub `genre · year` 10px.
- **Genre filter**: 9 genres incl. "Reality" and "Kids" (vs Movies' 8).
- **Grid**: same as Movies (3 cols, 2:3 aspect). Cards have a slightly different meta layout — genres separated by " · ".

### Behavior
- Same: tap card → `/detail/{id}`. Tap pill → filter. No pagination.
- "See All" on New Episodes is decorative — no handler.

### Data flow
- Static merge of `EXTRA_SERIES` (12) + `TRENDING` + `DRAMA`. Same caveat — should be backed by real `xtreamSeries`.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/series/series_screen.dart`.
- Wire to `seriesControllerProvider` for the grid; add a `newEpisodesProvider` returning items where `releaseDate` falls within the last N days (or a server-side flag).
- Reuse `_VodHero`-shaped widget but configurable: `badgeText: 'TV SHOWS'`, `badgeColor: gold`, `actionLabels: ['Watch Now', 'Watchlist']`.
- New Episodes strip: dedicated `SizedBox(height: 190)` with horizontal `ListView.builder`, fixed-width 130 cards.

---

## 6. Search (`search.tsx`) — visible tab #3

### Visual layout
- **Header** (sticky-feeling, `paddingTop: safeTop + 8`):
  - Title "Search" 28px Inter Bold, letterSpacing -0.3.
  - Search box: `surface` bg, border 1px, radius 12, padding 16/13 (iOS) or 16/11 (Android). Icon + TextInput (15px regular) + circular clear button (18×18 round, `mutedForeground` bg, 11px X glyph) when text length > 0.
  - On tablet (`width >= 768`): `maxWidth 600`, centered.
- **Empty body** (query length < 2):
  - **Popular Searches** section: 15px Bold title + flex-wrap pills row. Each pill: `surface` bg, border 1px, radius 22, padding 14/9, trending-up icon (cherry, 12px) + label (13px medium). Items: News, Sports, Movies, Kids, Music, TV Shows.
  - **Browse by Category** section: 2-column grid. Each card: 14px padding, radius 12, border 1px, `surface` bg. Inside: 36×36 cherry-tinted icon tile + group name (13px Bold) + count "{N} ch" (11px regular). Icon resolved from `CATEGORY_ICONS` map (defaults to `tv`).
- **No-results body** (query >= 2 but no hits): centered search icon 44px in border color + "No results found" 17px Bold + suggestion line 13px regular muted.
- **Results body** (SectionList): three sections — Live Channels, Movies, TV Shows — only rendered if non-empty. Header per section: 11px Bold uppercase muted with letterSpacing 1, padding-y 8.
- **Result row**: padding-y 13, gap 12, hairline bottom border. 48×48 left tile (`surface` bg, radius 10, image cover or fallback Feather icon 20px cherry). Title 14px SemiBold + subtitle 12px regular muted. Right "type badge" pill: padding 8/4, radius 6, color-coded:
  - channel → bg `#E11D4822` (cherry @13%), text `live` color, label "LIVE".
  - vod → bg `#ffffff15`, text `rgba(255,255,255,0.7)`, label "MOVIE".
  - series → bg `#f59e0b22`, text gold, label "SHOW".

### Behavior
- Query state local. Trigger results when `length >= 2`.
- Searches across `channels` (name/group), `xtreamVods` (name/categoryName), `xtreamSeries` (name/genre). Caps: 15 channels, 15 vods, 10 series.
- Tap channel result → addRecentChannel + setActiveChannel + push `/tv-player`. Tap VOD/series → no handler in source (TODO: navigate to detail).
- Tap popular pill or category card → fills the input with that string.
- No debounce; no async fetch — purely client-side filter.

### Data flow
- Reads: `channels`, `xtreamVods`, `xtreamSeries`, `getCurrentProgram`, `addRecentChannel`, `setActiveChannel`.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/search/search_screen.dart` (single file — likely simpler currently).
- New widgets to build:
  - `_SearchField` with rounded-12 box, clear button, tablet-max-width clamp using `LayoutBuilder`.
  - `_PopularPills` (`Wrap`).
  - `_CategoryGrid` (2-col `GridView.count` with `_CategoryCard`).
  - `_ResultRow` parameterised by `ResultType` enum (channel / vod / series) determining badge color + tap handler.
- Add `searchResultsProvider = Provider<List<SearchResult>>` that combines streams from channels, VODs, series — or use a `family` keyed on the query string with `select` to limit rebuilds.
- Skeleton:
  ```
  Scaffold(body: Column(children: [
    _SearchHeader(controller, query),
    Expanded(child: query.length < 2
      ? _BrowseScroll(popular, categories)
      : results.isEmpty
        ? _NoResults(query)
        : _ResultsList(sections))
  ]))
  ```

---

## 7. TV Guide / EPG (`guide.tsx`) — hidden route

### Visual layout
- **Header** (`surface` bg): "TV Guide" 22px Bold + horizontal `datePills` strip. 7 dates (`-1` to `+5` from today). Pills 14/6 padding, radius 16, border 1px. Active (cherry bg + white text) vs idle (card bg + outline + muted text). Labels: "Yesterday", "Today", "Tomorrow", then weekday short.
- **Program detail bar** (only when a cell is tapped): card bg, hairline bottom. Padding 16/10, gap 12. Title (14px SemiBold) + "{ChannelName} · HH:MM – HH:MM" (11px) + description (11px, 1 line). Right side cherry "Watch" pill (icon + 12px white bold).
- **Guide grid** (horizontal-scroll body):
  - **Time row** (header, height 32, `surface` bg). First cell `CHANNEL_COL = 90`-wide clock icon. Then 18 time cells each `TIME_SLOT_WIDTH = 120` wide, hairline left border, time text 11px medium muted.
  - **Now line** (only when "Today"): 2px vertical bar in cherry, `position: absolute`, `left = 90 + diffMins * 2`. Spans full grid height.
  - **Channel rows** (`CELL_HEIGHT = 56`, hairline bottom):
    - Left "channelNameCell" (`width: 90`, `surface` bg, hairline right): logo 32×20 contain or 16px cherry initial + name 9px medium.
    - Right "programsRow": each program `width = max(durationMin * 2, 40)`. Background:
      - selected → cherry solid.
      - currently airing → cherry @19% alpha, left border 2px cherry.
      - else → card bg.
      - Title 11px SemiBold (white if selected, foreground if now, muted otherwise). Time line 9px (only if width > 80).
- Display capped to `channels.slice(0, 30)` rows.

### Behavior
- Date selection: index 0..6, default to "Today" (index 1 in array, internal `selectedDate=0` means today).
- 18 half-hour slots starting 06:00 — schedule window 06:00–15:00.
- Tap program → set `selectedProgram` + `selectedChannel` (shows the detail bar).
- Long-press program → `handlePlay(channel)` → push `/tv-player`.
- Tap "Watch" pill in detail bar → `handlePlay`.
- No vertical-horizontal scroll-locking — uses an outer horizontal `ScrollView` containing a non-scrollable `FlatList` of rows; the cap of 30 rows means the page can fit comfortably.

### Data flow
- Reads: `channels`, `getProgramsForChannel`, `getCurrentProgram`, `addRecentChannel`, `setActiveChannel`.
- Programs filtered by overlap with the visible window.
- Mock EPG generator (`generateMockEPG`) — real Xtream EPG via `xmltv_url` is the upstream source.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/channels/epg_grid_screen.dart` + `epg_providers.dart`.
- The Flutter EPG grid likely already exists but needs:
  - A 7-day date pill strip (port the chips visual).
  - Program detail bar behaviour (selected program state).
  - Visual now-line (`Positioned(left: nowOffset, child: Container(width: 2))`).
- Use `InteractiveViewer` or **two coupled `ScrollController`s** (one horizontal, one vertical) for the grid — Flutter alternative is `TwoDimensionalScrollView` (Flutter 3.16+). Existing AWAtv likely uses a `SingleChildScrollView` strategy similar to Streas.
- Skeleton:
  ```
  Scaffold(body: Column(children: [
    _GuideHeader(dates, selectedDate),
    if (selectedProgram != null) _ProgramDetailBar(selectedProgram, channel),
    Expanded(child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 90 + 18 * 120,
        child: Column(children: [
          _TimeHeaderRow(slots),
          Expanded(child: Stack(children: [
            ListView.builder(itemCount: 30, itemBuilder: _ChannelEpgRow),
            if (isToday) Positioned(left: nowOffset, child: _NowLine()),
          ])),
        ]),
      ),
    )),
  ]))
  ```

---

## 8. Favorites (`favorites.tsx`) — hidden route

### Visual layout
- **Header**: padding 16, `paddingTop: safeTop + 12`, gap 2. "Favorites" 28px Bold + "{N} channels" 13px regular muted.
- **Recently Watched** (only when `recentChannels.length > 0`): 14px SemiBold section title (h-padding 16, mb 10). Horizontal `FlatList` of up to 10 cards.
  - Card: width 70, radius 10, border 1px, paddingBottom 8, alignItems center.
  - 70×50 logo box (`surface` bg) — image 50×36 contain or 22px cherry initial.
  - Name: 9px medium muted, marginTop 4, paddingX 4, centered.
- **Your Favorites** section title (14px SemiBold).
- **Empty state**: star icon 52px in border color + "No favorites yet" 18px SemiBold + "Tap the star on any channel to add it here" 13px regular muted (centered with paddingX 40).
- **Favorites list** (vertical FlatList, gap 10, h-padding 16):
  - Card: row layout, radius 12, border 1px, padding 12, gap 12.
  - Left logo area 56×56, radius 10, `surface` bg. Image 48×36 contain or 22px cherry initial. Bottom-right tiny 8×8 cherry live dot.
  - Center info (`flex:1`, gap 3): name 14px SemiBold + group 11px regular muted + program 11px regular muted + 2px progress bar (cherry).
  - Right star button (gold, size 18, padding 6, hit slop 10).

### Behavior
- Tap card → addRecent + setActive + push `/tv-player`.
- Tap star → toggleFavorite (removes from list — list re-renders).
- No search/filter on this screen; no pull-to-refresh.

### Data flow
- Reads: `channels`, `isFavorite`, `toggleFavorite`, `recentChannels`, `addRecentChannel`, `setActiveChannel`, `getCurrentProgram`.
- Derived: `favoriteChannels = channels.filter(c => isFavorite(c.id))`.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/favorites/favorites_screen.dart` + `favorites_providers.dart` + `folder_picker_sheet.dart`.
- AWAtv adds folders (`folder_picker_sheet`); Streas does not. Keep AWAtv's folder support but layer the **Recently Watched strip** above the folder/grid.
- New widgets:
  - `_RecentChannelStrip` (horizontal `ListView`, 70-wide cards).
  - `_FavoriteCard` (port the row layout — logo + meta + EPG progress + star button).
- Wire to `recentChannelsProvider` (`/Users/max/AWAtv/apps/mobile/lib/src/shared/channel_history/`) and `favoritesControllerProvider`.

---

## 9. Settings (`settings.tsx`) — visible tab #5

### Visual layout
- **Profile / app header**: row, padding-x 16, mb 16, gap 14. 52×52 cherry-tinted square (radius 14) with user icon + title "My Account" (22px Bold) + sub "AwaTV · v1.0 · {N} channels loaded" (11px regular muted) + cherry "Add Source" pill (icon + 12px white bold).
- **Premium banner** (one of three states):
  - Loading: card bg + spinner + "Checking subscription…".
  - Subscribed: green-tinted card (bg `#22c55e18`, border `#22c55e55`) + check-circle 22px green + "AwaTV Premium Active" + "Renews {date}" + "PRO" pill.
  - Free: card bg, cherry-tinted gradient overlay (left→right), 30×30 cherry icon tile (`zap`) + "Upgrade to Premium" + price preview + chevron-right cherry. Tap → `/paywall`.
- **Section pattern** (used 6×): cherry section label uppercase 11px Bold letterSpacing 1.5, padding-x 16, mb 10, mt 8. Followed by a `card` (radius 12, border 1px, h-margin 16) containing `Row` items.
- **Row** widget: padding 14/12, hairline bottom border, gap 12. Layout: 30×30 icon tile (cherry @13% bg, or destructive @13% if `danger`) + label (13px medium) + optional description (11px regular muted) + right-side value (12px regular muted) + chevron OR `Switch` (M3 default, cherry track when on).
- **Sections in order**:
  1. **Playlists & Accounts** — empty card with dashed border + "Add Your First Playlist" + two pills ("Try 800+ Free" green, "Add Playlist" cherry). Or grid of `SourceCard`s (radius 14, padding 14): top row icon + name + type-line + active pill (cherry "ACTIVE"). Stats row (channels / status / expires / connections). Action row: "Use This" or "Refresh" + "Remove" (destructive @9% bg). When non-subscribed and >=1 source: lock card linking to `/paywall`.
  2. **Player** — 9 rows: default player, hardware decoding (toggle), buffer size (cycles 1/3/5/10s), preferred format (auto/hls/ts/dash), double-tap seek (5/10/15/30s), swipe volume (toggle), swipe brightness (toggle), autoplay (toggle), remember position (toggle).
  3. **Supported Stream Formats** — 7 read-only rows with colored 8px dot + name + description + green check (HLS, MPEG-DASH, MPEG-TS, MP4/H.264, MKV/H.265, RTMP/RTSP, SRT).
  4. **Subtitles** (Premium-gated; opacity 0.6 when locked, taps redirect to `/paywall`):
     - Enable toggle, default language row.
     - Sub-section pickers: SIZE (S/M/L/XL), POSITION (Bottom/Top), BACKGROUND (None/Semi/Solid). Pills 14/6 padding radius 8.
     - COLOR sub-section: 6+ color dots 26×26 round, selected has 2.5px white border.
     - Bold toggle + OpenSubtitles API key row.
     - **Subtitle preview** card (16px h-margin, 90 tall, black bg, radius 12): renders sample subtitle with current size/color/background/bold + a hint line.
  5. **Playback** — subtitles toggle + stream format toggle (TS ↔ M3U8).
  6. **Parental Controls** — PIN protection + adult content filter toggle.
  7. **About** — 10 read-only rows (version, Xtream Codes API, M3U variants, XMLTV EPG, OpenSubtitles.com, players, languages, subscription, Flutter conversion, platforms).

### Behavior
- All toggles persist via `updatePlayerSettings` / `updateSubtitleSettings` / `updateSettings` (AsyncStorage).
- Cycling rows (default player, buffer, format, double-tap seek): tapping cycles through a tuple.
- Premium-gated subtitle controls: short-circuit to `router.push('/paywall')` if not subscribed.
- "Add Source" → `/add-source`. "Refresh" runs `refreshActiveSource()`. "Remove" calls `removeSource(id)` (no confirm dialog in source — should add).
- Paywall integration: RevenueCat (`useSubscription` hook) — Flutter port uses `purchases_flutter`.

### Data flow
- Reads from `useContent`: sources, activateSource, removeSource, refreshActiveSource, isLoadingSource, loadSamplePlaylist, settings, updateSettings, channels.
- Reads from `useSubtitle`: subtitleSettings, playerSettings, updateSubtitleSettings, updatePlayerSettings.
- Reads from `useSubscription`: isSubscribed, isLoading, monthlyPackage, customerInfo.

### Flutter port mapping
- Closest: `/Users/max/AWAtv/apps/mobile/lib/src/features/settings/settings_screen.dart`.
- AWAtv likely has a partial settings screen — needs to be **expanded significantly**. Build:
  - `_SectionLabel` (11px cherry uppercase letterSpacing 1.5).
  - `_SettingsCard` (rounded card with hairline-divided rows).
  - `_SettingsRow` (icon tile + label + desc + value/chevron OR switch).
  - `_OptionPills<T>` (generic horizontal pill picker).
  - `_ColorDotRow` (subtitle color picker).
  - `_PremiumBanner` (3-state: loading/active/upsell, with linear gradient cherry overlay).
  - `_SourceCard` (Xtream/M3U source with stats grid + actions).
  - `_SubtitlePreviewBox` (live preview reflecting current subtitle settings — port `SUBTITLE_SIZE_MAP`/`SUBTITLE_COLOR_MAP`/`SUBTITLE_BACKGROUND_MAP` to a Dart enum extension).
  - `_FormatRow` for supported formats list.
- Wire toggles to existing AWAtv providers in `/shared/` and `/features/playlists/`.
- Skeleton:
  ```
  Scaffold(body: SingleChildScrollView(child: Column(children: [
    _AppHeader(channelCount, onAddSource),
    _PremiumBanner(state),
    _Section('PLAYLISTS & ACCOUNTS', _PlaylistsBody()),
    _Section('PLAYER', _PlayerSettingsCard()),
    _Section('SUPPORTED STREAM FORMATS', _FormatsCard()),
    _Section('SUBTITLES', _SubtitleSettingsCard(), gated: !isSubscribed),
    _SubtitlePreviewBox(),
    _Section('PLAYBACK', _PlaybackCard()),
    _Section('PARENTAL CONTROLS', _ParentalCard()),
    _Section('ABOUT', _AboutCard()),
  ])))
  ```

---

## 10. Cross-cutting concerns

### Cache strategy
Streas does **not** use react-query. State lives in a single React Context (`ContentProvider`) hydrating from `AsyncStorage` on mount. Persisted keys:
- `awatv_my_list` — VOD watchlist.
- `awatv_sources` — playlist sources.
- `awatv_favorites` — favorite channel IDs.
- `awatv_recent_channels` — last 20 watched.
- `awatv_settings` — `AppSettings`.
- `awatv_channels` — declared but not persisted explicitly in current code.

Flutter equivalent: **Riverpod + `SharedPreferences` (or `flutter_secure_storage` for Xtream creds)**, replacing each AsyncStorage call. Add `riverpod_annotation` providers per domain (`favoritesNotifierProvider`, `sourcesNotifierProvider`, etc.). For HTTP-heavy operations (Xtream auth, VOD/series fetches) wrap with `AsyncNotifier` + `keepAlive: true` to mimic the in-memory cache.

### Loading / error / empty patterns
- Loading: cherry `ActivityIndicator` (large) + 14px regular muted label. Flutter: `CircularProgressIndicator(color: primary)` inside a `Center` with `Column`.
- Error: `Feather.alert-circle` 40px in `live` (cherry) color + title 16px SemiBold + sub messages 13px regular muted. Flutter: `Icon(Icons.error_outline)` + `Text` stack.
- Empty: large neutral icon (40–52px) in border color + title + tip text. Flutter equivalent identical.

### Animations & gestures
- Hero pager: paged-snap horizontal scroll. Flutter: `PageView` with `viewportFraction: 1`.
- Indicator dots: width transition active(20)/idle(6). Flutter: `AnimatedContainer(duration: 250ms)`.
- Channel/Movie row taps: `activeOpacity: 0.75–0.9`. Flutter: `InkWell` with `splashColor: primary @20%`.
- Haptic on channel play (Live TV tab): `Haptics.impactAsync(Medium)`. Flutter: `HapticFeedback.mediumImpact()`.
- Card hover: not applicable on mobile. For TV/desktop builds (`tv_home_shell`, `desktop_home_shell`), use `Focus` + scale animation on focus.
- No skeleton loaders in source — Streas just shows spinners. Flutter port: optional improvement using `shimmer` package for content rows.

### Pagination & infinite scroll
**Not used** — every list is fully materialized. For real-world Xtream catalogs (5k+ VODs) the Flutter port should add lazy pagination via `Sliver` lists + `infinite_scroll_pagination` package, especially for Movies and Series tabs.

### Pull-to-refresh
**Not implemented** in source. Recommended Flutter additions:
- `RefreshIndicator(color: primary, onRefresh: refreshActiveSource)` wrapping the body of Channels and Home.
- On Settings, refreshing the active source is already exposed via the `Refresh` row action.

### Routing transitions
Expo Router default (slide-from-right). Flutter `GoRouter` default mirrors that. Tab switches do NOT animate the bar — only the body. When pushing `/tv-player`, Streas uses default modal-style. Flutter equivalent: `MaterialPage` for VOD detail, custom `PageRouteBuilder` with `FadeTransition` for the player to feel cinematic.

---

## 11. Routing summary (for `app_router.dart` updates)

```
/                       → redirect to /channels (since `index` is hidden in tabs)
/home                   → HomeScreen (hidden but reachable)
/channels               → ChannelsScreen           (tab 1, icon: tv)
/movies                 → MoviesScreen             (tab 2, icon: movie)
/search                 → SearchScreen             (tab 3, icon: search)
/series                 → SeriesScreen             (tab 4, icon: monitor)
/settings               → SettingsScreen           (tab 5, icon: person)
/guide                  → GuideScreen              (hidden)
/favorites              → FavoritesScreen          (hidden)
/detail/:id             → DetailScreen
/player/:id             → PlayerScreen (VOD)
/tv-player              → TvPlayerScreen (live)
/add-source             → AddSourceScreen
/paywall                → PaywallScreen
```

`StatefulShellRoute.indexedStack` should host the 5 visible tabs; the 3 hidden routes (`/home`, `/guide`, `/favorites`) sit as siblings on the same shell branch so they share the bottom bar but don't appear as bar items.

---

## 12. File-by-file mapping summary

| Streas file | Closest Flutter file (AWAtv) | Action |
|---|---|---|
| `app/(tabs)/_layout.tsx` | `lib/src/shared/home_shell.dart` + `routing/app_router.dart` | **Adapt** — switch to 5-item NavigationBar with iOS blur. |
| `app/(tabs)/index.tsx` | `features/home/home_screen.dart` | **Adapt** — add hero pager, quick links, live strip, no-source banner, guide banner. |
| `app/(tabs)/channels.tsx` | `features/channels/channels_screen.dart` | **Adapt** — switch from chips to side rail, add EPG progress in tile, search field. |
| `app/(tabs)/movies.tsx` | `features/vod/vod_screen.dart` | **Adapt** — add 420-tall hero, genre pill row, real VOD provider behind grid. |
| `app/(tabs)/series.tsx` | `features/series/series_screen.dart` | **Adapt** — gold-badged hero, "New Episodes" strip, genre filter, real series provider. |
| `app/(tabs)/search.tsx` | `features/search/search_screen.dart` | **Build** — full search UX with popular pills, category grid, sectioned results, type badges. |
| `app/(tabs)/guide.tsx` | `features/channels/epg_grid_screen.dart` | **Adapt** — add 7-day pill strip, program detail bar, now-line. |
| `app/(tabs)/favorites.tsx` | `features/favorites/favorites_screen.dart` | **Adapt** — add Recently Watched strip; keep AWAtv's folder support. |
| `app/(tabs)/settings.tsx` | `features/settings/settings_screen.dart` | **Build** — full settings expansion with sections, pickers, sub-preview, RevenueCat. |
| `context/ContentContext.tsx` | (split across) `features/playlists/`, `shared/channel_history/`, `features/favorites/favorites_providers.dart`, etc. | **Map** to existing Riverpod providers; consolidate where missing. |
| `constants/colors.ts` | `lib/src/app/theme.dart` (or `themes/` feature) | **Port** as `AwaColors` ThemeExtension. |
