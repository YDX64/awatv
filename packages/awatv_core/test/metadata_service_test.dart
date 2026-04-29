// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> _ok(dynamic body) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
      statusCode: 200,
      data: body,
    );

const Map<String, dynamic> _movieResponse = {
  'results': [
    {
      'id': 27205,
      'title': 'Inception',
      'original_title': 'Inception',
      'overview': 'A thief.',
      'genre_ids': <int>[28, 878],
      'poster_path': '/p.jpg',
      'backdrop_path': '/b.jpg',
      'vote_average': 8.4,
      'release_date': '2010-07-16',
    },
  ],
};

const Map<String, dynamic> _seriesResponse = {
  'results': [
    {
      'id': 1396,
      'name': 'Breaking Bad',
      'original_name': 'Breaking Bad',
      'overview': 'Plot.',
      'genre_ids': <int>[18],
      'first_air_date': '2008-01-20',
    },
  ],
};

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  late Directory tmp;
  late AwatvStorage storage;
  late _MockDio dio;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_meta_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    dio = _MockDio();
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('MetadataService.movieByTitle — TMDB enabled', () {
    test('cache miss: TMDB called, result persisted', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);

      when(() => dio.getUri<dynamic>(any()))
          .thenAnswer((_) async => _ok(_movieResponse));

      final m = await svc.movieByTitle('Inception', year: 2010);
      expect(m, isNotNull);
      expect(m!.tmdbId, 27205);
      verify(() => dio.getUri<dynamic>(any())).called(1);

      // Persisted in storage with the key MetadataService composes.
      final cached =
          await storage.getMetadataJson('tmdb:movie:inception:2010');
      expect(cached, isNotNull);
      expect(cached!['tmdbId'], 27205);
    });

    test('cache hit: TMDB is NOT called when fresh entry exists', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);

      // Pre-seed cache. Note: MetadataService lowercases the title.
      await storage.putMetadataJson('tmdb:movie:cached movie:', {
        'tmdbId': 9999,
        'title': 'Cached Movie',
        'originalTitle': 'Cached Movie',
        'overview': 'from cache',
        'genres': <String>[],
      });

      final m = await svc.movieByTitle('Cached Movie');
      expect(m, isNotNull);
      expect(m!.tmdbId, 9999);
      expect(m.title, 'Cached Movie');
      verifyNever(() => dio.getUri<dynamic>(any()));
    });

    test('stale cache (older than TTL) bypasses cache and calls TMDB',
        () async {
      // Use a tiny TTL so anything we just wrote is already stale.
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(
        storage: storage,
        tmdb: tmdb,
        cacheTtl: const Duration(microseconds: 1),
      );

      await storage.putMetadataJson('tmdb:movie:inception:2010', {
        'tmdbId': 1,
        'title': 'Stale',
        'originalTitle': 'Stale',
        'overview': 'old',
        'genres': <String>[],
      });
      // Yield once so the savedAt timestamp is firmly in the past.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      when(() => dio.getUri<dynamic>(any()))
          .thenAnswer((_) async => _ok(_movieResponse));

      final m = await svc.movieByTitle('Inception', year: 2010);
      expect(m!.tmdbId, 27205);
      // Confirm fresh fetch happened.
      verify(() => dio.getUri<dynamic>(any())).called(1);
    });

    test('cache miss with no TMDB results returns null and does NOT cache',
        () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);

      when(() => dio.getUri<dynamic>(any()))
          .thenAnswer((_) async => _ok({'results': <dynamic>[]}));

      final m = await svc.movieByTitle('NoSuchMovie');
      expect(m, isNull);
      // No write should have occurred.
      final cached =
          await storage.getMetadataJson('tmdb:movie:nosuchmovie:');
      expect(cached, isNull);
    });
  });

  group('MetadataService.movieByTitle — TMDB disabled', () {
    test('returns null without throwing when TMDB client is null', () async {
      final svc = MetadataService(storage: storage);
      expect(await svc.movieByTitle('Whatever'), isNull);
    });

    test('still serves cached entries when TMDB client is null', () async {
      await storage.putMetadataJson('tmdb:movie:offline movie:', {
        'tmdbId': 42,
        'title': 'Offline Movie',
        'originalTitle': 'Offline Movie',
        'overview': '',
        'genres': <String>[],
      });
      final svc = MetadataService(storage: storage);
      final m = await svc.movieByTitle('Offline Movie');
      expect(m, isNotNull);
      expect(m!.tmdbId, 42);
    });
  });

  group('MetadataService.seriesByTitle', () {
    test('cache miss: fresh fetch + persisted', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);

      when(() => dio.getUri<dynamic>(any()))
          .thenAnswer((_) async => _ok(_seriesResponse));

      final s = await svc.seriesByTitle('Breaking Bad');
      expect(s!.tmdbId, 1396);
      final cached = await storage.getMetadataJson('tmdb:tv:breaking bad');
      expect(cached, isNotNull);
      expect(cached!['tmdbId'], 1396);
    });

    test('cache hit avoids TMDB call', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);

      await storage.putMetadataJson('tmdb:tv:cached show', {
        'tmdbId': 12345,
        'title': 'Cached Show',
        'originalTitle': 'Cached Show',
        'overview': '',
        'genres': <String>[],
      });
      final s = await svc.seriesByTitle('Cached Show');
      expect(s!.tmdbId, 12345);
      verifyNever(() => dio.getUri<dynamic>(any()));
    });

    test('returns null when TMDB client is null', () async {
      final svc = MetadataService(storage: storage);
      expect(await svc.seriesByTitle('NoTmdbKey'), isNull);
    });
  });

  group('MetadataService.trailerYoutubeId', () {
    test('returns null when TMDB client is absent', () async {
      final svc = MetadataService(storage: storage);
      expect(await svc.trailerYoutubeId(1, MediaType.movie), isNull);
      expect(await svc.trailerYoutubeId(1, MediaType.series), isNull);
    });

    test('delegates to TMDB movie trailer when kind=movie', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => _ok({
          'results': [
            {
              'site': 'YouTube',
              'type': 'Trailer',
              'key': 'movie-key',
              'official': true,
            },
          ],
        }),
      );
      final id = await svc.trailerYoutubeId(27205, MediaType.movie);
      expect(id, 'movie-key');
    });

    test('delegates to TMDB tv trailer when kind=series', () async {
      final tmdb = TmdbClient(apiKey: 'k', dio: dio);
      final svc = MetadataService(storage: storage, tmdb: tmdb);
      Uri? captured;
      when(() => dio.getUri<dynamic>(captureAny())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as Uri;
        return _ok({
          'results': [
            {'site': 'YouTube', 'type': 'Trailer', 'key': 'tv-key'},
          ],
        });
      });
      final id = await svc.trailerYoutubeId(1396, MediaType.series);
      expect(id, 'tv-key');
      expect(captured!.path, contains('/tv/1396/videos'));
    });
  });
}
