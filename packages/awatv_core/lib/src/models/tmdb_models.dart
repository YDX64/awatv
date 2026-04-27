import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_models.freezed.dart';
part 'tmdb_models.g.dart';

/// Whether a TMDB lookup is for a movie or a series.
enum MediaType { movie, series }

/// Movie metadata returned from TMDB.
@freezed
class MovieMetadata with _$MovieMetadata {
  const factory MovieMetadata({
    required int tmdbId,
    required String title,
    required String originalTitle,
    required String overview,
    @Default(<String>[]) List<String> genres,
    String? posterPath,
    String? backdropPath,
    double? rating,
    DateTime? releaseDate,
    String? trailerYoutubeId,
  }) = _MovieMetadata;

  factory MovieMetadata.fromJson(Map<String, dynamic> json) =>
      _$MovieMetadataFromJson(json);
}

/// Series metadata returned from TMDB.
@freezed
class SeriesMetadata with _$SeriesMetadata {
  const factory SeriesMetadata({
    required int tmdbId,
    required String title,
    required String originalTitle,
    required String overview,
    @Default(<String>[]) List<String> genres,
    String? posterPath,
    String? backdropPath,
    double? rating,
    DateTime? releaseDate,
    String? trailerYoutubeId,
  }) = _SeriesMetadata;

  factory SeriesMetadata.fromJson(Map<String, dynamic> json) =>
      _$SeriesMetadataFromJson(json);
}
