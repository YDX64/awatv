import 'package:freezed_annotation/freezed_annotation.dart';

part 'history_entry.freezed.dart';
part 'history_entry.g.dart';

/// Which surface produced the history entry.
enum HistoryKind { live, vod, series }

/// One row in the resume / continue-watching list.
@freezed
class HistoryEntry with _$HistoryEntry {
  const factory HistoryEntry({
    required String itemId,
    required HistoryKind kind,
    required Duration position,
    required Duration total,
    required DateTime watchedAt,
  }) = _HistoryEntry;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$HistoryEntryFromJson(json);
}
