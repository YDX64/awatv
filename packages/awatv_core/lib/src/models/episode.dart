import 'package:freezed_annotation/freezed_annotation.dart';

part 'episode.freezed.dart';
part 'episode.g.dart';

/// One episode inside a [SeriesItem].
@freezed
class Episode with _$Episode {
  const factory Episode({
    required String id,
    required String seriesId,
    required int season,
    required int number,
    required String title,
    required String streamUrl,
    String? plot,
    int? durationMin,
    String? posterUrl,
    String? containerExt,
  }) = _Episode;

  factory Episode.fromJson(Map<String, dynamic> json) =>
      _$EpisodeFromJson(json);
}
