import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

const String _m3uBody = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbcone.uk" tvg-logo="http://l/bbc.png" group-title="UK",BBC One
http://stream.example.com/bbc.ts
#EXTINF:-1 tvg-id="cnn.us" group-title="News",CNN
http://stream.example.com/cnn.ts
''';

Response<dynamic> _ok(dynamic body) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
      statusCode: 200,
      data: body,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(Options());
  });

  late Directory tmp;
  late AwatvStorage storage;
  late _MockDio dio;
  late PlaylistService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_pl_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    dio = _MockDio();
    service = PlaylistService(storage: storage, dio: dio);
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('PlaylistService.add — M3U', () {
    test('downloads body, parses, persists channels', () async {
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(_m3uBody));

      final src = PlaylistSource(
        id: 'm3u-1',
        name: 'My M3U',
        kind: PlaylistKind.m3u,
        url: 'http://example.com/list.m3u',
        addedAt: DateTime.utc(2026, 4, 27),
      );

      final result = await service.add(src);
      expect(result.id, 'm3u-1');
      expect(result.lastSyncAt, isNotNull);

      // Channels should be persisted.
      final channels = await service.channels('m3u-1');
      expect(channels, hasLength(2));
      expect(
        channels.map((c) => c.name).toList(),
        containsAll(['BBC One', 'CNN']),
      );

      // Source itself should be persisted.
      final stored = await storage.getSource('m3u-1');
      expect(stored, isNotNull);
      expect(stored!.lastSyncAt, isNotNull);
    });

    test('throws NetworkException when download returns 4xx', () async {
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 404,
          data: 'not found',
        ),
      );

      final src = PlaylistSource(
        id: 'm3u-bad',
        name: 'broken',
        kind: PlaylistKind.m3u,
        url: 'http://example.com/missing.m3u',
        addedAt: DateTime.utc(2026, 4, 27),
      );

      await expectLater(
        service.add(src),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });
  });

  group('PlaylistService.refresh', () {
    test('throws StorageException for unknown source', () async {
      await expectLater(
        service.refresh('nope'),
        throwsA(isA<StorageException>()),
      );
    });

    test('re-runs M3U parsing path on subsequent refresh', () async {
      // First add with two channels.
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(_m3uBody));

      final src = PlaylistSource(
        id: 'm3u-r',
        name: 'refresh me',
        kind: PlaylistKind.m3u,
        url: 'http://example.com/list.m3u',
        addedAt: DateTime.utc(2026, 4, 27),
      );
      await service.add(src);
      expect(await service.channels('m3u-r'), hasLength(2));

      // Now stub a different body for the refresh.
      const updatedBody = '''
