import 'package:freezed_annotation/freezed_annotation.dart';

part 'vod_item.freezed.dart';
part 'vod_item.g.dart';

/// On-demand movie.
@freezed
class VodItem with _$VodItem {
  const factory VodItem({
    required String id,
    required String sourceId,
    required String title,
    required String streamUrl,
    @Default(<String>[]) List<String> genres,
    int? year,
    String? plot,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    int? durationMin,
    String? containerExt,
    int? tmdbId,
  }) = _VodItem;

  factory VodItem.fromJson(Map<String, dynamic> json) =>
      _$VodItemFromJson(json);
}
