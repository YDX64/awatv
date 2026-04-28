import 'package:awatv_core/awatv_core.dart' show ProviderIntel, StreamCandidate;

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
/// Implementation now defers to [ProviderIntel] for the actual recipe:
/// when the URL host matches a known fingerprint (worldiptv.me,
/// iptvmate.io, sansat.tv, …) we use that fingerprint's preferred
/// extension order and template list. Unknown hosts fall through to
/// the generic catch-all fingerprint, which mirrors the historical
/// behaviour (`.ts` first, both `/live/` shapes).
///
/// The first entry in the returned list is always [url] verbatim. Order
/// matters: callers feed the list into a fallback chain and try each in
/// turn until one starts playing.
List<String> streamUrlVariants(String url) {
  final candidates = streamCandidates(url);
  return <String>[for (final c in candidates) c.url];
}

/// Like [streamUrlVariants] but returns the full [StreamCandidate]
/// objects so the caller can attach the per-host User-Agent / Referer
/// headers as well as the URL.
///
/// This is the preferred entry point — the `_play(...)` helpers in the
/// channels/VOD/series screens use it to fold provider-aware headers
/// into the `MediaSource` they feed to `AwaPlayerController`.
List<StreamCandidate> streamCandidates(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return const <StreamCandidate>[];
  return ProviderIntel.applyTo(trimmed);
}