#EXTM3U
#EXTINF:-1 tvg-id="only.tv",Only Channel
http://example.com/only.ts
''';
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(updatedBody));

      await service.refresh('m3u-r');
      final after = await service.channels('m3u-r');
      expect(after, hasLength(1));
      expect(after.single.name, 'Only Channel');
    });
  });

  group('PlaylistService.add — Xtream', () {
    test('authenticates, fetches live/vod/series, persists each', () async {
      // Tag responses by query action.
      when(() => dio.getUri<dynamic>(any())).thenAnswer((inv) async {
        final uri = inv.positionalArguments.first as Uri;
        final action = uri.queryParameters['action'];
        switch (action) {
          case null:
            // Auth ping.
            return _ok({
              'user_info': {'auth': 1, 'status': 'Active'},
              'server_info': {'url': 'http://provider.tv'},
            });
          case 'get_live_streams':
            return _ok([
              {
                'stream_id': 1,
                'name': 'Live A',
                'epg_channel_id': 'a.tv',
                'category_id': '7',
              },
            ]);
          case 'get_vod_streams':
            return _ok([
              {
                'stream_id': 100,
                'name': 'Movie A',
                'container_extension': 'mkv',
                'releaseDate': '2010-07-16',
                'rating': '8.0',
              },
            ]);
          case 'get_series':
            return _ok([
              {
                'series_id': 200,
                'name': 'Show A',
                'rating': '9.0',
                'releaseDate': '2008-01-20',
              },
            ]);
        }
        return _ok([]);
      });

      final src = PlaylistSource(
        id: 'xt-1',
        name: 'Xtream',
        kind: PlaylistKind.xtream,
        url: 'http://provider.tv:8080',
        username: 'u',
        password: 'p',
        addedAt: DateTime.utc(2026, 4, 27),
      );

      await service.add(src);

      final channels = await service.channels('xt-1');
      expect(channels, hasLength(1));
      expect(channels.single.name, 'Live A');

      final vod = await service.vodItems('xt-1');
      expect(vod, hasLength(1));
      expect(vod.single.title, 'Movie A');

      final allSeries = await service.series('xt-1');
      expect(allSeries, hasLength(1));
      expect(allSeries.single.title, 'Show A');
    });

    test('throws XtreamAuthException when credentials missing', () async {
      final src = PlaylistSource(
        id: 'xt-bad',
        name: 'no creds',
        kind: PlaylistKind.xtream,
        url: 'http://x',
        addedAt: DateTime.utc(2026, 4, 27),
      );

      await expectLater(
        service.add(src),
        throwsA(isA<XtreamAuthException>()),
      );
    });
  });

  group('PlaylistService.remove', () {
    test('deletes source + associated boxes', () async {
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(_m3uBody));

      final src = PlaylistSource(
        id: 'rm-1',
        name: 'remove me',
        kind: PlaylistKind.m3u,
        url: 'http://example.com/list.m3u',
        addedAt: DateTime.utc(2026, 4, 27),
      );
      await service.add(src);
      expect(await service.channels('rm-1'), isNotEmpty);

      await service.remove('rm-1');
      expect(await storage.getSource('rm-1'), isNull);
      expect(await service.channels('rm-1'), isEmpty);
    });
  });

  group('PlaylistService.list', () {
    test('returns sources persisted across add() calls', () async {
      when(
        () => dio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(_m3uBody));

      await service.add(
        PlaylistSource(
          id: 's1',
          name: 'A',
          kind: PlaylistKind.m3u,
          url: 'http://example.com/a.m3u',
          addedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      await service.add(
        PlaylistSource(
          id: 's2',
          name: 'B',
          kind: PlaylistKind.m3u,
          url: 'http://example.com/b.m3u',
          addedAt: DateTime.utc(2026, 4, 2),
        ),
      );

      final all = await service.list();
      expect(all.map((s) => s.id), ['s1', 's2']);
    });
  });

  group('PlaylistService.episodes', () {
    test('returns empty list when no Xtream source matches', () async {
      // No sources at all.
      expect(await service.episodes('does::not::matter', 1), isEmpty);
    });

    test('filters Xtream API response by season', () async {
      // Wire up Xtream calls so add() persists series, then episodes() can
      // parse + filter.
      when(() => dio.getUri<dynamic>(any())).thenAnswer((inv) async {
        final uri = inv.positionalArguments.first as Uri;
        final action = uri.queryParameters['action'];
        switch (action) {
          case null:
            return _ok({
              'user_info': {'auth': 1},
              'server_info': {},
            });
          case 'get_live_streams':
            return _ok(<dynamic>[]);
          case 'get_vod_streams':
            return _ok(<dynamic>[]);
          case 'get_series':
            return _ok([
              {
                'series_id': 42,
                'name': 'S',
                'rating': '8.0',
              },
            ]);
          case 'get_series_info':
            return _ok({
              'episodes': {
                '1': [
                  {
                    'id': 11,
                    'episode_num': 1,
                    'title': 'S1E1',
                    'container_extension': 'mp4',
                    'info': <String, dynamic>{},
                  },
                  {
                    'id': 12,
                    'episode_num': 2,
                    'title': 'S1E2',
                    'container_extension': 'mp4',
                    'info': <String, dynamic>{},
                  },
                ],
                '2': [
                  {
                    'id': 21,
                    'episode_num': 1,
                    'title': 'S2E1',
                    'container_extension': 'mp4',
                    'info': <String, dynamic>{},
                  },
                ],
              },
            });
        }
        return _ok([]);
      });

      final src = PlaylistSource(
        id: 'xt-eps',
        name: 'episodes test',
        kind: PlaylistKind.xtream,
        url: 'http://provider.tv:8080',
        username: 'u',
        password: 'p',
        addedAt: DateTime.utc(2026, 4, 27),
      );
      await service.add(src);

      final allSeries = await service.series('xt-eps');
      expect(allSeries, hasLength(1));
      final seriesId = allSeries.single.id;

      final s1 = await service.episodes(seriesId, 1);
      expect(s1, hasLength(2));
      expect(s1.map((e) => e.title), ['S1E1', 'S1E2']);

      final s2 = await service.episodes(seriesId, 2);
      expect(s2, hasLength(1));
      expect(s2.single.title, 'S2E1');

      final s3 = await service.episodes(seriesId, 3);
      expect(s3, isEmpty);
    });
  });
}
