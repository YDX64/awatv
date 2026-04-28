/// Builds an ordered list of plausible URL shapes for the same logical
/// IPTV/VOD/series stream.
///
/// Different Xtream Codes panels (and the same panel under different
/// load conditions) hand out the same content under multiple shapes:
///
///   - The original URL the panel reported (`.ts`, `.m3u8`, no extension).
///   - `/live/` prefixed paths (some forks gate live behind that segment
///     while others omit it entirely).
///   - Container swaps — a `.ts` URL often has an `.m3u8` twin that the
///     panel will gladly serve, and vice versa.
///
/// On web, raw MPEG-TS won't play in the `<video>` element without a
/// polyfill, so HLS is strongly preferred — the variant order biases
/// `.m3u8` to the front when starting from `.ts`. On native (libmpv via
/// media_kit) both work, but a stalled `.ts` open frequently succeeds
/// when retried as `.m3u8` (the panel transcodes on demand).
///
/// The first entry in the returned list is always [url] verbatim. Order
/// matters: callers feed the list into a fallback chain and try each in
/// turn until one starts playing.
List<String> streamUrlVariants(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return const <String>[];

  final out = <String>[trimmed];

  // We only mutate http(s) URLs; file/asset URIs go through unchanged.
  final lower = trimmed.toLowerCase();
  if (!(lower.startsWith('http://') || lower.startsWith('https://'))) {
    return out;
  }

  Uri parsed;
  try {
    parsed = Uri.parse(trimmed);
  } on FormatException {
    return out;
  }

  final ext = _extensionOf(parsed.path).toLowerCase();
  final hasLivePrefix = parsed.path.startsWith('/live/');

  void add(String candidate) {
    if (!out.contains(candidate)) out.add(candidate);
  }

  if (ext == 'ts') {
    // Web cannot play raw MPEG-TS; HLS twin first.
    add(_swapExtension(parsed, 'm3u8'));
    if (!hasLivePrefix) {
      final live = _insertLivePrefix(parsed);
      add(live.toString());
      add(_swapExtension(live, 'm3u8'));
    }
  } else if (ext == 'm3u8') {
    // Some panels reject HLS for clients without the right user agent —
    // a `.ts` retry sometimes recovers playback on libmpv.
    add(_swapExtension(parsed, 'ts'));
    if (!hasLivePrefix) {
      add(_insertLivePrefix(parsed).toString());
    }
  } else if (ext.isEmpty) {
    add('$trimmed.m3u8');
    add('$trimmed.ts');
  }

  return out;
}

String _extensionOf(String path) {
  final slash = path.lastIndexOf('/');
  final tail = slash < 0 ? path : path.substring(slash + 1);
  final dot = tail.lastIndexOf('.');
  if (dot < 0) return '';
  return tail.substring(dot + 1);
}

String _swapExtension(Uri uri, String newExt) {
  final path = uri.path;
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (dot <= slash) {
    // No extension to swap; append.
    return uri.replace(path: '$path.$newExt').toString();
  }
  return uri.replace(path: '${path.substring(0, dot + 1)}$newExt').toString();
}

Uri _insertLivePrefix(Uri uri) {
  // `/u/p/123.ts` → `/live/u/p/123.ts`. Idempotent guard already done at
  // the call-site but we re-check defensively.
  if (uri.path.startsWith('/live/')) return uri;
  return uri.replace(path: '/live${uri.path}');
}
