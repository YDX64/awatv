import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  Response<dynamic> ok(dynamic body) => Response<dynamic>(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 200,
        data: body,
      );

  group('TmdbClient image URL helpers', () {
    test('posterUrl returns null for null path', () {
      expect(TmdbClient.posterUrl(null), isNull);
    });

    test('posterUrl returns null for empty path', () {
      expect(TmdbClient.posterUrl(''), isNull);
    });

    test('posterUrl prefixes the canonical w500 base path', () {
      expect(
        TmdbClient.posterUrl('/abc.jpg'),
        'https://image.tmdb.org/t/p/w500/abc.jpg',
      );
    });

    test('backdropUrl uses the original-size base', () {
      expect(
        TmdbClient.backdropUrl('/back.jpg'),
        'https://image.tmdb.org/t/p/original/back.jpg',
      );
    });

    test('backdropUrl returns null for null/empty path', () {
      expect(TmdbClient.backdropUrl(null), isNull);
      expect(TmdbClient.backdropUrl(''), isNull);
    });
  });

  group('TmdbClient.searchMovie', () {
    late _MockDio dio;
    late TmdbClient client;

    setUp(() {
      dio = _MockDio();
      client = TmdbClient(apiKey: 'test-key', dio: dio);
    });

    test('returns MovieMetadata for a valid response', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'page': 1,
          'results': [
            {
              'id': 27205,
              'title': 'Inception',
              'original_title': 'Inception',
              'overview': 'A thief who steals corporate secrets.',
              'genre_ids': [28, 878, 53],
              'poster_path': '/inception_poster.jpg',
              'backdrop_path': '/inception_back.jpg',
              'vote_average': 8.4,
              'release_date': '2010-07-16',
            },
          ],
        }),
      );

      final m = await client.searchMovie('Inception');
      expect(m, isNotNull);
      expect(m!.tmdbId, 27205);
      expect(m.title, 'Inception');
      expect(m.originalTitle, 'Inception');
      expect(m.overview, 'A thief who steals corporate secrets.');
      expect(m.posterPath, '/inception_poster.jpg');
      expect(m.backdropPath, '/inception_back.jpg');
      expect(m.rating, closeTo(8.4, 0.001));
      expect(m.releaseDate, DateTime.parse('2010-07-16'));
      expect(m.genres, containsAll(['Action', 'Science Fiction', 'Thriller']));
    });

    test('returns null when results array is empty', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({'page': 1, 'results': <Map<String, dynamic>>[]}),
      );
      expect(await client.searchMovie('Nonexistent'), isNull);
    });

    test('returns null for empty title without making a network call', () async {
      // Should short-circuit and not invoke dio.getUri.
      expect(await client.searchMovie(''), isNull);
      expect(await client.searchMovie('   '), isNull);
      verifyNever(() => dio.getUri<dynamic>(any()));
    });

    test('passes year as &year=1999 in the request URI', () async {
      Uri? captured;
      when(() => dio.getUri<dynamic>(captureAny())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as Uri;
        return ok({
          'results': [
            {'id': 603, 'title': 'The Matrix', 'original_title': 'The Matrix'},
          ],
        });
      });

      await client.searchMovie('The Matrix', year: 1999);
      expect(captured, isNotNull);
      expect(captured!.queryParameters['year'], '1999');
      expect(captured!.queryParameters['query'], 'The Matrix');
      expect(captured!.path, contains('/search/movie'));
    });

    test('handles malformed result entry by returning null', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'results': [
            {'no_id_field': true},
          ],
        }),
      );
      expect(await client.searchMovie('something'), isNull);
    });

    test('throws NetworkException with statusCode=401 on auth failure',
        () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 401,
          data: {'status_code': 7, 'status_message': 'Invalid API key'},
        ),
      );

      await expectLater(
        client.searchMovie('Inception'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });

    test('translates DioException with response.statusCode=401', () async {
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

      await expectLater(
        client.searchMovie('Inception'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });

    test('marks 5xx as retryable', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 503,
        ),
      );

      await expectLater(
        client.searchMovie('Inception'),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('connection errors mark NetworkException as retryable', () async {
      when(() => dio.getUri<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
          message: 'connection timed out',
        ),
      );

      await expectLater(
        client.searchMovie('Inception'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    });
  });

  group('TmdbClient.searchSeries', () {
    late _MockDio dio;
    late TmdbClient client;

    setUp(() {
      dio = _MockDio();
      client = TmdbClient(apiKey: 'test-key', dio: dio);
    });

    test('returns SeriesMetadata for a valid response', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'results': [
            {
              'id': 1396,
              'name': 'Breaking Bad',
              'original_name': 'Breaking Bad',
              'overview': 'A teacher turns to crime.',
              'genre_ids': [18, 80],
              'poster_path': '/bb.jpg',
              'backdrop_path': '/bb_back.jpg',
              'vote_average': 9.5,
              'first_air_date': '2008-01-20',
            },
          ],
        }),
      );

      final s = await client.searchSeries('Breaking Bad');
      expect(s, isNotNull);
      expect(s!.tmdbId, 1396);
      expect(s.title, 'Breaking Bad');
      expect(s.overview, 'A teacher turns to crime.');
      expect(s.rating, closeTo(9.5, 0.001));
      expect(s.releaseDate, DateTime.parse('2008-01-20'));
      expect(s.genres, containsAll(['Drama', 'Crime']));
    });

    test('searchSeries returns null when results empty', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({'results': <Map<String, dynamic>>[]}),
      );
      expect(await client.searchSeries('Unknown'), isNull);
    });

    test('searchSeries hits /search/tv path', () async {
      Uri? captured;
      when(() => dio.getUri<dynamic>(captureAny())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as Uri;
        return ok({'results': <Map<String, dynamic>>[]});
      });
      await client.searchSeries('anything');
      expect(captured!.path, contains('/search/tv'));
    });
  });

  group('TmdbClient.movieTrailerYoutubeId', () {
    late _MockDio dio;
    late TmdbClient client;

    setUp(() {
      dio = _MockDio();
      client = TmdbClient(apiKey: 'test-key', dio: dio);
    });

    test('extracts YouTube key when type=Trailer + site=YouTube', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'id': 27205,
          'results': [
            {
              'site': 'Vimeo',
              'type': 'Trailer',
              'key': 'wronghost',
            },
            {
              'site': 'YouTube',
              'type': 'Trailer',
              'official': true,
              'key': 'YoHD9XEInc0',
            },
            {
              'site': 'YouTube',
              'type': 'Featurette',
              'key': 'extraextra',
            },
          ],
        }),
      );

      expect(await client.movieTrailerYoutubeId(27205), 'YoHD9XEInc0');
    });

    test('returns null when no trailer present', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({'id': 1, 'results': <dynamic>[]}),
      );
      expect(await client.movieTrailerYoutubeId(1), isNull);
    });

    test('returns null when results field is missing', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({'id': 1}),
      );
      expect(await client.movieTrailerYoutubeId(1), isNull);
    });

    test('falls back to first valid YouTube entry when no Trailer type', () async {
      when(() => dio.getUri<dynamic>(any())).thenAnswer(
        (_) async => ok({
          'results': [
            {
              'site': 'YouTube',
              'type': 'Featurette',
              'key': 'feat-key',
            },
          ],
        }),
      );
      expect(await client.movieTrailerYoutubeId(99), 'feat-key');
    });

    test('seriesTrailerYoutubeId hits /tv/<id>/videos path', () async {
      Uri? captured;
      when(() => dio.getUri<dynamic>(captureAny())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as Uri;
        return ok({'results': <Map<String, dynamic>>[]});
      });
      await client.seriesTrailerYoutubeId(1396);
      expect(captured!.path, contains('/tv/1396/videos'));
    });
  });
}
