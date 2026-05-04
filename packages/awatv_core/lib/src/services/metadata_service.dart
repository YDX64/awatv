import 'package:awatv_core/src/clients/tmdb_client.dart';
import 'package:awatv_core/src/models/tmdb_credits.dart';
import 'package:awatv_core/src/models/tmdb_models.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';

/// Cached wrapper around [TmdbClient]. Uses [AwatvStorage]'s metadata box
/// keyed by `tmdb:movie:$title:$year` / `tmdb:tv:$title` with a 30-day TTL.
class MetadataService {
  MetadataService({
    required AwatvStorage storage,
    TmdbClient? tmdb,
    Duration cacheTtl = const Duration(days: 30),
  })  : _tmdb = tmdb,
        _storage = storage,
        _ttl = cacheTtl;

  /// Nullable: when the user has no TMDB API key configured we skip the
  /// network call entirely and only serve the on-disk cache. Callers can
  /// still call all methods — they just receive `null` more often.
  final TmdbClient? _tmdb;
  final AwatvStorage _storage;
  final Duration _ttl;

  static final AwatvLogger _log = AwatvLogger(tag: 'MetadataService');

  Future<MovieMetadata?> movieByTitle(String title, {int? year}) async {
    final key = 'tmdb:movie:${title.toLowerCase()}:${year ?? ""}';
    final cached = await _storage.getMetadataJson(key, ttl: _ttl);
    if (cached != null) {
      try {
        return MovieMetadata.fromJson(cached);
      } on Exception catch (e) {
        _log.warn('cache decode failed for $key: $e');
      }
    }

    final tmdb = _tmdb;
    if (tmdb == null) return null;
    final fresh = await tmdb.searchMovie(title, year: year);
    if (fresh != null) {
      await _storage.putMetadataJson(key, fresh.toJson());
    }
    return fresh;
  }

  Future<SeriesMetadata?> seriesByTitle(String title) async {
    final key = 'tmdb:tv:${title.toLowerCase()}';
    final cached = await _storage.getMetadataJson(key, ttl: _ttl);
    if (cached != null) {
      try {
        return SeriesMetadata.fromJson(cached);
      } on Exception catch (e) {
        _log.warn('cache decode failed for $key: $e');
      }
    }

    final tmdb = _tmdb;
    if (tmdb == null) return null;
    final fresh = await tmdb.searchSeries(title);
    if (fresh != null) {
      await _storage.putMetadataJson(key, fresh.toJson());
    }
    return fresh;
  }

  Future<String?> trailerYoutubeId(int tmdbId, MediaType kind) async {
    final tmdb = _tmdb;
    if (tmdb == null) return null;
    return kind == MediaType.movie
        ? tmdb.movieTrailerYoutubeId(tmdbId)
        : tmdb.seriesTrailerYoutubeId(tmdbId);
  }

  /// Cached `/credits` lookup. Credits change rarely so we keep them on
  /// disk for 24 h regardless of the broader [_ttl]. Returns
  /// [TmdbCredits.empty] when the user has no TMDB key configured (so
  /// the UI can hide the cast row without checking the env directly).
  Future<TmdbCredits> credits(
    int tmdbId, {
    MediaType kind = MediaType.movie,
  }) async {
    final isMovie = kind == MediaType.movie;
    final cacheKey = 'tmdb:credits:${isMovie ? "movie" : "tv"}:$tmdbId';
    const cacheTtl = Duration(hours: 24);

    final cached = await _storage.getMetadataJson(cacheKey, ttl: cacheTtl);
    if (cached != null) {
      try {
        return TmdbCredits.fromJson(cached);
      } on Object catch (e) {
        _log.warn('credits cache decode failed for $cacheKey: $e');
      }
    }

    final tmdb = _tmdb;
    if (tmdb == null) return TmdbCredits.empty;

    try {
      final fresh = await tmdb.credits(tmdbId, isMovie: isMovie);
      await _storage.putMetadataJson(cacheKey, fresh.toJson());
      return fresh;
    } on Object catch (e) {
      _log.warn('credits fetch failed for $cacheKey: $e');
      return TmdbCredits.empty;
    }
  }

  /// `/similar` — returns up to [limit] tmdb ids of titles TMDB considers
  /// similar to [tmdbId]. Cached for 24 h. Returns an empty list when the
  /// TMDB key isn't configured so callers can fall through to local-only
  /// genre-overlap scoring.
  Future<List<int>> similarTmdbIds(
    int tmdbId, {
    MediaType kind = MediaType.movie,
    int limit = 10,
  }) async {
    final isMovie = kind == MediaType.movie;
    final cacheKey =
        'tmdb:similar:${isMovie ? "movie" : "tv"}:$tmdbId:l$limit';
    const cacheTtl = Duration(hours: 24);

    final cached = await _storage.getMetadataJson(cacheKey, ttl: cacheTtl);
    if (cached != null) {
      try {
        final raw = cached['ids'];
        if (raw is List) {
          final out = <int>[];
          for (final e in raw) {
            if (e is num) out.add(e.toInt());
          }
          return out;
        }
      } on Object catch (e) {
        _log.warn('similar cache decode failed for $cacheKey: $e');
      }
    }

    final tmdb = _tmdb;
    if (tmdb == null) return const <int>[];

    try {
      final ids =
          await tmdb.similarTmdbIds(tmdbId, isMovie: isMovie, limit: limit);
      await _storage.putMetadataJson(cacheKey, <String, dynamic>{'ids': ids});
      return ids;
    } on Object catch (e) {
      _log.warn('similar fetch failed for $cacheKey: $e');
      return const <int>[];
    }
  }
}
