// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extra coverage for [WatchlistService] beyond the basic add/toggle
/// flow already covered by `watchlist_service_test.dart`. Focuses on:
///
///   * the reactive `watch()` and `watchAll()` streams
///   * sync `getOrNull` lookup
///   * id-only `ids()` snapshot
///   * `remove` idempotency
///   * boundary-case JSON roundtripping
void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late WatchlistService svc;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_watchlist_extra_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    svc = WatchlistService(storage: storage);
  });

  tearDown(() async {
    await svc.dispose();
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  WatchlistEntry mk(String id) => WatchlistEntry(
        itemId: id,
        kind: HistoryKind.vod,
        title: 'Title $id',
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      );

  group('ids', () {
    test('returns empty set when nothing has been added', () async {
      final ids = await svc.ids();
      expect(ids, isEmpty);
    });

    test('returns the keys of every added entry', () async {
      await svc.add(mk('a'));
      await svc.add(mk('b'));
      await svc.add(mk('c'));
      final ids = await svc.ids();
      expect(ids, <String>{'a', 'b', 'c'});
    });
  });

  group('remove', () {
    test('is a no-op for unknown id', () async {
      await svc.remove('does-not-exist');
      expect(await svc.contains('does-not-exist'), isFalse);
    });

    test('removes existing entry', () async {
      await svc.add(mk('z'));
      expect(await svc.contains('z'), isTrue);
      await svc.remove('z');
      expect(await svc.contains('z'), isFalse);
    });

    test('removing one entry leaves others untouched', () async {
      await svc.add(mk('a'));
      await svc.add(mk('b'));
      await svc.remove('a');
      expect(await svc.contains('a'), isFalse);
      expect(await svc.contains('b'), isTrue);
    });
  });

  group('getOrNull', () {
    test('returns null for absent entry', () async {
      expect(svc.getOrNull('absent'), isNull);
    });

    test('returns the entry after add', () async {
      await svc.add(mk('synchronous'));
      final entry = svc.getOrNull('synchronous');
      expect(entry, isNotNull);
      expect(entry!.itemId, 'synchronous');
    });
  });

  group('JSON roundtrip', () {
    test('preserves all fields', () async {
      final original = WatchlistEntry(
        itemId: 'roundtrip',
        kind: HistoryKind.series,
        title: 'Türkçe başlık',
        posterUrl: 'http://poster.test/p.jpg',
        year: 2024,
        addedAt: DateTime.utc(2026, 1, 15, 10, 30),
      );
      await svc.add(original);
      final all = await svc.all();
      expect(all, hasLength(1));
      final round = all.first;
      expect(round.itemId, original.itemId);
      expect(round.kind, original.kind);
      expect(round.title, original.title);
      expect(round.posterUrl, original.posterUrl);
      expect(round.year, original.year);
      expect(
        round.addedAt.millisecondsSinceEpoch,
        original.addedAt.millisecondsSinceEpoch,
      );
    });

    test('handles missing year gracefully', () async {
      final e = WatchlistEntry(
        itemId: 'no-year',
        kind: HistoryKind.vod,
        title: 'No year',
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      );
      await svc.add(e);
      final stored = (await svc.all()).single;
      expect(stored.year, isNull);
    });
  });

  group('watch', () {
    test('emits the live id set after add', () async {
      // Subscribe before the write.
      final stream = svc.watch();
      final firstFuture = stream.first;
      await svc.add(mk('streaming-1'));
      final first = await firstFuture.timeout(const Duration(seconds: 2));
      expect(first, contains('streaming-1'));
    });
  });

  group('watchAll', () {
    test('emits filtered list for movies-only filter', () async {
      // Pre-seed.
      await svc.add(mk('movie-a'));
      await svc.add(WatchlistEntry(
        itemId: 'series-a',
        kind: HistoryKind.series,
        title: 'Series A',
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      ));
      // Now subscribe with the movie filter.
      final stream = svc.watchAll(kind: HistoryKind.vod);
      final first = await stream.first.timeout(const Duration(seconds: 2));
      expect(first.map((WatchlistEntry e) => e.itemId), <String>['movie-a']);
    });
  });

  group('all() filter combinations', () {
    test('returns all entries when no kind filter', () async {
      await svc.add(mk('m1'));
      await svc.add(WatchlistEntry(
        itemId: 's1',
        kind: HistoryKind.series,
        title: 'S1',
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      ));
      final all = await svc.all();
      expect(all, hasLength(2));
    });

    test('returns empty when kind filter has no matches', () async {
      await svc.add(mk('m1'));
      final series = await svc.all(kind: HistoryKind.series);
      expect(series, isEmpty);
    });
  });
}
