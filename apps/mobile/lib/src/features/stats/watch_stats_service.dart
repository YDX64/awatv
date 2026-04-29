import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/stats/watch_stats_models.dart';

/// Pure aggregation layer over [HistoryService] + the merged catalog
/// providers. Given the raw history rows and three lookup callbacks,
/// produces a [WatchStatsSummary] that the screen renders directly.
///
/// No network, no Hive, no async work past the initial history read —
/// all heavy lifting is in-memory list folding so a 1000-row history
/// completes well under one frame on a low-end Android device.
class WatchStatsService {
  WatchStatsService({
    required HistoryService history,
    required Future<Channel?> Function(String id) channelLookup,
    required Future<VodItem?> Function(String id) vodLookup,
    required Future<SeriesItem?> Function(String id) seriesLookup,
  })  : _history = history,
        _channelLookup = channelLookup,
        _vodLookup = vodLookup,
        _seriesLookup = seriesLookup;

  final HistoryService _history;
  final Future<Channel?> Function(String id) _channelLookup;
  final Future<VodItem?> Function(String id) _vodLookup;
  final Future<SeriesItem?> Function(String id) _seriesLookup;

  /// Pull the most recent [limit] history rows (default 500 — we
  /// want enough headroom for "all-time" totals on heavy users) and
  /// fold them into a [WatchStatsSummary]. Lookups happen in parallel
  /// to keep the screen latency in the 50–150 ms range even when the
  /// catalog has thousands of items.
  Future<WatchStatsSummary> compute({int limit = 500}) async {
    final rows = await _history.recent(limit: limit);
    if (rows.isEmpty) return WatchStatsSummary.empty;

    final now = DateTime.now().toUtc();
    final cutoff7 = now.subtract(const Duration(days: 7));
    final cutoff30 = now.subtract(const Duration(days: 30));

    var totalAll = Duration.zero;
    var total7 = Duration.zero;
    var total30 = Duration.zero;
    final byKind = <HistoryKind, Duration>{};
    final daySeconds = List<int>.filled(7, 0);
    final perItem = <_PerItemBucket>[];
    final activeDays = <DateTime>{};

    // Index of itemId → bucket so we can fold repeated rows for the
    // same channel / movie. The HistoryService already overwrites
    // older rows for the same itemId, so in practice each itemId
    // appears at most once — but the indexer is cheap and keeps the
    // future-proof against a service tweak.
    final indexById = <String, _PerItemBucket>{};

    for (final row in rows) {
      final pos = row.position;
      if (pos.inSeconds <= 0) continue;

      totalAll += pos;
      byKind[row.kind] = (byKind[row.kind] ?? Duration.zero) + pos;
      activeDays.add(_dayKey(row.watchedAt));

      if (row.watchedAt.isAfter(cutoff7)) total7 += pos;
      if (row.watchedAt.isAfter(cutoff30)) total30 += pos;

      // 7-day bar chart bucketing. Index 6 is today; index 0 is the
      // morning of `today - 6`. Anything older than 7 days is dropped.
      final bucket = _bucketIndexFor(row.watchedAt, now);
      if (bucket != null) {
        daySeconds[bucket] += pos.inSeconds;
      }

      final existing = indexById[row.itemId];
      if (existing == null) {
        final bucketRow = _PerItemBucket(
          itemId: row.itemId,
          kind: row.kind,
          watched: pos,
        );
        indexById[row.itemId] = bucketRow;
        perItem.add(bucketRow);
      } else {
        existing.watched += pos;
      }
    }

    // Top-N enrichment — only the leaders deserve a metadata lookup,
    // so we pre-rank by watched time before resolving names + posters.
    final topChannelsRaw = perItem
        .where((b) => b.kind == HistoryKind.live)
        .toList()
      ..sort((a, b) => b.watched.compareTo(a.watched));
    final topVodRaw = perItem
        .where((b) => b.kind == HistoryKind.vod)
        .toList()
      ..sort((a, b) => b.watched.compareTo(a.watched));
    final topSeriesRaw = perItem
        .where((b) => b.kind == HistoryKind.series)
        .toList()
      ..sort((a, b) => b.watched.compareTo(a.watched));

    final topChannels = await _resolveChannels(topChannelsRaw.take(5));
    final topVod = await _resolveVod(topVodRaw.take(5));
    final topSeries = await _resolveSeries(topSeriesRaw.take(5));

    return WatchStatsSummary(
      totalAllTime: totalAll,
      totalLast7Days: total7,
      totalLast30Days: total30,
      byKind: byKind,
      last7DaysBuckets: daySeconds,
      topChannels: topChannels,
      topVod: topVod,
      topSeries: topSeries,
      streakDays: _computeStreak(activeDays, now),
      totalSessions: perItem.length,
    );
  }

