/// Channel-logo fallback resolver.
///
/// Maps a free-text channel name to a candidate logo URL on the
/// **tv-logo/tv-logos** GitHub repo (CC-licensed community library —
/// https://github.com/tv-logo/tv-logos). Used by the channel tile when
/// the playlist source either ships no `logoUrl` or the URL fails to
/// load. The repo lays out files like:
///
/// ```text
/// countries/
///   turkey/
///     trt-1-hd.png
///     show-tv-tr.png
///   world/
///     bbc-news-uk.png
/// ```
///
/// `LogosFallback` does no network work — it only computes URL
/// candidates. The caller (typically the cached_network_image
/// `errorWidget` chain) probes them. We try Turkey-first because the
/// app's primary audience is TR; the world bucket is the second guess.
class LogosFallback {
  const LogosFallback._();

  /// Base raw-content URL of the tv-logos repository.
  static const String _base =
      'https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries';

  /// Word-boundary regex of resolution / quality tokens we want to drop
  /// before slugifying. Keeping them in the slug would make e.g.
  /// `BBC News HD` and `BBC News` look like different files even though
  /// the repo only has the canonical `bbc-news-uk.png`.
  static final RegExp _qualityTokens = RegExp(
    r'\b(uhd|fhd|hd|sd|4k|8k|1080p|720p|480p)\b',
    caseSensitive: false,
  );

  /// Punctuation we strip out before joining slug parts. `[`, `]`, `(`,
  /// `)` and `|` are common in IPTV M3U names and would corrupt the
  /// resulting filename. Hyphens and underscores survive — they're
  /// turned into single hyphens by [_slugify].
  static final RegExp _punct =
      RegExp(r'[^\p{L}\p{N}\s_-]+', unicode: true);

  /// One or more whitespace runs — collapsed to a single hyphen.
  static final RegExp _spaces = RegExp(r'\s+');

  /// Multiple consecutive hyphens — collapsed to one.
  static final RegExp _multiDash = RegExp('-{2,}');

  /// Returns the best-guess Turkey URL or `null` if the input is empty.
  ///
  /// The companion [worldUrlFor] returns the second candidate. Use
  /// [candidatesFor] to get the ordered list when probing both.
  static String? urlFor(String channelName) {
    final slug = _slugify(channelName);
    if (slug.isEmpty) return null;
    return '$_base/turkey/$slug.png';
  }

  /// Second-guess URL in the `world/` bucket of the same repo.
  static String? worldUrlFor(String channelName) {
    final slug = _slugify(channelName);
    if (slug.isEmpty) return null;
    return '$_base/world/$slug.png';
  }

  /// Ordered list of URL candidates. Prefer this when a caller wants to
  /// retry on 404 — currently `[turkey, world]`. Empty when the input
  /// produces no slug (all punctuation / whitespace).
  static List<String> candidatesFor(String channelName) {
    final slug = _slugify(channelName);
    if (slug.isEmpty) return const <String>[];
    return <String>[
      '$_base/turkey/$slug.png',
      '$_base/world/$slug.png',
    ];
  }

  /// Public slugifier — exposed for tests and for the metadata-cache key
  /// in `channel_tile.dart`.
  static String slugify(String channelName) => _slugify(channelName);

  static String _slugify(String value) {
    if (value.isEmpty) return '';
    var s = value.trim().toLowerCase();
    // Drop quality / resolution tokens.
    s = s.replaceAll(_qualityTokens, ' ');
    // Drop punctuation that the repo never uses.
    s = s.replaceAll(_punct, ' ');
    // Underscores treated like spaces.
    s = s.replaceAll('_', ' ');
    // Collapse whitespace runs to a single hyphen.
    s = s.replaceAll(_spaces, '-');
    // Squash duplicate hyphens.
    s = s.replaceAll(_multiDash, '-');
    // Trim leading / trailing dashes.
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return s;
  }
}
