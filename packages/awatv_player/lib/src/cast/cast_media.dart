import 'package:flutter/foundation.dart';

/// Describes a single media payload to send to a cast receiver.
///
/// Mirrors the receiver-side `MediaInformation` shape used by both Google
/// Cast and AVFoundation's AVPlayerItem, distilled to the fields AWAtv
/// actually needs to drive an IPTV stream end-to-end:
///
/// - [url] is the playback URL the receiver will fetch directly. For
///   Chromecast over the public internet this should already be a
///   public proxy URL (private LAN HTTP servers can't be reached from
///   the cast device anyway — see `proxify`).
/// - [headers] are passed to the receiver as `customData.headers`. The
///   receiver app interprets them as HTTP request headers when fetching
///   the manifest.
/// - [contentType] is the IANA MIME type — Chromecast requires it for
///   adaptive streaming (`application/vnd.apple.mpegurl` for HLS,
///   `application/dash+xml` for DASH, `video/mp4` for progressive,
///   `video/mp2t` for raw MPEG-TS).
/// - [streamType] tells the receiver whether to expose a scrub bar.
@immutable
class CastMedia {
  const CastMedia({
    required this.url,
    this.title,
    this.subtitle,
    this.artworkUrl,
    this.headers,
    this.contentType,
    this.streamType = CastStreamType.buffered,
    this.startPosition = Duration.zero,
  });

  /// Playable URL — must be reachable from the receiver device.
  final String url;

  /// Display title shown on the TV.
  final String? title;

  /// Optional secondary line (channel group, episode label, …).
  final String? subtitle;

  /// Optional artwork URL (poster, channel logo).
  final String? artworkUrl;

  /// Optional HTTP headers the receiver should attach when fetching [url].
  final Map<String, String>? headers;

  /// IANA MIME type of the stream. Defaults inferred from the URL extension
  /// when null — see [resolvedContentType].
  final String? contentType;

  /// Live vs VOD signal for the receiver chrome.
  final CastStreamType streamType;

  /// Where the receiver should start playback. Useful when handing off
  /// from the local player so the user doesn't re-watch the intro.
  final Duration startPosition;

  /// Resolves [contentType] from the URL when not explicitly set.
  ///
  /// Falls back to `application/octet-stream` for unknown extensions so
  /// the receiver still attempts playback (some Chromecast devices accept
  /// the generic type for raw TS). Real receivers usually need the
  /// specific type, so callers should pass [contentType] when known.
  String get resolvedContentType {
    final c = contentType;
    if (c != null && c.isNotEmpty) return c;
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.mp4')) return 'video/mp4';
    if (lower.contains('.mkv')) return 'video/x-matroska';
    if (lower.contains('.webm')) return 'video/webm';
    if (lower.contains('.ts')) return 'video/mp2t';
    return 'application/octet-stream';
  }

  /// Encodes this descriptor into a primitive map suitable for crossing
  /// the platform-channel boundary in either direction.
  ///
  /// Native plugins use this to drive `GCKMediaInformation` /
  /// `MPNowPlayingInfoCenter` / similar without having to know about the
  /// Dart class shape.
  Map<String, Object?> toChannelMap() => <String, Object?>{
        'url': url,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
        'headers': headers,
        'contentType': resolvedContentType,
        'streamType': streamType.channelValue,
        'startPositionMs': startPosition.inMilliseconds,
      };
}

/// Live vs VOD signal for the receiver. Maps to GCKMediaStreamType on iOS
/// / Android and to AVPlayerItem.duration semantics on AirPlay.
enum CastStreamType {
  /// VOD with a known duration and seekable timeline.
  buffered,

  /// Live broadcast — no seek bar.
  live,

  /// Generic stream where the type isn't known yet. The receiver picks
  /// based on whether the manifest reports a duration.
  unknown,
}

extension CastStreamTypeChannel on CastStreamType {
  String get channelValue => switch (this) {
        CastStreamType.buffered => 'BUFFERED',
        CastStreamType.live => 'LIVE',
        CastStreamType.unknown => 'NONE',
      };
}