  /// Walk back from today and count consecutive days with activity.
  /// `activeDays` is the set of UTC midnights observed in the rows;
  /// the streak ends at the first gap.
  int _computeStreak(Set<DateTime> activeDays, DateTime now) {
    if (activeDays.isEmpty) return 0;
    var streak = 0;
    var cursor = _dayKey(now);
    while (activeDays.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Drop the time-of-day so two [DateTime]s on the same UTC date
  /// hash to the same key.
  DateTime _dayKey(DateTime dt) {
    final utc = dt.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// Returns the 7-day bar-chart bucket index a [DateTime] should
  /// land in (0..6, where 6 is today), or `null` if the row is older
  /// than 7 days.
  int? _bucketIndexFor(DateTime watchedAt, DateTime now) {
    final today = _dayKey(now);
    final day = _dayKey(watchedAt);
    final delta = today.difference(day).inDays;
    if (delta < 0 || delta > 6) return null;
    return 6 - delta;
  }

  Future<List<TopWatchEntry>> _resolveChannels(
    Iterable<_PerItemBucket> raws,
  ) async {
    final futures =
        raws.map((b) => _channelLookup(b.itemId)).toList(growable: false);
    final lookups = await Future.wait(futures);
    final out = <TopWatchEntry>[];
    var i = 0;
    for (final raw in raws) {
      final c = lookups[i++];
      out.add(
        TopWatchEntry(
          id: raw.itemId,
          label: c?.name ?? 'Kanal',
          kind: HistoryKind.live,
          watched: raw.watched,
          posterUrl: c?.logoUrl,
          subtitle: c?.groups.isNotEmpty == true ? c!.groups.first : null,
        ),
      );
    }
    return out;
  }

  Future<List<TopWatchEntry>> _resolveVod(
    Iterable<_PerItemBucket> raws,
  ) async {
    final futures =
        raws.map((b) => _vodLookup(b.itemId)).toList(growable: false);
    final lookups = await Future.wait(futures);
    final out = <TopWatchEntry>[];
    var i = 0;
    for (final raw in raws) {
      final v = lookups[i++];
      out.add(
        TopWatchEntry(
          id: raw.itemId,
          label: v?.title ?? 'Film',
          kind: HistoryKind.vod,
          watched: raw.watched,
          posterUrl: v?.posterUrl,
          subtitle: v?.year?.toString(),
        ),
      );
    }
    return out;
  }

  Future<List<TopWatchEntry>> _resolveSeries(
    Iterable<_PerItemBucket> raws,
  ) async {
    final futures =
        raws.map((b) => _seriesLookup(b.itemId)).toList(growable: false);
    final lookups = await Future.wait(futures);
    final out = <TopWatchEntry>[];
    var i = 0;
    for (final raw in raws) {
      final s = lookups[i++];
      out.add(
        TopWatchEntry(
          id: raw.itemId,
          label: s?.title ?? 'Dizi',
          kind: HistoryKind.series,
          watched: raw.watched,
          posterUrl: s?.posterUrl,
          subtitle: s?.year?.toString(),
        ),
      );
    }
    return out;
  }
}

class _PerItemBucket {
  _PerItemBucket({
    required this.itemId,
    required this.kind,
    required this.watched,
  });

  final String itemId;
  final HistoryKind kind;
  Duration watched;
}
