import 'package:freezed_annotation/freezed_annotation.dart';

part 'series_item.freezed.dart';
part 'series_item.g.dart';

/// A TV series header (no episodes — those live in [Episode]).
@freezed
class SeriesItem with _$SeriesItem {
  const factory SeriesItem({
    required String id,
    required String sourceId,
    required String title,
    @Default(<int>[]) List<int> seasons,
    @Default(<String>[]) List<String> genres,
    String? plot,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    int? year,
    int? tmdbId,
  }) = _SeriesItem;

  factory SeriesItem.fromJson(Map<String, dynamic> json) =>
      _$SeriesItemFromJson(json);
}
