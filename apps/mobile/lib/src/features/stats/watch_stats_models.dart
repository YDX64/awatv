import 'package:awatv_core/awatv_core.dart';
import 'package:flutter/foundation.dart';

/// Aggregate viewing summary derived from `HistoryService.recent()`.
///
/// All durations are computed from raw history rows — every row's
/// `position` field doubles as "watched-up-to-here" so the headline
/// metric is just the sum of every row's position (not the playback
/// total, which would double-count repeats).
@immutable
class WatchStatsSummary {
  const WatchStatsSummary({
    required this.totalAllTime,
    required this.totalLast7Days,
    required this.totalLast30Days,
    required this.byKind,
    required this.last7DaysBuckets,
    required this.topChannels,
    required this.topVod,
    required this.topSeries,
    required this.streakDays,
    required this.totalSessions,
  });

  /// Sum of every history row's `position`. We treat the latest
  /// position per item as authoritative because the HistoryService
  /// always overwrites the previous row for the same itemId.
  final Duration totalAllTime;

  /// Sum across rows whose `watchedAt` is newer than `now - 7d`.
  final Duration totalLast7Days;

  /// Sum across rows whose `watchedAt` is newer than `now - 30d`.
  final Duration totalLast30Days;

  /// Watched-time grouped by [HistoryKind] — used for the pie chart.
  final Map<HistoryKind, Duration> byKind;

  /// Watched seconds bucketed by day for the last 7 days. Index 0 is
  /// "today minus 6 days", index 6 is "today" — matches reading a
  /// time series left-to-right.
  final List<int> last7DaysBuckets;

  /// Top live channels by total watched time. Each entry carries the
  /// id, the resolved name (best-effort lookup), and the watched
  /// duration. Length capped at 5; free tier sees the first 3.
  final List<TopWatchEntry> topChannels;

  /// Top movies / VOD items.
  final List<TopWatchEntry> topVod;

  /// Top series.
  final List<TopWatchEntry> topSeries;

  /// Consecutive trailing days with at least one history entry. Today
  /// counts; gap days break the streak.
  final int streakDays;

  /// Number of distinct watched items considered. Useful header copy
  /// for "X farkli kanal / film izledin".
  final int totalSessions;

  /// Total of [byKind] values — kept as a getter so the UI doesn't
  /// have to know about the kind-by-kind decomposition.
  Duration get byKindTotal {
    var seconds = 0;
    for (final v in byKind.values) {
      seconds += v.inSeconds;
    }
    return Duration(seconds: seconds);
  }

  /// Empty summary — returned when `HistoryService.recent()` is empty.
  /// Keeping a singleton-style empty value means UI consumers don't
  /// need to special-case `null`.
  static WatchStatsSummary get empty => WatchStatsSummary(
        totalAllTime: Duration.zero,
        totalLast7Days: Duration.zero,
        totalLast30Days: Duration.zero,
        byKind: const <HistoryKind, Duration>{},
        last7DaysBuckets: const <int>[0, 0, 0, 0, 0, 0, 0],
        topChannels: const <TopWatchEntry>[],
        topVod: const <TopWatchEntry>[],
        topSeries: const <TopWatchEntry>[],
        streakDays: 0,
        totalSessions: 0,
      );
}

/// One row in the "Top 5" list.
@immutable
class TopWatchEntry {
  const TopWatchEntry({
    required this.id,
    required this.label,
    required this.kind,
    required this.watched,
    this.posterUrl,
    this.subtitle,
  });

  final String id;
  final String label;
  final HistoryKind kind;
  final Duration watched;

  /// Optional poster / channel logo URL — surfaced as a thumbnail in
  /// the list. Cold paths (no metadata available) just render an
  /// icon-coloured placeholder.
  final String? posterUrl;

  /// Optional secondary line — channel group, year, etc.
  final String? subtitle;
}
