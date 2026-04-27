import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XmltvParser', () {
    test('returns empty list on empty body (no exception)', () {
      expect(XmltvParser.parse(''), isEmpty);
      expect(XmltvParser.parse('   \n  \t '), isEmpty);
    });

    test('parses a minimal programme element correctly', () {
      const body = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="news.tv"><display-name>News</display-name></channel>
  <programme channel="news.tv" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Midday News</title>
    <desc>Headlines and weather.</desc>
    <category>News</category>
  </programme>
</tv>
''';
      final result = XmltvParser.parse(body);
      expect(result, hasLength(1));
      final p = result.first;
      expect(p.channelTvgId, 'news.tv');
      expect(p.title, 'Midday News');
      expect(p.description, 'Headlines and weather.');
      expect(p.category, 'News');
      // 12:00 UTC at +0000 → exactly 12:00 UTC stored.
      expect(p.start.toUtc(), DateTime.utc(2026, 4, 27, 12));
      expect(p.stop.toUtc(), DateTime.utc(2026, 4, 27, 13));
    });

    test('handles +0200 offset by converting to UTC (subtracts 2h)', () {
      const body = '''
<tv>
  <programme channel="de1" start="20260427140000 +0200" stop="20260427150000 +0200">
    <title>Tagesschau</title>
  </programme>
</tv>
''';
      final p = XmltvParser.parse(body).single;
      // 14:00 in +0200 is 12:00 UTC.
      expect(p.start.toUtc(), DateTime.utc(2026, 4, 27, 12));
      expect(p.stop.toUtc(), DateTime.utc(2026, 4, 27, 13));
    });

    test('handles -0500 offset by converting to UTC (adds 5h)', () {
      const body = '''
<tv>
  <programme channel="us1" start="20260427070000 -0500" stop="20260427080000 -0500">
    <title>Morning Show</title>
  </programme>
</tv>
''';
      final p = XmltvParser.parse(body).single;
      // 07:00 in -0500 is 12:00 UTC.
      expect(p.start.toUtc(), DateTime.utc(2026, 4, 27, 12));
      expect(p.stop.toUtc(), DateTime.utc(2026, 4, 27, 13));
    });

    test('parses date without timezone offset as UTC', () {
      const body = '''
<tv>
  <programme channel="zone.unknown" start="20260427120000" stop="20260427130000">
    <title>Unzoned</title>
  </programme>
</tv>
''';
      final p = XmltvParser.parse(body).single;
      expect(p.start.toUtc(), DateTime.utc(2026, 4, 27, 12));
      expect(p.stop.toUtc(), DateTime.utc(2026, 4, 27, 13));
    });

    test('skips programmes with missing start/stop/channel attributes', () {
      const body = '''
<tv>
  <programme start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>No channel attr</title>
  </programme>
  <programme channel="x" stop="20260427130000 +0000">
    <title>No start</title>
  </programme>
  <programme channel="x" start="20260427120000 +0000">
    <title>No stop</title>
  </programme>
  <programme channel="ok" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Good</title>
  </programme>
</tv>
''';
      final result = XmltvParser.parse(body);
      expect(result, hasLength(1));
      expect(result.single.title, 'Good');
    });

    test('skips programmes with empty title', () {
      const body = '''
<tv>
  <programme channel="x" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title></title>
  </programme>
  <programme channel="y" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Has Title</title>
  </programme>
</tv>
''';
      final result = XmltvParser.parse(body);
      expect(result, hasLength(1));
      expect(result.single.channelTvgId, 'y');
    });

    test('preserves UTF-8 accented and non-ASCII titles', () {
      const body = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme channel="tr1" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Şampiyonlar Ligi: Galatasaray — İstanbul</title>
    <desc>Maç özeti ve değerlendirme.</desc>
  </programme>
  <programme channel="fr1" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Bonjour à tous — Café déjà brûlé</title>
  </programme>
</tv>
''';
      final result = XmltvParser.parse(body);
      expect(result, hasLength(2));
      expect(
        result[0].title,
        'Şampiyonlar Ligi: Galatasaray — İstanbul',
      );
      expect(result[0].description, 'Maç özeti ve değerlendirme.');
      expect(result[1].title, 'Bonjour à tous — Café déjà brûlé');
    });

    test('throws PlaylistParseException on malformed XML', () {
      const body = '<tv><programme><<<not really xml';
      expect(
        () => XmltvParser.parse(body),
        throwsA(isA<PlaylistParseException>()),
      );
    });

    test('returns empty list for valid XML with no programme elements', () {
      const body = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="bbcone.uk"><display-name>BBC One</display-name></channel>
</tv>
''';
      expect(XmltvParser.parse(body), isEmpty);
    });

    test('description and category are null when child elements absent', () {
      const body = '''
<tv>
  <programme channel="x" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Lonely Title</title>
  </programme>
</tv>
''';
      final p = XmltvParser.parse(body).single;
      expect(p.description, isNull);
      expect(p.category, isNull);
    });

    test('returns unmodifiable list', () {
      const body = '''
<tv>
  <programme channel="x" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>One</title>
  </programme>
</tv>
''';
      final result = XmltvParser.parse(body);
      expect(
        () => result.add(
          EpgProgramme(
            channelTvgId: 'y',
            start: DateTime.utc(2026),
            stop: DateTime.utc(2026, 1, 1, 1),
            title: 'extra',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
