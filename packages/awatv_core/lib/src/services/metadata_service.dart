import 'package:awatv_core/src/clients/tmdb_client.dart';
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
}
