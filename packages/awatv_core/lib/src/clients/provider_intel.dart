// IPTV provider intelligence layer.
//
// Different IPTV panels (forks of Xtream Codes, custom OTT setups,
// resellers, …) reject identical streams under subtle differences:
//
//   - some 401/456 unless the User-Agent matches a native player string
//   - some require a `/live/` path prefix that the original Xtream omits
//   - some prefer `.ts` over `.m3u8` (or vice versa) for the same stream
//   - some return 403 unless a `Referer:` header matches the panel host
//   - some IP-block all datacenter ranges, giving 456 / 403 to Cloudflare
//   - VOD/series paths can be `/movie/` vs `/play/movie/` vs custom roots
//
// Rather than blast every channel through the same generic fallback chain
// we keep a small registry of fingerprints, one per panel family, and the
// recipes for crafting URLs / headers that we know work. When a host
// matches a fingerprint we surface the right candidates (in order); when
// it doesn't, we fall back to the generic [genericVariants] chain that
// `streamUrlVariants` already produces.
//
// This file is pure Dart — no Flutter, no media_kit. The mobile/web
// players consume `applyTo` to expand a single URL into a list of
// `StreamCandidate`s (URL + headers) and feed them to
// `MediaSource.variants(...)` or whatever transport they prefer.

import 'package:meta/meta.dart';

/// Maximum number of URL candidates produced per call site.
///
/// Six is enough to cover the realistic permutations (`.ts` vs `.m3u8`,
/// `/live/` prefix, alternate VOD root) without spamming the player with
/// 20+ failed opens before declaring a dead stream.
const int _maxCandidates = 6;

/// What kind of stream we're resolving. Drives which template list is
/// consulted (live vs VOD vs series episode).
enum StreamKind {
  /// 24/7 channel — `/live/` path or bare `/{user}/{pass}/{id}.{ext}`.
  live,

  /// On-demand movie — typically rooted under `/movie/`.
  vod,

  /// Series episode — typically rooted under `/series/`.
  series,
}

/// Output of [ProviderFingerprint.applyTo]: a single URL + headers tuple
/// the player should try.
///
/// Pure Dart record-style class so callers in `awatv_player` /
/// `apps/mobile` can convert each into their own `MediaSource` without
/// `awatv_core` importing `awatv_player` (would be a dependency cycle).
@immutable
final class StreamCandidate {
  /// Builds a candidate. [headers] is treated as immutable by callers.
  const StreamCandidate({
    required this.url,
    this.headers = const <String, String>{},
    this.userAgent,
    this.referer,
  });

  /// Resolved playback URL (no further variant expansion needed).
  final String url;

  /// HTTP headers the player should set on the request.
  ///
  /// Always non-null (defaulting to the empty map) so callers can spread
  /// safely without null-checks.
  final Map<String, String> headers;

  /// Convenience: the User-Agent header value (also present in [headers]).
  final String? userAgent;

