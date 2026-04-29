import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late WatchlistService svc;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_watchlist_');
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

  WatchlistEntry vod(String id, {String title = 'Some film'}) =>
      WatchlistEntry(
        itemId: id,
        kind: HistoryKind.vod,
        title: title,
        posterUrl: 'http://example.test/$id.jpg',
        year: 2024,
        addedAt: DateTime.now().toUtc(),
      );

  WatchlistEntry series(String id, {String title = 'Some series'}) =>
      WatchlistEntry(
        itemId: id,
        kind: HistoryKind.series,
        title: title,
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      );

  test('add then contains', () async {
    await svc.add(vod('movie-1'));
    expect(await svc.contains('movie-1'), isTrue);
  });

  test('toggle returns true when adding, false when removing', () async {
    final added = await svc.toggle(vod('m1'));
    expect(added, isTrue);
    final removed = await svc.toggle(vod('m1'));
    expect(removed, isFalse);
    expect(await svc.contains('m1'), isFalse);
  });

  test('rejects live kind', () async {
    await svc.add(
      WatchlistEntry(
        itemId: 'channel-1',
        kind: HistoryKind.live,
        title: 'TRT 1',
        posterUrl: null,
        addedAt: DateTime.now().toUtc(),
      ),
    );
    expect(await svc.contains('channel-1'), isFalse);
  });

  test('all() returns newest-first', () async {
    await svc.add(vod('a'));
    // Sleep 5ms so the timestamp differs.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await svc.add(vod('b'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await svc.add(series('c'));
    final all = await svc.all();
    expect(all.map((WatchlistEntry e) => e.itemId).toList(),
        <String>['c', 'b', 'a']);
  });

  test('all(kind:) filters by HistoryKind', () async {
    await svc.add(vod('v1'));
    await svc.add(series('s1'));
    final vodOnly = await svc.all(kind: HistoryKind.vod);
    final seriesOnly = await svc.all(kind: HistoryKind.series);
    expect(vodOnly, hasLength(1));
    expect(vodOnly.first.itemId, 'v1');
    expect(seriesOnly, hasLength(1));
    expect(seriesOnly.first.itemId, 's1');
  });

  test('re-add preserves original addedAt', () async {
    final first = vod('m1');
    await svc.add(first);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final updated = WatchlistEntry(
      itemId: 'm1',
      kind: HistoryKind.vod,
      title: 'New title',
      posterUrl: 'http://x.test/p.jpg',
      year: 2025,
      addedAt: DateTime.now().toUtc(),
    );
    await svc.add(updated);
    final stored = (await svc.all()).single;
    expect(stored.title, 'New title');
    expect(
      stored.addedAt.millisecondsSinceEpoch,
      first.addedAt.millisecondsSinceEpoch,
    );
  });
}
