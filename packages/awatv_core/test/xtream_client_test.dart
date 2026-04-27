import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  group('XtreamClient', () {
    late _MockDio dio;
    late XtreamClient client;

    setUp(() {
      dio = _MockDio();
      client = XtreamClient(
        server: 'http://provider.tv:8080',
        username: 'u1',
        password: 'p1',
        dio: dio,
      );
    });

    Response<dynamic> ok(dynamic body) => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: body,
        );

    test('authenticate succeeds when user_info.auth == 1', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'user_info': {'auth': 1, 'status': 'Active'},
          'server_info': {'url': 'http://provider.tv'},
        }),
      );
      expect(await client.authenticate(), isTrue);
    });

    test('authenticate throws XtreamAuthException on auth=0', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'user_info': {'auth': 0},
        }),
      );
      expect(
        client.authenticate,
        throwsA(isA<XtreamAuthException>()),
      );
    });

    test('authenticate throws XtreamAuthException on HTTP 401', () async {
      when(() => dio.getUri<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(
        client.authenticate,
        throwsA(isA<XtreamAuthException>()),
      );
    });

    test('liveChannels parses array response and builds stream URL', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok([
          {
            'stream_id': 9001,
            'name': 'Test HD',
            'epg_channel_id': 'test.hd',
            'stream_icon': 'http://logo.png',
            'category_id': '7',
          },
          {
            'stream_id': 9002,
            'name': 'No Logo',
          },
        ]),
      );
      final channels = await client.liveChannels();
      expect(channels, hasLength(2));
      final c0 = channels[0];
      expect(c0.name, 'Test HD');
      expect(c0.tvgId, 'test.hd');
      expect(c0.streamUrl, 'http://provider.tv:8080/u1/p1/9001.ts');
      expect(c0.groups, ['7']);
      expect(c0.kind, ChannelKind.live);
      expect(c0.logoUrl, 'http://logo.png');
      // Stable id must contain tvg-id when present.
      expect(c0.id, contains('test.hd'));

      final c1 = channels[1];
      expect(c1.tvgId, isNull);
      expect(c1.logoUrl, isNull);
    });

    test('vodItems builds /movie/ URL with container extension', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok([
          {
            'stream_id': 1234,
            'name': 'Inception',
            'container_extension': 'mkv',
            'releaseDate': '2010-07-16',
            'rating': '8.8',
            'tmdb_id': 27205,
            'plot': 'Dreams within dreams.',
          },
        ]),
      );
      final items = await client.vodItems();
      expect(items, hasLength(1));
      final v = items.first;
      expect(v.title, 'Inception');
      expect(
        v.streamUrl,
        'http://provider.tv:8080/movie/u1/p1/1234.mkv',
      );
      expect(v.year, 2010);
      expect(v.rating, closeTo(8.8, 0.001));
      expect(v.tmdbId, 27205);
      expect(v.plot, 'Dreams within dreams.');
    });

    test('series returns SeriesItem list', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok([
          {
            'series_id': 77,
            'name': 'Breaking Bad',
            'cover': 'http://poster.png',
            'rating': '9.5',
            'releaseDate': '2008-01-20',
            'tmdb': 1396,
            'plot': 'A chemistry teacher turns to crime.',
          },
        ]),
      );
      final items = await client.series();
      expect(items, hasLength(1));
      expect(items.first.title, 'Breaking Bad');
      expect(items.first.year, 2008);
      expect(items.first.rating, closeTo(9.5, 0.001));
      expect(items.first.tmdbId, 1396);
    });

    test('seriesEpisodes flattens season map', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'episodes': {
            '1': [
              {
                'id': 555,
                'episode_num': 1,
                'title': 'Pilot',
                'container_extension': 'mp4',
                'info': {
                  'plot': 'It begins.',
                  'duration_secs': 3000,
                  'movie_image': 'http://img.png',
                },
              },
            ],
          },
        }),
      );
      final eps = await client.seriesEpisodes(77);
      expect(eps, hasLength(1));
      final e = eps.first;
      expect(e.season, 1);
      expect(e.number, 1);
      expect(e.title, 'Pilot');
      expect(e.durationMin, 50);
      expect(
        e.streamUrl,
        'http://provider.tv:8080/series/u1/p1/555.mp4',
      );
    });

    test('NetworkException on 5xx', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 503,
        ),
      );
      expect(
        client.liveChannels,
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
