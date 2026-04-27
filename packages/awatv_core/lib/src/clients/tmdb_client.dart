import 'package:awatv_core/src/models/tmdb_models.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Thin client over the TMDB v3 REST API.
///
/// Image base: `https://image.tmdb.org/t/p/`
/// Poster size used: `w500`
/// Backdrop size used: `original`
class TmdbClient {
  TmdbClient({
    required this.apiKey,
    Dio? dio,
    this.language = 'en-US',
  }) : _dio = dio ?? _defaultDio();

  static const String _base = 'https://api.themoviedb.org/3';
  static const String imageBase = 'https://image.tmdb.org/t/p/';
  static const String posterSize = 'w500';
  static const String backdropSize = 'original';

  final String apiKey;
  final String language;
  final Dio _dio;

  static final AwatvLogger _log = AwatvLogger(tag: 'TmdbClient');

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.json,
        ),
      );

  /// Build a fully-qualified poster URL from a TMDB `poster_path`.
  static String? posterUrl(String? path) =>
      (path == null || path.isEmpty) ? null : '$imageBase$posterSize$path';

  /// Build a fully-qualified backdrop URL from a TMDB `backdrop_path`.
  static String? backdropUrl(String? path) => (path == null || path.isEmpty)
      ? null
      : '$imageBase$backdropSize$path';

  /// Search a movie by title; pick the highest-popularity match. Optionally
  /// constrain by year.
  Future<MovieMetadata?> searchMovie(String title, {int? year}) async {
    if (title.trim().isEmpty) return null;
    final params = <String, String>{
      'api_key': apiKey,
      'language': language,
      'query': title,
      'include_adult': 'false',
      if (year != null) 'year': '$year',
    };
    final data = await _getJson(
      Uri.parse('$_base/search/movie').replace(queryParameters: params),
    );
    if (data is! Map) return null;

    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    final first = results.first;
    if (first is! Map) return null;
    final m = first.cast<String, dynamic>();
    final tmdbId = (m['id'] as num?)?.toInt();
    if (tmdbId == null) return null;

    final genreIds = (m['genre_ids'] as List?)?.cast<num>() ?? const [];
    final genres = genreIds.map(_movieGenreById).whereType<String>().toList();

    return MovieMetadata(
      tmdbId: tmdbId,
      title: (m['title'] as String?)?.trim() ?? title,
      originalTitle: (m['original_title'] as String?)?.trim() ?? title,
      overview: (m['overview'] as String?)?.trim() ?? '',
      genres: genres,
      posterPath: m['poster_path'] as String?,
      backdropPath: m['backdrop_path'] as String?,
      rating: (m['vote_average'] as num?)?.toDouble(),
      releaseDate: _parseDate(m['release_date'] as String?),
    );
  }

  /// Search a series by title; pick the highest-popularity match.
  Future<SeriesMetadata?> searchSeries(String title) async {
    if (title.trim().isEmpty) return null;
    final params = <String, String>{
      'api_key': apiKey,
      'language': language,
      'query': title,
      'include_adult': 'false',
    };
    final data = await _getJson(
      Uri.parse('$_base/search/tv').replace(queryParameters: params),
    );
    if (data is! Map) return null;

    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    final first = results.first;
    if (first is! Map) return null;
    final m = first.cast<String, dynamic>();
    final tmdbId = (m['id'] as num?)?.toInt();
    if (tmdbId == null) return null;

    final genreIds = (m['genre_ids'] as List?)?.cast<num>() ?? const [];
    final genres = genreIds.map(_tvGenreById).whereType<String>().toList();

    return SeriesMetadata(
      tmdbId: tmdbId,
      title: (m['name'] as String?)?.trim() ?? title,
      originalTitle: (m['original_name'] as String?)?.trim() ?? title,
      overview: (m['overview'] as String?)?.trim() ?? '',
      genres: genres,
      posterPath: m['poster_path'] as String?,
      backdropPath: m['backdrop_path'] as String?,
      rating: (m['vote_average'] as num?)?.toDouble(),
      releaseDate: _parseDate(m['first_air_date'] as String?),
    );
  }

  /// Trailer YouTube id for a TMDB movie. `null` if none.
  Future<String?> movieTrailerYoutubeId(int tmdbId) =>
      _trailerYoutubeId('movie', tmdbId);

  /// Trailer YouTube id for a TMDB series. `null` if none.
  Future<String?> seriesTrailerYoutubeId(int tmdbId) =>
      _trailerYoutubeId('tv', tmdbId);

  Future<String?> _trailerYoutubeId(String kind, int tmdbId) async {
    final params = <String, String>{
      'api_key': apiKey,
      'language': language,
    };
    final data = await _getJson(
      Uri.parse('$_base/$kind/$tmdbId/videos')
          .replace(queryParameters: params),
    );
    if (data is! Map) return null;
    final results = data['results'];
    if (results is! List) return null;

    Map<String, dynamic>? best;
    for (final r in results) {
      if (r is! Map) continue;
      final m = r.cast<String, dynamic>();
      if ((m['site'] as String?)?.toLowerCase() != 'youtube') continue;
      if ((m['type'] as String?)?.toLowerCase() == 'trailer') {
        best = m;
        if (m['official'] == true) break;
      }
      best ??= m;
    }
    return best?['key'] as String?;
  }

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final resp = await _dio.getUri<dynamic>(uri);
      if (resp.statusCode == null ||
          resp.statusCode! < 200 ||
          resp.statusCode! >= 300) {
        throw NetworkException(
          'TMDB returned status',
          statusCode: resp.statusCode,
          retryable: (resp.statusCode ?? 0) >= 500,
        );
      }
      return resp.data;
    } on DioException catch (e) {
      _log.warn('TMDB Dio error: ${e.message}');
      throw NetworkException(
        e.message ?? 'TMDB request failed',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }
  }

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// TMDB genre lookup tables (frozen at TMDB v3 spec).
  static String? _movieGenreById(num id) => _movieGenres[id.toInt()];
  static String? _tvGenreById(num id) => _tvGenres[id.toInt()];

  static const Map<int, String> _movieGenres = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Science Fiction',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
  };

  static const Map<int, String> _tvGenres = {
    10759: 'Action & Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    10762: 'Kids',
    9648: 'Mystery',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
    37: 'Western',
  };
}
