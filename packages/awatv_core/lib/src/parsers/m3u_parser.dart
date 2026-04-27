import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';

/// Parser for M3U / M3U8 IPTV playlists.
///
/// Handles real-world quirks:
/// - `#EXTM3U` header (optional in some sources)
/// - `#EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="..."` attributes
/// - `#EXTGRP:Group/Sub` legacy group declarations
/// - `#EXTVLCOPT:http-user-agent=...` per-channel HTTP options
/// - `#KODIPROP:...` Kodi extensions (captured as extras)
/// - blank lines, comments, malformed entries (skipped with a warn)
abstract class M3uParser {
  M3uParser._();

  static final AwatvLogger _log = AwatvLogger(tag: 'M3uParser');

  /// Parse an entire M3U body into a list of [Channel]s.
  ///
  /// [sourceId] is the parent [PlaylistSource.id] used to compose stable
  /// channel ids and link channels back to their playlist.
  ///
  /// Returns an empty list on completely empty input. Throws
  /// [PlaylistParseException] only if the body is non-empty but has zero
  /// recognizable entries AND zero EXTINF lines (i.e. obviously not an M3U).
  static List<Channel> parse(String body, String sourceId) {
    if (body.trim().isEmpty) return const <Channel>[];

    final lines = body.split(RegExp('\r\n|\r|\n'));
    final result = <Channel>[];

    var sawExtinf = false;
    _PendingChannel? pending;
    var lineNumber = 0;

    for (final raw in lines) {
      lineNumber++;
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        // Some sources put url-tvg or x-tvg-url here; ignored at channel level.
        continue;
      }

      if (line.startsWith('#EXTINF')) {
        sawExtinf = true;
        try {
          pending = _parseExtinf(line);
        } on FormatException catch (e) {
          _log.warn('skipping malformed EXTINF line $lineNumber: ${e.message}');
          pending = null;
        }
        continue;
      }

      if (line.startsWith('#EXTGRP:')) {
        final group = line.substring('#EXTGRP:'.length).trim();
        if (pending != null && group.isNotEmpty) {
          pending.groups.addAll(_splitGroups(group));
        }
        continue;
      }

      if (line.startsWith('#EXTVLCOPT:')) {
        final kv = line.substring('#EXTVLCOPT:'.length).trim();
        final eq = kv.indexOf('=');
        if (eq > 0 && pending != null) {
          final k = kv.substring(0, eq).trim();
          final v = kv.substring(eq + 1).trim();
          pending.extras[k] = v;
        }
        continue;
      }

      if (line.startsWith('#KODIPROP:')) {
        final kv = line.substring('#KODIPROP:'.length).trim();
        final eq = kv.indexOf('=');
        if (eq > 0 && pending != null) {
          pending.extras['kodi.${kv.substring(0, eq).trim()}'] =
              kv.substring(eq + 1).trim();
        }
        continue;
      }

      if (line.startsWith('#')) {
        // Unknown directive — ignore silently.
        continue;
      }

      // Non-comment line is the URL for the most recent EXTINF.
      if (pending == null) {
        // Bare URL with no EXTINF: tolerate it as a minimal channel.
        final ch = _channelFromBareUrl(line, sourceId);
        if (ch != null) result.add(ch);
        continue;
      }

      final channel = pending.toChannel(sourceId, line);
      if (channel != null) {
        result.add(channel);
      } else {
        _log.warn(
          'skipping line $lineNumber: empty/invalid URL after EXTINF',
        );
      }
      pending = null;
    }

    if (result.isEmpty && !sawExtinf) {
      throw PlaylistParseException(
        'No #EXTINF entries and no playable URLs found',
      );
    }

