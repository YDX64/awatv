import 'package:flutter/foundation.dart';

/// A single IPTV-ish service surfaced by mDNS / Bonjour discovery.
///
/// Three Bonjour types are interesting to us:
///   - `_xtream._tcp` — Xtream Codes panels that explicitly advertise.
///   - `_iptv._tcp`   — generic IPTV streamers.
///   - `_http._tcp`   — fallback for routers that re-export an IPTV web UI.
///
/// We only render the first two by default; `_http._tcp` is wide-open and
/// would surface every web-enabled device on the LAN, so it's gated behind
/// the explicit `includeHttp` toggle in `LocalIptvDiscovery`.
@immutable
class DiscoveredIptvServer {
  const DiscoveredIptvServer({
    required this.name,
    required this.host,
    required this.port,
    required this.type,
    required this.attributes,
  });

  /// Human-readable service name (e.g. "Living Room Xtream").
  final String name;

  /// Resolved hostname or IP. May be `mdns.local` style on iOS, raw IPv4
  /// on Android — both work as a `Uri` host segment.
  final String host;

  /// TCP port the service is listening on.
  final int port;

  /// Bonjour service type, e.g. `_xtream._tcp`.
  final String type;

  /// TXT-record key/value pairs. Often empty; some panels expose
  /// `path=/player_api.php` here so we can prefill the URL field.
  final Map<String, String> attributes;

  /// Best-effort `http://host:port[/path]` URL for the service. Falls back
  /// to `http://host:port` when the TXT record doesn't carry a `path`.
  String get suggestedUrl {
    final scheme =
        attributes['scheme']?.toLowerCase() == 'https' ? 'https' : 'http';
    final base = '$scheme://$host:$port';
    final path = attributes['path'];
    if (path == null || path.isEmpty) return base;
    if (path.startsWith('/')) return '$base$path';
    return '$base/$path';
  }

  /// Stable identity for `found.remove(...)` lookups in the discovery loop.
  String get key => '$type|$name|$host:$port';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredIptvServer && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
