// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late HistoryService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_hist_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    service = HistoryService(storage: storage);
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('HistoryService.markPosition', () {
    test('writes a HistoryEntry retrievable via storage.getHistory', () async {
      await service.markPosition(
        'channel-42',
        const Duration(seconds: 90),
        const Duration(seconds: 600),
      );
      final entry = await storage.getHistory('channel-42');
      expect(entry, isNotNull);
      expect(entry!.itemId, 'channel-42');
      expect(entry.position, const Duration(seconds: 90));
      expect(entry.total, const Duration(seconds: 600));
      expect(entry.kind, HistoryKind.live);
      // watchedAt is in UTC and recent.
      final age = DateTime.now().toUtc().difference(entry.watchedAt);
      expect(age.inMinutes, lessThan(2));
    });

    test('respects custom HistoryKind', () async {
      await service.markPosition(
        'movie-1',
        const Duration(seconds: 600),
        const Duration(seconds: 7200),
        kind: HistoryKind.vod,
      );
      final entry = await storage.getHistory('movie-1');
      expect(entry!.kind, HistoryKind.vod);
    });
  });

  group('HistoryService.recent', () {
    test('returns at most N entries, sorted desc by watchedAt', () async {
      // Insert 5 entries with explicit watchedAt timestamps via direct
      // storage.putHistory; service.markPosition uses now() and we want
      // deterministic ordering.
      for (var i = 0; i < 5; i++) {
        await storage.putHistory(
          HistoryEntry(
            itemId: 'item-$i',
            kind: HistoryKind.vod,
            position: const Duration(seconds: 60),
            total: const Duration(seconds: 600),
            watchedAt: DateTime.utc(2026, 4, 27, i),
          ),
        );
      }
      final recent = await service.recent(limit: 3);
      expect(recent, hasLength(3));
      expect(
        recent.map((e) => e.itemId).toList(),
        ['item-4', 'item-3', 'item-2'],
      );
    });

    test('default limit returns all entries when fewer than 50', () async {
      for (var i = 0; i < 4; i++) {
        await storage.putHistory(
          HistoryEntry(
            itemId: 'i$i',
            kind: HistoryKind.vod,
            position: const Duration(seconds: 1),
            total: const Duration(seconds: 100),
            watchedAt: DateTime.utc(2026, 4, 27, i),
          ),
        );
      }
      final recent = await service.recent();
      expect(recent, hasLength(4));
    });
  });

  group('HistoryService.resumeFor', () {
    test('returns null when no entry exists', () async {
      expect(await service.resumeFor('nope'), isNull);
    });

    test('returns position when watched > 30s and well before end', () async {
      await service.markPosition(
        'mid',
        const Duration(seconds: 90),
        const Duration(seconds: 600),
      );
      final got = await service.resumeFor('mid');
      expect(got, const Duration(seconds: 90));
    });

    test('returns null when watched < 30s (too early)', () async {
      await service.markPosition(
        'early',
        const Duration(seconds: 10),
        const Duration(seconds: 600),
      );
      expect(await service.resumeFor('early'), isNull);
    });

    test(
      'returns null when total - position < 30s (treated as fully watched)',
      () async {
        await service.markPosition(
          'almost-done',
          const Duration(seconds: 580),
          const Duration(seconds: 600),
        );
        expect(await service.resumeFor('almost-done'), isNull);
      },
    );

    test(
      'returns position when total is 0 (live channel with unknown duration)',
      () async {
        await service.markPosition(
          'live',
          const Duration(seconds: 120),
          Duration.zero,
        );
        expect(
          await service.resumeFor('live'),
          const Duration(seconds: 120),
        );
      },
    );

    test('boundary: exactly 30s in returns the position (not null)', () async {
      // Per current implementation: position.inSeconds < 30 → null.
      // 30 itself is not less than 30, so a resume should be returned.
      await service.markPosition(
        'edge',
        const Duration(seconds: 30),
        const Duration(seconds: 600),
      );
      expect(
        await service.resumeFor('edge'),
        const Duration(seconds: 30),
      );
    });
  });
}
