import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/sync/sync_envelope.dart';
import 'package:awatv_mobile/src/shared/sync/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late SyncQueue queue;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_sync_test_');
    Hive.init(tmp.path);
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    queue = SyncQueue(storage: storage);
    await queue.ensureOpen();
  });

  tearDown(() async {
    await queue.close();
    await Hive.close();
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // Best-effort temp cleanup; ignore on Windows file-locks.
      }
    }
  });

  group('SyncEnvelope JSON', () {
    test('FavoriteUpserted round-trips through toJson/fromJson', () {
      final original = FavoriteUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27, 10),
        itemId: 'src-1::ch-42',
        itemKind: FavoriteItemKind.live,
      );
      final restored = SyncEvent.fromJson(original.toJson());
      expect(restored, isA<FavoriteUpserted>());
      final fav = restored! as FavoriteUpserted;
      expect(fav.itemId, original.itemId);
      expect(fav.userId, original.userId);
      expect(fav.itemKind, FavoriteItemKind.live);
      expect(fav.updatedAt.toUtc(), original.updatedAt.toUtc());
    });

    test('HistoryUpserted preserves entry payload', () {
      final entry = HistoryEntry(
        itemId: 'src::vod-9',
        kind: HistoryKind.vod,
        position: const Duration(seconds: 600),
        total: const Duration(seconds: 5400),
        watchedAt: DateTime.utc(2026, 4, 27),
      );
      final original = HistoryUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27),
        entry: entry,
      );
      final restored = SyncEvent.fromJson(original.toJson())! as HistoryUpserted;
      expect(restored.entry.itemId, entry.itemId);
      expect(restored.entry.kind, HistoryKind.vod);
      expect(restored.entry.position, entry.position);
      expect(restored.entry.total, entry.total);
    });

    test('PlaylistSourceUpserted strips URL and credentials by design', () {
      final original = PlaylistSourceUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27),
        clientId: 'src-uuid-1',
        name: 'Living Room',
        kind: PlaylistKind.xtream,
        addedAt: DateTime.utc(2026, 4, 26),
        lastSyncAt: DateTime.utc(2026, 4, 27),
      );
      final json = original.toJson();
      // The wire must NEVER contain url / username / password.
      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('username'), isFalse);
      expect(json.containsKey('password'), isFalse);
      final restored =
          SyncEvent.fromJson(json)! as PlaylistSourceUpserted;
      expect(restored.clientId, original.clientId);
      expect(restored.kind, PlaylistKind.xtream);
      expect(restored.name, original.name);
    });

    test('Unknown kind decodes to null (forward-compat)', () {
      final raw = <String, dynamic>{
        'kind': 'future_event_v9',
        'user_id': 'u',
        'updated_at': '2099-01-01T00:00:00Z',
      };
      expect(SyncEvent.fromJson(raw), isNull);
    });
  });

  group('SyncQueue', () {
    test('enqueue persists envelope to Hive', () async {
      final event = FavoriteUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27, 12),
        itemId: 'src::ch-1',
        itemKind: FavoriteItemKind.live,
      );
      await queue.enqueue(event);
      expect(await queue.length(), 1);
    });

    test('drain calls push and removes the row on success', () async {
      final event = FavoriteUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27),
        itemId: 'src::ch-1',
        itemKind: FavoriteItemKind.live,
      );
      await queue.enqueue(event);

      final pushed = <SyncEvent>[];
      await queue.drain((SyncEvent e) async {
        pushed.add(e);
      });

      expect(pushed.length, 1);
      expect(pushed.first, isA<FavoriteUpserted>());
      expect(await queue.length(), 0);
    });

    test('retryable failure leaves row in queue with bumped attempts',
        () async {
      final event = HistoryUpserted(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27),
        entry: HistoryEntry(
          itemId: 'src::vod-1',
          kind: HistoryKind.vod,
          position: const Duration(seconds: 30),
          total: const Duration(seconds: 600),
          watchedAt: DateTime.utc(2026, 4, 27),
        ),
      );
      await queue.enqueue(event);

      var attempts = 0;
      await queue.drain((SyncEvent e) async {
        attempts++;
        throw StateError('network down');
      });

      // Drain stopped on first failure; one push attempted.
      expect(attempts, 1);
      // Row remains queued.
      expect(await queue.length(), 1);
    });

    test('non-retryable failure drops the row', () async {
      final event = FavoriteRemoved(
        userId: 'user-1',
        updatedAt: DateTime.utc(2026, 4, 27),
        itemId: 'src::ch-broken',
      );
      await queue.enqueue(event);

      await queue.drain((SyncEvent e) async {
        throw SyncQueue.nonRetryable(e, 'permanent 403');
      });

      // Non-retryable → row dropped immediately.
      expect(await queue.length(), 0);
    });

    test('FIFO order — first enqueued is first drained', () async {
      const user = 'user-1';
      final base = DateTime.utc(2026, 4, 27);
      final events = <FavoriteUpserted>[
        FavoriteUpserted(
          userId: user,
          updatedAt: base,
          itemId: 'src::ch-A',
          itemKind: FavoriteItemKind.live,
        ),
        FavoriteUpserted(
          userId: user,
          updatedAt: base.add(const Duration(seconds: 1)),
          itemId: 'src::ch-B',
          itemKind: FavoriteItemKind.live,
        ),
        FavoriteUpserted(
          userId: user,
          updatedAt: base.add(const Duration(seconds: 2)),
          itemId: 'src::ch-C',
          itemKind: FavoriteItemKind.live,
        ),
      ];
      for (final e in events) {
        await queue.enqueue(e);
        // Tiny delay so the per-microsecond key is monotonic in tests.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final order = <String>[];
      await queue.drain((SyncEvent e) async {
        if (e is FavoriteUpserted) order.add(e.itemId);
      });
      expect(order, equals(<String>['src::ch-A', 'src::ch-B', 'src::ch-C']));
    });
  });

  group('Cloud sync happy path (favourite toggle → outbound upsert)', () {
    test(
      'A favourite toggle is enqueued as a FavoriteUpserted event and '
      'arrives at the push handler intact',
      () async {
        // Simulate the engine's behaviour: when a favourite is added
        // locally the engine enqueues a FavoriteUpserted; the queue
        // drains by calling our push function. The test asserts the
        // outgoing payload is shaped correctly for the Supabase
        // `favorites` upsert.
        const itemId = 'src-uuid-1::channel-7';
        const userId = 'user-uuid-1';
        final now = DateTime.utc(2026, 4, 27, 14, 30);

        await queue.enqueue(FavoriteUpserted(
          userId: userId,
          updatedAt: now,
          itemId: itemId,
          itemKind: FavoriteItemKind.live,
        ));

        Map<String, dynamic>? captured;
        await queue.drain((SyncEvent event) async {
          // Equivalent of the engine's pushOne switch arm for favourites.
          if (event is FavoriteUpserted) {
            captured = <String, dynamic>{
              'user_id': event.userId,
              'item_id': event.itemId,
              'item_kind': event.itemKind.wire,
              'added_at': event.updatedAt.toUtc().toIso8601String(),
            };
          }
        });

        expect(captured, isNotNull);
        expect(captured!['user_id'], userId);
        expect(captured!['item_id'], itemId);
        expect(captured!['item_kind'], 'live');
        expect(captured!['added_at'], now.toIso8601String());
        // Critically, the wire payload only contains the four columns
        // that exist on the `favorites` table.
        expect(captured!.length, 4);
      },
    );
  });
}
