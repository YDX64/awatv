import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

const String _xmltvBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme channel="bbcone.uk" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>BBC News</title>
    <desc>Bulletin.</desc>
  </programme>
  <programme channel="bbcone.uk" start="20260427130000 +0000" stop="20260427140000 +0000">
    <title>Doctor Who</title>
  </programme>
</tv>
''';

List<int> _gzipped(String body) =>
    const GZipEncoder().encode(utf8.encode(body));

Response<List<int>> _resp(
  List<int> bytes, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return Response<List<int>>(
    data: bytes,
    requestOptions: RequestOptions(path: '/epg'),
    statusCode: statusCode,
    headers: Headers.fromMap(headers ?? const {}),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  group('EpgClient.downloadAndParse', () {
    late _MockDio dio;
    late EpgClient client;

    setUp(() {
      dio = _MockDio();
      client = EpgClient(dio: dio);
    });

    test('parses plain XMLTV body', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(utf8.encode(_xmltvBody)),
      );

      final progs = await client.downloadAndParse('http://x.tv/epg.xml');
      expect(progs, hasLength(2));
      expect(progs[0].title, 'BBC News');
      expect(progs[0].channelTvgId, 'bbcone.uk');
      expect(progs[1].title, 'Doctor Who');
    });

    test('auto-detects gzip via .gz URL suffix and decompresses', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(_gzipped(_xmltvBody)),
      );

      final progs =
          await client.downloadAndParse('http://x.tv/epg.xml.gz');
      expect(progs, hasLength(2));
      expect(progs.first.title, 'BBC News');
    });

    test('auto-detects gzip via Content-Encoding header', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(
          _gzipped(_xmltvBody),
          headers: {
            'content-encoding': ['gzip'],
            'content-type': ['application/xml'],
          },
        ),
      );

      // URL has no .gz suffix here — must rely on header detection.
      final progs =
          await client.downloadAndParse('http://x.tv/api/epg?id=1');
      expect(progs, hasLength(2));
    });

    test('auto-detects gzip via Content-Type: application/gzip', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(
          _gzipped(_xmltvBody),
          headers: {
            'content-type': ['application/gzip'],
          },
        ),
      );

      final progs = await client.downloadAndParse('http://x.tv/epg');
      expect(progs, hasLength(2));
    });

    test('auto-detects gzip via magic bytes 0x1F 0x8B', () async {
      // Server forgot to set headers, URL has no .gz suffix; rely on magic.
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(_gzipped(_xmltvBody)),
      );

      final progs =
          await client.downloadAndParse('http://x.tv/api/epg?id=1');
      expect(progs, hasLength(2));
      // First two bytes of a gzipped stream are 1F 8B by spec; sanity-check
      // our test fixture really starts with that.
      final bytes = _gzipped(_xmltvBody);
      expect(bytes[0], 0x1F);
      expect(bytes[1], 0x8B);
    });

    test('throws NetworkException on DioException', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/epg'),
          type: DioExceptionType.connectionError,
          message: 'no internet',
        ),
      );

      await expectLater(
        client.downloadAndParse('http://x.tv/epg.xml'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    });

    test('throws NetworkException on non-2xx', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(<int>[], statusCode: 500),
      );

      await expectLater(
        client.downloadAndParse('http://x.tv/epg.xml'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('returns empty list when body is empty XML', () async {
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(utf8.encode('  ')),
      );

      final progs = await client.downloadAndParse('http://x.tv/epg.xml');
      expect(progs, isEmpty);
    });

    test('handles UTF-8 multi-byte characters in body', () async {
      const body = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme channel="tr1" start="20260427120000 +0000" stop="20260427130000 +0000">
    <title>Şampiyonlar Ligi</title>
  </programme>
</tv>
''';
      when(
        () => dio.get<List<int>>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _resp(Uint8List.fromList(utf8.encode(body))),
      );
      final progs = await client.downloadAndParse('http://x.tv/epg.xml');
      expect(progs, hasLength(1));
      expect(progs.first.title, 'Şampiyonlar Ligi');
    });
  });
}
