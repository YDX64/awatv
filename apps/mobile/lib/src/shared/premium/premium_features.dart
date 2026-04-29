/// Every gated capability in the app. The values here are the single
/// source of truth — UI screens import this enum and ask
/// `canUseFeatureProvider` whether to render the unlocked path.
///
/// Adding a new gate is a three-step process:
///   1. Append a value here.
///   2. Add a friendly title/subtitle to [PremiumFeatureCopy].
///   3. Decide in `_freeTierAllowed` (see `feature_gate_provider.dart`)
///      whether the free tier still gets it. Default is "premium only".
enum PremiumFeature {
  /// Beyond the free `FreeTier.playlistLimit` cap.
  unlimitedPlaylists,

  /// Side-by-side or floating multi-stream playback.
  multiScreen,

  /// Picture-in-picture playback (separate from multi-screen because
  /// PiP can be a free perk on some platforms — for now both gated).
  pictureInPicture,

  /// Choosing the VLC backend in player settings.
  vlcBackend,

  /// EPG history beyond `FreeTier.epgPastDays`.
  extendedEpgHistory,

  /// Cloud sync of favourites/history across devices.
  cloudSync,

  /// PIN-locked adult-content gate.
  parentalControls,

  /// Custom theme palettes / accent colours.
  customThemes,

  /// Suppress AdMob banners and interstitials.
  noAds,

  /// Keep audio + video decoding alive when the app is backgrounded
  /// (phone lock, app switcher, window focus loss). Surfaces a lock-
  /// screen / notification "now playing" tile so the user can
  /// pause / resume without re-opening the app.
  backgroundPlayback,

  /// Pin the desktop player window above every other window so the
  /// stream stays visible while the user works or browses elsewhere.
  /// Mirrors the "always on top" toggle reference IPTV apps surface
  /// in their player overlay and tray menu.
  alwaysOnTop,

  /// Catchup / replay TV — Xtream `archive=1` timeshift playback.
  /// Free tier only gets the currently-airing programme; everything
  /// past that is premium. Mirrors how IPTV Expert and ipTV gate
  /// "Replay TV" behind their paywall.
  catchup,

  /// Recording live channels to disk (and the planned recording
  /// scheduler). Premium-only because it consumes both bandwidth and
  /// disk on the user's device.
  recording,

  /// Offline VOD downloads. Free tier is capped at 5 active downloads
  /// at 720p; premium removes both caps and unlocks parallel
  /// downloads beyond the default of 3.
  downloads,

  /// Auto-fetch the best Turkish OpenSubtitles entry as soon as the
  /// player opens — saves one round-trip through the picker for the
  /// most common case. The picker itself (manual search + selection)
  /// is always free; only the "do it for me" automation is gated.
  autoSubtitles,
}

/// Display copy used by the paywall sheet and lock dialog. Kept as a
/// static lookup so the enum stays a pure data type and the strings
/// can be swapped during i18n later.
class PremiumFeatureCopy {
  const PremiumFeatureCopy._();

  static String title(PremiumFeature f) => switch (f) {
        PremiumFeature.unlimitedPlaylists => 'Unlimited playlists',
        PremiumFeature.multiScreen => 'Multi-screen playback',
        PremiumFeature.pictureInPicture => 'Picture-in-picture',
        PremiumFeature.vlcBackend => 'VLC playback engine',
        PremiumFeature.extendedEpgHistory => '14-day EPG history',
        PremiumFeature.cloudSync => 'Cloud sync',
        PremiumFeature.parentalControls => 'Parental controls',
        PremiumFeature.customThemes => 'Custom themes',
        PremiumFeature.noAds => 'Ad-free experience',
        PremiumFeature.backgroundPlayback => 'Arkaplan oynatma',
        PremiumFeature.alwaysOnTop => 'Pencereyi üstte sabitle',
        PremiumFeature.catchup => 'Catchup / Geri sar TV',
        PremiumFeature.recording => 'Canli yayin kaydi',
        PremiumFeature.downloads => 'Cevrimdisi indirme',
        PremiumFeature.autoSubtitles => 'Otomatik altyazi',
      };

  static String subtitle(PremiumFeature f) => switch (f) {
        PremiumFeature.unlimitedPlaylists =>
          'Add as many M3U or Xtream sources as you need.',
        PremiumFeature.multiScreen =>
          'Watch two streams at once with picture-in-picture support.',
        PremiumFeature.pictureInPicture =>
          'Pop the player out into a floating window while you keep browsing.',
        PremiumFeature.vlcBackend =>
          'Switch to the VLC engine for tougher codecs (HEVC, AV1, exotic AAC).',
        PremiumFeature.extendedEpgHistory =>
          'Scroll back two weeks in the program guide instead of one day.',
        PremiumFeature.cloudSync =>
          'Keep favourites, history and settings in sync across your devices.',
        PremiumFeature.parentalControls =>
          'Hide adult content behind a 4-digit PIN.',
        PremiumFeature.customThemes =>
          'Personalise the accent colour and wallpaper packs.',
        PremiumFeature.noAds =>
          'Banishes every banner and interstitial throughout the app.',
        PremiumFeature.backgroundPlayback =>
          'Premium üyelere özel — kilit ekranında ve uygulama dışında '
              'oynatmaya devam.',
        PremiumFeature.alwaysOnTop =>
          'Player penceresi diğer pencereler arkasında kalmaz — bilgisayarda '
              'çalışırken veya gezerken yayını gözden kaçırma.',
        PremiumFeature.catchup =>
          'Gecmis 24-72 saatin programlarini geri sar — Xtream timeshift ile '
              'kacirilan macin tekrarini, yarismanin sonunu, bilim haberini '
              'ne zaman istersen ac.',
        PremiumFeature.recording =>
          'Canli kanali diske kaydet — istedigin kadar uzun, tek dokunusla '
              'baslat ve duraklat. Plan kayit ile yakin tarihli yayinlari '
              'da otomatik yakala.',
        PremiumFeature.downloads =>
          'Filmleri ve bolumleri indir, ucakta veya internetsiz oynat. 3 '
              'paralel indirme, duraklat / surdur / iptal kontrolu.',
        PremiumFeature.autoSubtitles =>
          'Filmi her actigin anda Turkce altyaziyi senin icin bul ve yukle. '
              'Manuel arama herkese acik kalir; bu otomasyon Premium uyelere ozel.',
      };
}