  /// Convenience: the Referer header value (also present in [headers]).
  final String? referer;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StreamCandidate &&
        other.url == url &&
        other.userAgent == userAgent &&
        other.referer == referer &&
        _mapEquals(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(url, userAgent, referer, headers.length);

  @override
  String toString() => 'StreamCandidate($url, ua=$userAgent, ref=$referer)';
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// One known panel family. Patterns are matched against the URL host (a
/// `host` like `cdn-12.worldiptv.me` matches `worldiptv.me` because of
/// `host.endsWith(suffix)`).
///
/// Templates use `{server}/{user}/{pass}/{id}.{ext}` placeholders. The
/// list is tried top-down by [applyTo] and the first N (capped by
/// [_maxCandidates]) become candidates.
@immutable
final class ProviderFingerprint {
  const ProviderFingerprint({
    required this.id,
    required this.label,
    required this.hostPatterns,
    this.userAgents = const <String>['VLC/3.0.20 LibVLC/3.0.20'],
    this.liveUrlTemplates = const <String>[
      '{server}/{user}/{pass}/{id}.{ext}',
      '{server}/live/{user}/{pass}/{id}.{ext}',
    ],
    this.vodUrlTemplates = const <String>[
      '{server}/movie/{user}/{pass}/{id}.{ext}',
    ],
    this.seriesUrlTemplates = const <String>[
      '{server}/series/{user}/{pass}/{id}.{ext}',
    ],
    this.preferredExtensions = const <String>['m3u8', 'ts'],
    this.timeout = const Duration(seconds: 10),
    this.needsRefererHeader = false,
    this.defaultReferer,
    this.ipLockedToResidential = false,
    this.notes = const <String>[],
  });

  /// Stable identifier for logging / diagnostics.
  final String id;

  /// Human-readable label for the UI / logs.
  final String label;

  /// Host suffixes (or full hostnames) this fingerprint matches.
  ///
  /// Matched via `host == suffix || host.endsWith('.$suffix')`. The empty
  /// string is reserved for [genericFingerprint] (default fallback) and
  /// is treated as a wildcard that matches everything.
  final List<String> hostPatterns;

  /// User-Agent strings to try in order. The first is used by default;
  /// the rest are for fallback retries when the first is rejected with
  /// 401/403/456.
  final List<String> userAgents;

  /// URL templates for live channels.
  final List<String> liveUrlTemplates;

  /// URL templates for VOD movies.
  final List<String> vodUrlTemplates;

  /// URL templates for series episodes.
  final List<String> seriesUrlTemplates;

  /// Extensions to try for live streams, in preference order.
  final List<String> preferredExtensions;

  /// Per-request timeout. Some panels are slow on first byte but stable
  /// once flowing, so we allow per-fingerprint tuning rather than a
  /// global default that punishes the slow-but-honest providers.
  final Duration timeout;

  /// True when the panel checks the `Referer` header and 403s without it.
  final bool needsRefererHeader;

  /// Default Referer when [needsRefererHeader] is set. When null we fall
  /// back to `{scheme}://{host}/`.
  final String? defaultReferer;

  /// True when the panel rejects datacenter IP ranges (Cloudflare,
  /// AWS, Hetzner) with 403/456. Surfacing this so the UI can warn the
  /// user that the stream is unlikely to play through the web proxy.
  final bool ipLockedToResidential;

  /// Free-form notes — used as `///` doc strings in the registry below.
  final List<String> notes;

  /// True iff this fingerprint should match the supplied host. The
  /// generic catch-all (empty pattern) always returns true.
  bool matchesHost(String host) {
    final h = host.toLowerCase();
    for (final pattern in hostPatterns) {
      if (pattern.isEmpty) return true; // generic catch-all
      final p = pattern.toLowerCase();
      if (h == p || h.endsWith('.$p')) return true;
    }
    return false;
  }

  /// Selects the right template list for [kind].
  List<String> templatesFor(StreamKind kind) {
    switch (kind) {
      case StreamKind.live:
        return liveUrlTemplates;
      case StreamKind.vod:
        return vodUrlTemplates;
      case StreamKind.series:
        return seriesUrlTemplates;
    }
  }

  /// Renders [template] into a concrete URL.
  ///
  /// Substitutes `{server}`, `{user}`, `{pass}`, `{id}`, `{ext}`. The
  /// caller is responsible for URL-encoding `user` / `pass` if they
  /// contain reserved characters — the registry recipes don't, but a
  /// bad-faith panel might issue a credential like `pass=foo bar`.
  String render({
    required String template,
    required String server,
    required String user,
    required String pass,
    required String id,
    required String ext,
  }) {
    final s = server.endsWith('/')
        ? server.substring(0, server.length - 1)
        : server;
    return template
        .replaceAll('{server}', s)
        .replaceAll('{user}', user)
        .replaceAll('{pass}', pass)
        .replaceAll('{id}', id)
        .replaceAll('{ext}', ext);
  }

  /// Expands a known stream URL into an ordered list of [StreamCandidate]s.
  ///
  /// [originalUrl] is the URL the panel/M3U gave us. We try to keep it
  /// at the head of the list (with this fingerprint's headers attached)
  /// and follow with the recipe-based variants:
  ///
  ///   1. swap extension to each `preferredExtensions` entry
  ///   2. add `/live/` prefix when missing (and remove when present)
  ///
  /// If [parsed] cannot be parsed (file URI, malformed URL) we return a
  /// single candidate with the original URL and the fingerprint's headers
  /// — still useful because the headers may unblock the request.
  List<StreamCandidate> applyTo(String originalUrl) {
    final trimmed = originalUrl.trim();
    if (trimmed.isEmpty) return const <StreamCandidate>[];

    final ua = userAgents.isEmpty ? null : userAgents.first;
    final ref = needsRefererHeader ? (defaultReferer ?? _defaultRefererFor(trimmed)) : null;

    Map<String, String> buildHeaders() {
      final h = <String, String>{};
      if (ua != null) h['User-Agent'] = ua;
      if (ref != null) h['Referer'] = ref;
      return h;
    }

    final lower = trimmed.toLowerCase();
    if (!(lower.startsWith('http://') || lower.startsWith('https://'))) {
      return <StreamCandidate>[
        StreamCandidate(
          url: trimmed,
          headers: buildHeaders(),
          userAgent: ua,
          referer: ref,
        ),
      ];
    }

    Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } on FormatException {
      return <StreamCandidate>[
        StreamCandidate(
          url: trimmed,
          headers: buildHeaders(),
          userAgent: ua,
          referer: ref,
        ),
      ];
    }

    final urls = <String>[];
    void addUrl(String u) {
      if (u.isEmpty) return;
      if (urls.contains(u)) return;
      urls.add(u);
    }

    // Always honour the original URL first — the panel just gave it to
    // us, so it has the highest probability of working. The candidate
    // list adds the recipe-based variants to cover the cases where the
    // original was wrong (cached URL after a panel update, etc.).
    addUrl(trimmed);

    final ext = _extensionOf(parsed.path).toLowerCase();
    final hasLivePrefix = parsed.path.startsWith('/live/');

    // Extension swaps — bias toward the fingerprint's preferred order
    // (e.g. some panels work only with .m3u8, others only with .ts).
    if (ext.isNotEmpty) {
      for (final candidateExt in preferredExtensions) {
        if (candidateExt == ext) continue;
        addUrl(_swapExtension(parsed, candidateExt));
      }
    }

    // /live/ prefix variants. Many forks omit the prefix; many require
    // it. Cheap to try both unconditionally.
    if (!hasLivePrefix) {
      final live = _insertLivePrefix(parsed);
      addUrl(live.toString());
      // Combined: /live/ + alt-ext.
      for (final candidateExt in preferredExtensions) {
        if (candidateExt == ext) continue;
        addUrl(_swapExtension(live, candidateExt));
      }
    } else {
      // Already has /live/ — surface a sibling without the prefix in
      // case the panel actually rejects it (rare but observed).
      final stripped = parsed.replace(
        path: parsed.path.substring('/live'.length),
      );
      addUrl(stripped.toString());
    }

    // Bare URL with no extension — append the preferred ones. Common
    // for older panels that infer container from the user agent.
    if (ext.isEmpty) {
      for (final candidateExt in preferredExtensions) {
        addUrl('$trimmed.$candidateExt');
      }
    }

    final headers = buildHeaders();
    final out = <StreamCandidate>[];
    for (final u in urls) {
      out.add(StreamCandidate(
        url: u,
        headers: headers,
        userAgent: ua,
        referer: ref,
      ));
      if (out.length >= _maxCandidates) break;
    }
    return List.unmodifiable(out);
  }

  /// `{scheme}://{host}/` from any URL — used as default Referer when
  /// the fingerprint demands one but doesn't override [defaultReferer].
  static String _defaultRefererFor(String url) {
    try {
      final u = Uri.parse(url);
      return '${u.scheme}://${u.host}/';
    } on FormatException {
      return '';
    }
  }

  static String _extensionOf(String path) {
    final slash = path.lastIndexOf('/');
    final tail = slash < 0 ? path : path.substring(slash + 1);
    final dot = tail.lastIndexOf('.');
    if (dot < 0) return '';
    return tail.substring(dot + 1);
  }

  static String _swapExtension(Uri uri, String newExt) {
    final path = uri.path;
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    if (dot <= slash) {
      return uri.replace(path: '$path.$newExt').toString();
    }
    return uri.replace(path: '${path.substring(0, dot + 1)}$newExt').toString();
  }

  static Uri _insertLivePrefix(Uri uri) {
    if (uri.path.startsWith('/live/')) return uri;
    return uri.replace(path: '/live${uri.path}');
  }
}

/// The catch-all fingerprint used when no host pattern matches.
///
/// Mirrors the historical generic Xtream layout: `.ts` first, both with
/// and without the `/live/` prefix, default VLC user agent, no referer.
const ProviderFingerprint genericFingerprint = ProviderFingerprint(
  id: 'generic-xtream',
  label: 'Generic Xtream Codes',
  // Empty pattern == wildcard catch-all.
  hostPatterns: <String>[''],
  notes: <String>[
    'Default fingerprint for unknown hosts.',
    'Matches the historical streamUrlVariants() fallback chain.',
  ],
);

/// The static registry, ordered most-specific-first. [ProviderIntel.match]
/// walks this list and returns the first hit; the catch-all
/// [genericFingerprint] is always available as the final fallback.
///
/// All entries are based on real-world panel software fingerprints I or
/// the user have observed in the field. Each carries a `///`-style note
/// in [ProviderFingerprint.notes] explaining WHY it's here.
const List<ProviderFingerprint> _builtInFingerprints = <ProviderFingerprint>[
  // ---------------------------------------------------------------------
  // worldiptv.me — the user's headline complaint. Returns 456 for any
  // datacenter IP (Cloudflare, AWS, Hetzner). Live URLs use /live/
  // prefix and prefer .m3u8. VLC UA is mandatory; browser UAs get 403.
  ProviderFingerprint(
    id: 'worldiptv',
    label: 'WorldIPTV',
    hostPatterns: <String>['worldiptv.me', 'worldiptv.live', 'worldiptv.tv'],
    userAgents: <String>[
      'VLC/3.0.20 LibVLC/3.0.20',
      'IPTVSmarters',
      'TiviMate/4.7.0',
    ],
    liveUrlTemplates: <String>[
      '{server}/live/{user}/{pass}/{id}.{ext}',
      '{server}/{user}/{pass}/{id}.{ext}',
    ],
    preferredExtensions: <String>['m3u8', 'ts'],
    needsRefererHeader: true,
    ipLockedToResidential: true,
    notes: <String>[
      'Datacenter IPs get 456. The Cloudflare worker proxy will likely',
      'be blocked — surface ipLockedToResidential to warn the user.',
      'Requires /live/ prefix and Referer matching the panel host.',
      'Browser User-Agents (Chrome/Firefox) are rejected with 403.',
    ],
  ),

  // ---------------------------------------------------------------------
  // Original Xtream Codes panel software. Defunct upstream (sold
  // 2018, raided 2019), but thousands of clones still ship the same
  // routes. Live URL is `{server}/{user}/{pass}/{id}.ts`, NO /live/
  // prefix; older versions only serve .ts (transcoder for .m3u8 was
  // a separate paid plugin).
  ProviderFingerprint(
    id: 'xtream-codes-original',
    label: 'Xtream Codes (legacy)',
    hostPatterns: <String>['xtreamcodes.com', 'xtream-codes.com'],
    userAgents: <String>[
      'VLC/3.0.20 LibVLC/3.0.20',
      'Lavf/58.76.100',
    ],
    liveUrlTemplates: <String>[
      '{server}/{user}/{pass}/{id}.{ext}',
    ],
    preferredExtensions: <String>['ts', 'm3u8'],
    notes: <String>[
      'No /live/ prefix on the original panel.',
      '.ts first because the m3u8 transcoder is a paid add-on that',
      'most pirate clones never installed.',
    ],
  ),

  // ---------------------------------------------------------------------
  // IPTVMate / similar /play/ rooted panels. Common with newer
  // resellers built on Node.js / NestJS rewrites of the Xtream API.
  // They like .m3u8 and serve via a /play/live/ root with a token.
  ProviderFingerprint(
    id: 'iptvmate-style',
    label: 'IPTVMate / OTT Mate (token-rooted)',
    hostPatterns: <String>['iptvmate.io', 'iptvmate.app', 'ottmate.tv'],
    liveUrlTemplates: <String>[
      '{server}/play/live/{user}/{pass}/{id}.{ext}',
      '{server}/live/{user}/{pass}/{id}.{ext}',
      '{server}/{user}/{pass}/{id}.{ext}',
    ],
    vodUrlTemplates: <String>[
      '{server}/play/movie/{user}/{pass}/{id}.{ext}',
      '{server}/movie/{user}/{pass}/{id}.{ext}',
    ],
    seriesUrlTemplates: <String>[
      '{server}/play/series/{user}/{pass}/{id}.{ext}',
      '{server}/series/{user}/{pass}/{id}.{ext}',
    ],
    preferredExtensions: <String>['m3u8', 'ts'],
    notes: <String>[
      'Routes use a /play/ prefix on top of the standard Xtream layout.',
      '.m3u8 is the only supported container for live; .ts returns 404.',
    ],
  ),

  // ---------------------------------------------------------------------
  // Sansat-style hot-link-protected panels. Reject every request that
  // lacks a Referer header pointing at the panel root. Common with
  // Turkish reseller panels and small "club" providers.
  ProviderFingerprint(
    id: 'sansat-style',
    label: 'Sansat / hot-link-protected panel',
    hostPatterns: <String>['sansat.tv', 'sansat.io', 'kralhd.tv'],
    needsRefererHeader: true,
    preferredExtensions: <String>['m3u8', 'ts'],
    notes: <String>[
      'Returns 403 unless Referer header matches the panel host.',
      'Defaults to {scheme}://{host}/ when no explicit defaultReferer.',
    ],
  ),

  // ---------------------------------------------------------------------
  // ott / iptv-stream.tv style — the "/play/" prefix is also used by
  // a few European resellers. Splitting from iptvmate because their
  // VOD root is `/movie/` not `/play/movie/`.
  ProviderFingerprint(
    id: 'ott-iptv-stream',
    label: 'OTT iptv-stream.tv',
    hostPatterns: <String>['ott.iptv-stream.tv', 'iptv-stream.tv'],
    vodUrlTemplates: <String>[
      '{server}/movie/{user}/{pass}/{id}.{ext}',
      '{server}/vod/{user}/{pass}/{id}.{ext}',
    ],
    seriesUrlTemplates: <String>[
      '{server}/series/{user}/{pass}/{id}.{ext}',
    ],
    preferredExtensions: <String>['mp4', 'mkv'],
    notes: <String>[
      'VOD streams are direct mp4/mkv — no HLS layer.',
      'preferredExtensions reflects this so live fallback chain doesn\'t',
      'try .m3u8 swaps for VOD URLs (which would 404).',
    ],
  ),

  // ---------------------------------------------------------------------
  // TivuStream-style — common in Italian / Balkan markets. Series
  // episodes use a non-standard /tv/ prefix; live and VOD follow the
  // generic Xtream layout.
  ProviderFingerprint(
    id: 'tivustream',
    label: 'TivuStream / IT-balkan flavor',
    hostPatterns: <String>['tivustream.tv', 'tivustream.live', 'tivunetwork.tv'],
    liveUrlTemplates: <String>[
      '{server}/{user}/{pass}/{id}.{ext}',
      '{server}/live/{user}/{pass}/{id}.{ext}',
    ],
    seriesUrlTemplates: <String>[
      '{server}/tv/{user}/{pass}/{id}.{ext}',
      '{server}/series/{user}/{pass}/{id}.{ext}',
    ],
    preferredExtensions: <String>['m3u8', 'ts'],
    notes: <String>[
      'Series episodes resolve under /tv/, not /series/.',
      'Live and VOD follow the original Xtream Codes layout.',
    ],
  ),

  // ---------------------------------------------------------------------
  // IPTV Smarters / Pro panels. The "Smarters" UI is just a brand —
  // the underlying panels are usually Xtream forks with adaptive
  // bitrate enabled. They're tolerant of both UA and prefix; we keep
  // a defensive recipe with both shapes and a Smarters UA.
  ProviderFingerprint(
    id: 'smarters-pro',
    label: 'IPTV Smarters Pro panels',
    hostPatterns: <String>['smarters.pro', 'iptvsmarters.com'],
    userAgents: <String>[
      'IPTVSmarters',
      'IPTVSmartersPro/3.1',
      'VLC/3.0.20 LibVLC/3.0.20',
    ],
    preferredExtensions: <String>['m3u8', 'ts'],
    notes: <String>[
      'Generic Smarters Pro brand. The "IPTVSmarters" UA unlocks panels',
      'that whitelist the Smarters mobile app explicitly.',
    ],
  ),

  // ---------------------------------------------------------------------
  // CDN-VIP / cdnvip.tv style — datacenter-tolerant panels, but very
  // strict about extension. They serve raw .ts only; .m3u8 returns
  // 404 because they have no HLS muxer.
  ProviderFingerprint(
    id: 'cdnvip',
    label: 'CDN VIP (.ts-only)',
    hostPatterns: <String>['cdnvip.tv', 'cdnvip.live', 'vip-cdn.tv'],
    preferredExtensions: <String>['ts'],
    liveUrlTemplates: <String>[
      '{server}/{user}/{pass}/{id}.{ext}',
      '{server}/live/{user}/{pass}/{id}.{ext}',
    ],
    notes: <String>[
      'No HLS muxer — only .ts works. Skipping .m3u8 saves a 404.',
      "On web this means the proxy is mandatory (browsers can't play",
      'raw MPEG-TS without a polyfill).',
    ],
  ),

  // ---------------------------------------------------------------------
  // Generic-but-modern HLS-first panel. Fallback for hosts that look
  // like reseller URLs (`*.cdnvip.tv`-style without specific match).
  // Listed AFTER specific entries so the more-specific patterns win.
  ProviderFingerprint(
    id: 'generic-hls',
    label: 'Generic HLS-first panel',
    hostPatterns: <String>['hlspanel.io', 'hls-iptv.tv'],
    preferredExtensions: <String>['m3u8', 'ts'],
    notes: <String>[
      "Defensive entry for HLS-first panels we haven't fingerprinted",
      'individually yet. .m3u8 leads, .ts as fallback.',
    ],
  ),
];

/// Public registry of provider fingerprints.
///
/// Stateless / pure: every method takes the host (or full URL) as input.
/// Designed to be cheap to call from hot paths (URL composition for
/// every channel in the list, etc.).
abstract final class ProviderIntel {
  ProviderIntel._();