    return List.unmodifiable(result);
  }

  static Channel? _channelFromBareUrl(String url, String sourceId) {
    if (!_looksLikeUrl(url)) return null;
    final name = _filenameFromUrl(url);
    return Channel(
      id: Channel.buildId(sourceId: sourceId, name: name),
      sourceId: sourceId,
      name: name,
      streamUrl: url,
      kind: ChannelKind.live,
    );
  }

  static _PendingChannel _parseExtinf(String line) {
    // Format: #EXTINF:DURATION [attr="value" ...],TITLE
    final body = line.substring(line.indexOf(':') + 1);
    final commaIdx = _findTopLevelComma(body);
    if (commaIdx < 0) {
      throw const FormatException('EXTINF missing comma before title');
    }
    final head = body.substring(0, commaIdx);
    final title = body.substring(commaIdx + 1).trim();

    if (title.isEmpty) {
      throw const FormatException('EXTINF empty title');
    }

    final attrs = _parseAttrs(head);
    final groups = <String>[];
    final groupTitle = attrs['group-title'];
    if (groupTitle != null && groupTitle.isNotEmpty) {
      groups.addAll(_splitGroups(groupTitle));
    }

    return _PendingChannel(
      title: title,
      tvgId: attrs['tvg-id'],
      logoUrl: attrs['tvg-logo'] ?? attrs['logo'],
      groups: groups,
      extras: <String, String>{
        for (final entry in attrs.entries)
          if (!_consumedAttrs.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static const Set<String> _consumedAttrs = {
    'tvg-id',
    'tvg-logo',
    'tvg-name',
    'logo',
    'group-title',
  };

  /// Split `head` (everything after `#EXTINF:` and before the comma) into
  /// `key="value"` pairs. The leading duration token is skipped.
  static Map<String, String> _parseAttrs(String head) {
    final out = <String, String>{};
    var i = 0;
    final len = head.length;

    // Skip duration (first whitespace-separated token).
    while (i < len && head[i] != ' ' && head[i] != '\t') {
      i++;
    }

    while (i < len) {
      // Skip whitespace.
      while (i < len && (head[i] == ' ' || head[i] == '\t')) {
        i++;
      }
      if (i >= len) break;

      // Read key up to '='.
      final keyStart = i;
      while (i < len && head[i] != '=' && head[i] != ' ' && head[i] != '\t') {
        i++;
      }
      if (i >= len || head[i] != '=') break;
      final key = head.substring(keyStart, i);
      i++; // skip '='

      String value;
      if (i < len && head[i] == '"') {
        i++; // skip opening quote
        final valStart = i;
        while (i < len && head[i] != '"') {
          i++;
        }
        value = head.substring(valStart, i);
        if (i < len) i++; // skip closing quote
      } else {
        final valStart = i;
        while (i < len && head[i] != ' ' && head[i] != '\t') {
          i++;
        }
        value = head.substring(valStart, i);
      }

      if (key.isNotEmpty) out[key] = value;
    }

    return out;
  }

  /// Find the first top-level comma — i.e. one not inside double quotes —
  /// because attribute values can themselves contain commas.
  static int _findTopLevelComma(String s) {
    var inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) return i;
    }
    return -1;
  }

  static List<String> _splitGroups(String raw) {
    return raw
        .split(RegExp(r'[/;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static bool _looksLikeUrl(String s) {
    final lc = s.toLowerCase();
    return lc.startsWith('http://') ||
        lc.startsWith('https://') ||
        lc.startsWith('rtmp://') ||
        lc.startsWith('rtsp://') ||
        lc.startsWith('udp://') ||
        lc.startsWith('rtp://');
  }

  static String _filenameFromUrl(String url) {
    final qIdx = url.indexOf('?');
    final path = qIdx < 0 ? url : url.substring(0, qIdx);
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    return name.isEmpty ? url : name;
  }
}

class _PendingChannel {
  _PendingChannel({
    required this.title,
    required this.groups,
    required this.extras,
    this.tvgId,
    this.logoUrl,
  });

  final String title;
  final String? tvgId;
  final String? logoUrl;
  final List<String> groups;
  final Map<String, String> extras;

  Channel? toChannel(String sourceId, String url) {
    if (url.isEmpty) return null;
    if (!M3uParser._looksLikeUrl(url)) return null;

    return Channel(
      id: Channel.buildId(
        sourceId: sourceId,
        tvgId: tvgId,
        name: title,
      ),
      sourceId: sourceId,
      name: title,
      tvgId: (tvgId == null || tvgId!.isEmpty) ? null : tvgId,
      logoUrl: (logoUrl == null || logoUrl!.isEmpty) ? null : logoUrl,
      streamUrl: url,
      groups: List.unmodifiable(groups),
      kind: _inferKind(url, groups),
      extras: Map.unmodifiable(extras),
    );
  }

  ChannelKind _inferKind(String url, List<String> groups) {
    final lcGroups = groups.map((g) => g.toLowerCase()).toList();
    final lcUrl = url.toLowerCase();
    if (lcGroups.any((g) => g.contains('vod') || g.contains('movie'))) {
      return ChannelKind.vod;
    }
    if (lcGroups.any((g) => g.contains('series'))) {
      return ChannelKind.series;
    }
    if (lcUrl.contains('/movie/')) return ChannelKind.vod;
    if (lcUrl.contains('/series/')) return ChannelKind.series;
    return ChannelKind.live;
  }
}

