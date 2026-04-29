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

    test(
      'liveChannels resolves category_id to readable names with parent chain',
      () async {
        // Route the two API calls based on the `action=` query parameter so
        // categories and streams return distinct payloads.
        when(() => dio.getUri<dynamic>(any())).thenAnswer((Invocation inv) async {
          final uri = inv.positionalArguments.first as Uri;
          final action = uri.queryParameters['action'] ?? '';
          if (action == 'get_live_categories') {
            return ok([
              {'category_id': '1', 'category_name': 'TR', 'parent_id': 0},
              {'category_id': '12', 'category_name': 'Spor', 'parent_id': '1'},
              {'category_id': '15', 'category_name': 'EN', 'parent_id': 0},
            ]);
          }
          if (action == 'get_live_streams') {
            return ok([
              {
                'stream_id': 9001,
                'name': 'beIN Sports',
                'category_id': '12',
              },
              {
                'stream_id': 9002,
                'name': 'BBC One',
                'category_id': '15',
              },
              {
                'stream_id': 9003,
                'name': 'Mystery',
                'category_id': '999', // unknown id
              },
            ]);
          }
          return ok(<Object>[]);
        });

        final channels = await client.liveChannels();
        expect(channels, hasLength(3));

        // child + parent chain — parent name first, full path last.
        expect(channels[0].groups, containsAll(<String>['TR', 'Spor', 'TR > Spor']));

        // Single-level: just the leaf name (no chain entry).
        expect(channels[1].groups, ['EN']);

        // Unknown category id falls back to the raw id (preserves old
        // behaviour for panels without categories).
        expect(channels[2].groups, ['999']);
      },
    );

    test(
      'liveCategories returns id → resolved name map',
      () async {
        when(() => dio.getUri<dynamic>(any())).thenAnswer((Invocation inv) async {
          final uri = inv.positionalArguments.first as Uri;
          if (uri.queryParameters['action'] == 'get_live_categories') {
            return ok([
              {'category_id': '1', 'category_name': 'TR', 'parent_id': 0},
              {
                'category_id': '12',
                'category_name': 'Spor',
                'parent_id': '1',
              },
            ]);
          }
          return ok(<Object>[]);
        });
        final cats = await client.liveCategories();
        expect(cats['1'], 'TR');
        expect(cats['12'], 'TR > Spor');
      },
    );

    test('catchupUrl renders the canonical Xtream timeshift pattern', () {
      // 2026-04-28 18:30 UTC → "2026-04-28:18-30"
      final start = DateTime.utc(2026, 4, 28, 18, 30);
      final url = client.catchupUrl(
        streamId: 12345,
        start: start,
        duration: const Duration(minutes: 90),
      );
      expect(
        url,
        'http://provider.tv:8080/timeshift/u1/p1/90/2026-04-28:18-30/12345.ts',
      );
    });

    test('catchupForChannel parses get_simple_data_table rows', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'epg_listings': [
            {
              'id': '101',
              'title': 'TGl2ZSBOZXdz', // 'Live News' base64
              'description': 'TmV3cyBidWxsZXRpbg==', // 'News bulletin'
              'start_timestamp': '1714326600',
              'stop_timestamp': '1714330200',
              'now_playing': 1,
              'has_archive': 1,
            },
            {
              'id': '102',
              'title': 'U3BvcnRz', // 'Sports' base64
              'start_timestamp': '1714330200',
              'stop_timestamp': '1714333800',
              'has_archive': 0,
            },
          ],
        }),
      );
      final list = await client.catchupForChannel(7);
      expect(list, hasLength(2));
      // Sorted ascending by start.
      expect(list[0].streamId, 7);
      expect(list[0].title, 'Live News');
      expect(list[0].nowPlaying, isTrue);
      expect(list[0].hasArchive, isTrue);
      expect(list[1].title, 'Sports');
      expect(list[1].hasArchive, isFalse);
    });

    test(
      'catchupForChannel returns empty list when panel returns no listings',
      () async {
        when(() => dio.getUri<dynamic>(any())).thenAnswer(
          (_) async => ok(<String, dynamic>{}),
        );
        final list = await client.catchupForChannel(7);
        expect(list, isEmpty);
      },
    );
  });
}
