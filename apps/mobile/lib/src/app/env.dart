import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Strongly-typed accessor over `flutter_dotenv` so the rest of the app
/// never reads raw env strings.
///
/// `Env.load()` is delegated to `dotenv.load()` in `main.dart` — this class
/// only exposes the keys we care about, with sensible empty-string fallbacks
/// so the app boots even when the developer hasn't filled in `.env` yet.
class Env {
  const Env._();

  /// TMDB v3 API key. Empty when the developer has not configured one — the
  /// MetadataService should detect the empty string and degrade gracefully
  /// (no posters / backdrops, but the app still works).
  static String get tmdbApiKey => _read('TMDB_API_KEY');

  /// OpenSubtitles REST API v1 key (free tier). Required to power the
  /// "OpenSubtitles" section in the player track picker. Empty means the
  /// section degrades to a polite "configure key" notice; embedded
  /// subtitle tracks and the local-file picker keep working.
  static String get openSubtitlesKey => _read('OPENSUBTITLES_API_KEY');

  /// True when the user has configured an OpenSubtitles key — the player
  /// track picker uses this to hide the OpenSubtitles section entirely
  /// when nothing can ever come back.
  static bool get hasOpenSubtitles => openSubtitlesKey.isNotEmpty;

  // --- AdMob ---------------------------------------------------------------
  static String get admobAppIdIos => _read('ADMOB_APP_ID_IOS');
  static String get admobAppIdAndroid => _read('ADMOB_APP_ID_ANDROID');
  static String get admobBannerIos => _read('ADMOB_BANNER_IOS');
  static String get admobBannerAndroid => _read('ADMOB_BANNER_ANDROID');
  static String get admobInterstitialIos => _read('ADMOB_INTERSTITIAL_IOS');
  static String get admobInterstitialAndroid =>
      _read('ADMOB_INTERSTITIAL_ANDROID');

  // --- RevenueCat ----------------------------------------------------------
  static String get revenueCatKeyIos => _read('REVENUECAT_API_KEY_IOS');
  static String get revenueCatKeyAndroid => _read('REVENUECAT_API_KEY_ANDROID');

  // --- Backend (Supabase) --------------------------------------------------
  static String get supabaseUrl => _read('SUPABASE_URL');
  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  // --- Web proxy (CORS + HTTPS + HLS rewrite) -----------------------------
  /// On web the browser blocks mixed-content (HTTPS page → HTTP server) and
  /// most IPTV panels don't return CORS headers. We tunnel every outbound
  /// request through a Cloudflare Worker that adds the headers and rewrites
  /// HLS segment URIs. Compile-time default falls back to the public Worker;
  /// override per-environment via `.env`.
  static String get webProxyUrl => _read('WEB_PROXY_URL').isNotEmpty
      ? _read('WEB_PROXY_URL')
      : 'https://awa-proxy.awadigitalinteractive.workers.dev';

  /// True when the user has configured a TMDB key — features that depend on
  /// it (poster lookup, trailers, …) can early-out otherwise.
  static bool get hasTmdb => tmdbApiKey.isNotEmpty;

  /// True when both Supabase URL and anon key are configured. Auth and
  /// cloud-sync features key off this — when false the auth controller
  /// permanently emits guest, the login screen surfaces a "not configured"
  /// banner, and cloud-sync gates stay locked.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // -------------------------------------------------------------------------
  static String _read(String key) {
    // `dotenv.maybeGet` returns null when the key is missing; we treat that
    // identically to an empty string so callers only have one branch.
    return dotenv.maybeGet(key) ?? '';
  }
}
