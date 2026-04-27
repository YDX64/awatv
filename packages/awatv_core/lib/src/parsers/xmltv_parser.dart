import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:xml/xml.dart';

/// Parser for XMLTV-format EPG documents.
///
/// XMLTV programme element shape (subset we use):
/// ```xml
/// <programme start="20260427060000 +0000"
///            stop="20260427070000 +0000"
///            channel="bbcone.uk">
///   <title lang="en">Breakfast</title>
///   <desc lang="en">News and weather.</desc>
///   <category lang="en">News</category>
/// </programme>
/// ```
abstract class XmltvParser {
  XmltvParser._();

  static final AwatvLogger _log = AwatvLogger(tag: 'XmltvParser');

  /// Parse an XMLTV body. Returns an empty list if there are no `<programme>`
  /// elements. Throws [PlaylistParseException] if the body is not parseable
  /// XML.
  static List<EpgProgramme> parse(String xmlBody) {
    if (xmlBody.trim().isEmpty) return const <EpgProgramme>[];

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } on XmlException catch (e) {
      throw PlaylistParseException('Invalid XMLTV: ${e.message}');
    }

    final programmes = doc.findAllElements('programme');
    final out = <EpgProgramme>[];

    for (final p in programmes) {
      final start = _parseXmltvDate(p.getAttribute('start'));
      final stop = _parseXmltvDate(p.getAttribute('stop'));
      final channel = p.getAttribute('channel') ?? '';

      if (start == null || stop == null || channel.isEmpty) {
        _log.warn('skipping programme: missing start/stop/channel');
        continue;
      }

      final title = _firstChildText(p, 'title') ?? '';
      if (title.isEmpty) {
        _log.warn('skipping programme on $channel: empty title');
        continue;
      }

      out.add(
        EpgProgramme(
          channelTvgId: channel,
          start: start,
          stop: stop,
          title: title,
          description: _firstChildText(p, 'desc'),
          category: _firstChildText(p, 'category'),
        ),
      );
    }

    return List.unmodifiable(out);
  }

  static String? _firstChildText(XmlElement parent, String name) {
    for (final c in parent.findElements(name)) {
      final t = c.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// XMLTV dates are `YYYYMMDDHHMMSS [+/-HHMM]` (timezone optional).
  /// Examples:
  /// - `20260427060000 +0000`
  /// - `20260427060000 -0500`
  /// - `20260427060000` (assume UTC)
  static DateTime? _parseXmltvDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.length < 14) return null;

    int? p(String v) => int.tryParse(v);

    final year = p(s.substring(0, 4));
    final month = p(s.substring(4, 6));
    final day = p(s.substring(6, 8));
    final hour = p(s.substring(8, 10));
    final minute = p(s.substring(10, 12));
    final second = p(s.substring(12, 14));

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }

    var offsetMinutes = 0;
    if (s.length >= 19) {
      final tz = s.substring(s.length - 5).trim();
      if (tz.length == 5 && (tz[0] == '+' || tz[0] == '-')) {
        final sign = tz[0] == '-' ? -1 : 1;
        final h = int.tryParse(tz.substring(1, 3)) ?? 0;
        final m = int.tryParse(tz.substring(3, 5)) ?? 0;
        offsetMinutes = sign * (h * 60 + m);
      }
    }

    final utc = DateTime.utc(year, month, day, hour, minute, second);
    return utc.subtract(Duration(minutes: offsetMinutes));
  }
}