  /// All built-in fingerprints, including the catch-all [genericFingerprint]
  /// at the tail.
  static List<ProviderFingerprint> get all => List<ProviderFingerprint>.unmodifiable(
        <ProviderFingerprint>[..._builtInFingerprints, genericFingerprint],
      );

  /// Returns the most-specific fingerprint for [host], or
  /// [genericFingerprint] when nothing matches.
  ///
  /// [host] is matched case-insensitively. Specificity comes from
  /// registry order — earlier entries win, and the catch-all always
  /// matches last.
  static ProviderFingerprint match(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return genericFingerprint;
    for (final fp in _builtInFingerprints) {
      if (fp.matchesHost(h)) return fp;
    }
    return genericFingerprint;
  }

  /// Convenience: extracts the host from [url] and runs [match].
  static ProviderFingerprint matchUrl(String url) {
    if (url.isEmpty) return genericFingerprint;
    try {
      final host = Uri.parse(url).host;
      return match(host);
    } on FormatException {
      return genericFingerprint;
    }
  }

  /// Expands [originalUrl] into an ordered list of [StreamCandidate]s
  /// using the matched fingerprint's recipe.
  ///
  /// When no fingerprint matches the host, returns the generic chain
  /// (mirrors the legacy `streamUrlVariants` behaviour).
  static List<StreamCandidate> applyTo(String originalUrl) {
    if (originalUrl.isEmpty) return const <StreamCandidate>[];
    final fp = matchUrl(originalUrl);
    return fp.applyTo(originalUrl);
  }

  /// Convenience helper for code paths that already know the username,
  /// password and stream id — used by `XtreamClient` to build live /
  /// VOD / series URLs without baking the templates into the client.
  ///
  /// Returns the FIRST template's rendered URL — callers that need the
  /// fallback chain should pair this with [applyTo] on the result.
  static String renderUrl({
    required String host,
    required StreamKind kind,
    required String server,
    required String user,
    required String pass,
    required String id,
    required String ext,
  }) {
    final fp = match(host);
    final templates = fp.templatesFor(kind);
    if (templates.isEmpty) {
      return '${server.endsWith('/') ? server.substring(0, server.length - 1) : server}'
          '/$user/$pass/$id.$ext';
    }
    return fp.render(
      template: templates.first,
      server: server,
      user: user,
      pass: pass,
      id: id,
      ext: ext,
    );
  }
}
