import 'package:freezed_annotation/freezed_annotation.dart';

part 'epg_programme.freezed.dart';
part 'epg_programme.g.dart';

/// One scheduled programme on a channel (XMLTV `<programme>`).
@freezed
class EpgProgramme with _$EpgProgramme {
  const factory EpgProgramme({
    required String channelTvgId,
    required DateTime start,
    required DateTime stop,
    required String title,
    String? description,
    String? category,
  }) = _EpgProgramme;

  factory EpgProgramme.fromJson(Map<String, dynamic> json) =>
      _$EpgProgrammeFromJson(json);
}
