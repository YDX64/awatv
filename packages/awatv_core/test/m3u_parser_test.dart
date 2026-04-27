import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M3uParser', () {
    test('returns empty list on empty input', () {
      expect(M3uParser.parse('', 'src1'), isEmpty);
      expect(M3uParser.parse('   \n  \n', 'src1'), isEmpty);
    });

    test('throws PlaylistParseException on body that has no EXTINF and no URLs',
        () {
      const garbage = 'this is not\nan m3u file at all\n# random comment';
      expect(
        () => M3uParser.parse(garbage, 'src1'),
        throwsA(isA<PlaylistParseException>()),
      );
    });

    test('parses a real-world EXTM3U with attributes', () {
      const body = '''
#EXTM3U url-tvg="https://example.com/epg.xml.gz"
#EXTINF:-1 tvg-id="bbcone.uk" tvg-logo="https://logos.tv/bbc1.png" group-title="UK / News",BBC One HD
#EXTVLCOPT:http-user-agent=AWAtv/1.0
http://stream.example.com/live/bbc1.m3u8

#EXTINF:-1 tvg-id="cnn.us" tvg-logo="https://logos.tv/cnn.png" group-title="News",CNN International
#EXTGRP:News/International
http://stream.example.com/live/cnn.ts

#EXTINF:-1 tvg-id="" tvg-logo="" group-title="Movies",The Matrix (1999)
http://stream.example.com/movie/matrix.mp4
''';

      final channels = M3uParser.parse(body, 'src-abc');
      expect(channels, hasLength(3));

      final bbc = channels[0];
      expect(bbc.name, 'BBC One HD');
      expect(bbc.tvgId, 'bbcone.uk');
      expect(bbc.logoUrl, 'https://logos.tv/bbc1.png');
      expect(bbc.streamUrl, 'http://stream.example.com/live/bbc1.m3u8');
      expect(bbc.groups, containsAll(['UK', 'News']));
      expect(bbc.kind, ChannelKind.live);
      expect(bbc.id, 'src-abc::bbcone.uk');
      expect(bbc.extras['http-user-agent'], 'AWAtv/1.0');

      final cnn = channels[1];
      expect(cnn.tvgId, 'cnn.us');
      expect(cnn.groups, contains('News'));
      // EXTGRP appended additional grouping.
      expect(cnn.groups, contains('International'));

      final matrix = channels[2];
      expect(matrix.name, 'The Matrix (1999)');
      // No tvg-id, so id falls back to name.
      expect(matrix.id, 'src-abc::The Matrix (1999)');
      expect(matrix.kind, ChannelKind.vod);
      // Empty attribute strings are normalised to null.
      expect(matrix.tvgId, isNull);
      expect(matrix.logoUrl, isNull);
    });

    test('continues parsing past malformed EXTINF (URL is kept as bare entry)',
        () {
      // Real-world IPTV providers occasionally emit broken EXTINF tags.
      // We treat the orphan URL as a bare entry (no metadata) rather than
      // dropping it — losing channels silently is worse than naming one
      // after its file segment.
      const body = '''
#EXTM3U
#EXTINF
http://example.com/ignored.ts
#EXTINF:-1 tvg-id="ok",Good Channel
http://example.com/good.ts
''';
      final channels = M3uParser.parse(body, 'src1');
      expect(channels, hasLength(2));
      expect(
        channels.firstWhere((c) => c.tvgId == 'ok').name,
        'Good Channel',
      );
    });

    test('handles bare URLs without EXTINF', () {
      const body = '''
#EXTM3U
http://example.com/raw1.ts
http://example.com/raw2.ts
''';
      final channels = M3uParser.parse(body, 'src1');
      expect(channels, hasLength(2));
      expect(channels.first.streamUrl, 'http://example.com/raw1.ts');
      expect(channels.first.name, 'raw1.ts');
    });

    test('detects series via /series/ path segment', () {
      const body = '''
#EXTM3U
#EXTINF:-1 tvg-id="" tvg-logo="" group-title="",Breaking Bad S01E01
http://provider.tv/series/u/p/12345.mp4
''';
      final channels = M3uParser.parse(body, 'src1');
      expect(channels, hasLength(1));
      expect(channels.first.kind, ChannelKind.series);
    });

    test('parses titles containing commas inside quoted attributes', () {
      const body = '''
#EXTM3U
#EXTINF:-1 tvg-id="x" group-title="Movies, Drama",The, Comma, Movie
http://example.com/c.mp4
''';
      final channels = M3uParser.parse(body, 'src1');
      expect(channels, hasLength(1));
      expect(channels.first.name, 'The, Comma, Movie');
      expect(channels.first.groups, contains('Movies, Drama'));
    });
  });
}
