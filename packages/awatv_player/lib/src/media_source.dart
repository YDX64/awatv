import 'package:awatv_player/awatv_player.dart' show AwaPlayerController;
import 'package:awatv_player/src/awa_player_controller.dart' show AwaPlayerController;

/// Describes a single playable media resource for [AwaPlayerController].
///
/// Includes the playback URL plus the metadata required to honour servers
/// that gate streams behind custom headers, user-agent strings, or referer
/// checks (very common with IPTV providers and Xtream Codes endpoints).
class MediaSource {
  /// Creates a media source.
  ///
  /// [url] must be a fully-qualified, network- or file-scheme URI that
  /// libmpv can open (http, https, rtmp, rtsp, file, asset, ...).
  const MediaSource({
    required this.url,
    this.headers,
    this.userAgent,
    this.referer,
    this.title,
    this.subtitleUrl,
  });

  /// The playable URL.
  final String url;

  /// Optional HTTP headers passed verbatim to the underlying transport.
  final Map<String, String>? headers;

  /// Optional `User-Agent` string. media_kit accepts this only via header,
  /// so the controller will fold it into the headers map at open time.
  final String? userAgent;

  /// Optional `Referer` value, common requirement for hot-linked streams.
  final String? referer;

  /// Optional human-readable title (used as window/notification title on
  /// platforms where libmpv exposes one).
  final String? title;

  /// Optional sidecar subtitle URL (SRT, VTT, ASS). Loaded after `open()`.
  final String? subtitleUrl;

  /// True if the URL looks like an HLS playlist (`.m3u8`).
  bool get isHls => url.toLowerCase().contains('.m3u8');

  /// True if the URL looks like a DASH manifest (`.mpd`).
  bool get isDash => url.toLowerCase().contains('.mpd');
}
