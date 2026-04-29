// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  late AwatvStorage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_storage_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('AwatvStorage sources', () {
    test('putSource then getSource round-trips', () async {
      final src = PlaylistSource(
        id: 'src-1',
        name: 'My Provider',
        kind: PlaylistKind.m3u,
        url: 'http://example.com/list.m3u',
        addedAt: DateTime.utc(2026, 4, 27, 8),
      );
      await storage.putSource(src);

      final got = await storage.getSource('src-1');
      expect(got, isNotNull);
      expect(got!.id, 'src-1');
      expect(got.name, 'My Provider');
      expect(got.kind, PlaylistKind.m3u);
      expect(got.url, 'http://example.com/list.m3u');
      expect(got.addedAt, DateTime.utc(2026, 4, 27, 8));
    });

    test('getSource returns null for unknown id', () async {
      final got = await storage.getSource('does-not-exist');
      expect(got, isNull);
    });

    test('listSources returns sources ordered by addedAt ascending', () async {
      final a = PlaylistSource(
        id: 'a',
        name: 'A',
        kind: PlaylistKind.m3u,
        url: 'http://a/',
        addedAt: DateTime.utc(2026, 4),
      );
      final b = PlaylistSource(
        id: 'b',
        name: 'B',
        kind: PlaylistKind.m3u,
        url: 'http://b/',
        addedAt: DateTime.utc(2026, 4, 2),
      );
      final c = PlaylistSource(
        id: 'c',
        name: 'C',
        kind: PlaylistKind.m3u,
        url: 'http://c/',
        addedAt: DateTime.utc(2026, 3, 15),
      );

      // Insert out of order.
      await storage.putSource(b);
      await storage.putSource(a);
      await storage.putSource(c);

      final all = await storage.listSources();
      expect(all.map((s) => s.id).toList(), ['c', 'a', 'b']);
    });

    test('deleteSource removes source AND channels/vod/series boxes', () async {
      const sourceId = 'src-del';
      final src = PlaylistSource(
        id: sourceId,
        name: 'doomed',
        kind: PlaylistKind.xtream,
        url: 'http://x',
        addedAt: DateTime.utc(2026, 4, 27),
      );
      await storage.putSource(src);
      await storage.putChannels(sourceId, [
        const Channel(
          id: '$sourceId::c1',
          sourceId: sourceId,
          name: 'C1',
          streamUrl: 'http://x/1.ts',
          kind: ChannelKind.live,
        ),
      ]);
      await storage.putVod(sourceId, [
        const VodItem(
          id: '$sourceId::vod::1',
          sourceId: sourceId,
          title: 'Movie',
          streamUrl: 'http://x/m.mp4',
        ),
      ]);
      await storage.putSeries(sourceId, [
        const SeriesItem(
          id: '$sourceId::series::1',
          sourceId: sourceId,
          title: 'Show',
        ),
      ]);

      // Sanity: data is there.
      expect(await storage.listChannels(sourceId), hasLength(1));
      expect(await storage.listVod(sourceId), hasLength(1));
      expect(await storage.listSeries(sourceId), hasLength(1));

      await storage.deleteSource(sourceId);

      expect(await storage.getSource(sourceId), isNull);
      // Re-listing reopens an empty box.
      expect(await storage.listChannels(sourceId), isEmpty);
      expect(await storage.listVod(sourceId), isEmpty);
      expect(await storage.listSeries(sourceId), isEmpty);
    });
  });

  group('AwatvStorage channels', () {
    test('putChannels then listChannels round-trips', () async {
      const sourceId = 'src-ch';
      final channels = [
        const Channel(
          id: '$sourceId::a',
          sourceId: sourceId,
          name: 'Alpha',
          streamUrl: 'http://s/a.ts',
          kind: ChannelKind.live,
          tvgId: 'a.tv',
          logoUrl: 'http://l/a.png',
          groups: ['News'],
        ),
        const Channel(
          id: '$sourceId::b',
          sourceId: sourceId,
          name: 'Beta',
          streamUrl: 'http://s/b.ts',
          kind: ChannelKind.vod,
        ),
      ];
      await storage.putChannels(sourceId, channels);

      final loaded = await storage.listChannels(sourceId);
      expect(loaded, hasLength(2));
      final byId = {for (final c in loaded) c.id: c};
      expect(byId['$sourceId::a']!.name, 'Alpha');
      expect(byId['$sourceId::a']!.tvgId, 'a.tv');
      expect(byId['$sourceId::a']!.logoUrl, 'http://l/a.png');
      expect(byId['$sourceId::a']!.groups, ['News']);
      expect(byId['$sourceId::b']!.kind, ChannelKind.vod);
    });

    test('putChannels replaces previous content (clear semantics)', () async {
      const sourceId = 'src-replace';
      await storage.putChannels(sourceId, [
        const Channel(
          id: '$sourceId::old',
          sourceId: sourceId,
          name: 'Old',
          streamUrl: 'http://x/old.ts',
          kind: ChannelKind.live,
        ),
      ]);
      await storage.putChannels(sourceId, [
        const Channel(
          id: '$sourceId::new',
          sourceId: sourceId,
          name: 'New',
          streamUrl: 'http://x/new.ts',
          kind: ChannelKind.live,
        ),
      ]);
      final list = await storage.listChannels(sourceId);
      expect(list, hasLength(1));
      expect(list.single.name, 'New');
    });

    test('watchChannels emits initial value then updates', () async {
      const sourceId = 'src-watch';
      await storage.putChannels(sourceId, [
        const Channel(
          id: '$sourceId::1',
          sourceId: sourceId,
          name: 'one',
          streamUrl: 'http://x/1.ts',
          kind: ChannelKind.live,
        ),
      ]);

      final stream = storage.watchChannels(sourceId);
      final emissions = <int>[];
      final sub = stream.listen((cs) => emissions.add(cs.length));

      // Allow initial emission to flush.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, 1);

      // Mutate; expect a new emission.
      await storage.putChannels(sourceId, [
        const Channel(
          id: '$sourceId::1',
          sourceId: sourceId,
          name: 'one',
          streamUrl: 'http://x/1.ts',
          kind: ChannelKind.live,
        ),
        const Channel(
          id: '$sourceId::2',
          sourceId: sourceId,
          name: 'two',
          streamUrl: 'http://x/2.ts',
          kind: ChannelKind.live,
        ),
      ]);

      // Box.watch fires one event per put — give it time.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, 2);

      await sub.cancel();
    });
  });

  group('AwatvStorage metadata cache', () {
    test('putMetadataJson then getMetadataJson round-trips', () async {
      await storage.putMetadataJson('k1', {'a': 1, 'b': 'two'});
      final got = await storage.getMetadataJson('k1');
      expect(got, isNotNull);
      expect(got!['a'], 1);
      expect(got['b'], 'two');
    });

    test('getMetadataJson returns null when entry is older than TTL', () async {
      // Manually craft a wrapper with an old savedAt to simulate stale cache.
      final box = Hive.box<String>(AwatvStorage.boxMetadata);
      // 2026-01-01 is months earlier than today's test date (2026-04-27),
      // so it's well past the default 30-day TTL.
      const oldSavedAt = '2026-01-01T00:00:00.000Z';
      await box.put(
        'stale-key',
        '{"savedAt":"$oldSavedAt","value":{"a":1}}',
      );
      final got = await storage.getMetadataJson('stale-key');
      expect(got, isNull);
    });

    test('getMetadataJson respects custom TTL', () async {
      await storage.putMetadataJson('fresh', {'fresh': true});
      // Sleep a tick so DateTime.now() definitely advances past the savedAt
      // timestamp, then ask for any TTL that's tiny.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final got = await storage.getMetadataJson(
        'fresh',
        ttl: const Duration(microseconds: 1),
      );
      expect(got, isNull);
    });

    test('getMetadataJson returns null for unknown key', () async {
      expect(await storage.getMetadataJson('nope'), isNull);
    });

    test('getMetadataJson returns null on corrupted JSON', () async {
      final box = Hive.box<String>(AwatvStorage.boxMetadata);
      await box.put('bad', '!!!not json!!!');
      expect(await storage.getMetadataJson('bad'), isNull);
    });
  });

  group('AwatvStorage history', () {
    test('putHistory + listHistory orders most recent first', () async {
      final older = HistoryEntry(
        itemId: 'a',
        kind: HistoryKind.vod,
        position: const Duration(minutes: 10),
        total: const Duration(minutes: 100),
        watchedAt: DateTime.utc(2026, 4),
      );
      final newer = HistoryEntry(
        itemId: 'b',
        kind: HistoryKind.vod,
        position: const Duration(minutes: 20),
        total: const Duration(minutes: 100),
        watchedAt: DateTime.utc(2026, 4, 27),
      );
      await storage.putHistory(older);
      await storage.putHistory(newer);

      final list = await storage.listHistory();
      expect(list, hasLength(2));
      expect(list.first.itemId, 'b');
      expect(list[1].itemId, 'a');
    });

    test('listHistory respects limit argument', () async {
      for (var i = 0; i < 5; i++) {
        await storage.putHistory(
          HistoryEntry(
            itemId: 'h$i',
            kind: HistoryKind.vod,
            position: Duration(minutes: i),
            total: const Duration(minutes: 100),
            watchedAt: DateTime.utc(2026, 4, 27, i),
          ),
        );
      }
      final limited = await storage.listHistory(limit: 3);
      expect(limited, hasLength(3));
      // Newest three by watchedAt → 4, 3, 2.
      expect(limited.map((e) => e.itemId), ['h4', 'h3', 'h2']);
    });

    test('getHistory returns null for unknown id', () async {
      expect(await storage.getHistory('zzz'), isNull);
    });
  });

  group('AwatvStorage EPG', () {
    test('putEpg + getEpg round-trips a list of programmes', () async {
      const tvgId = 'bbcone.uk';
      final progs = [
        EpgProgramme(
          channelTvgId: tvgId,
          start: DateTime.utc(2026, 4, 27, 12),
          stop: DateTime.utc(2026, 4, 27, 13),
          title: 'News',
          description: 'd',
        ),
      ];
      await storage.putEpg(tvgId, progs);
      final got = await storage.getEpg(tvgId);
      expect(got, hasLength(1));
      expect(got.first.title, 'News');
      expect(got.first.description, 'd');
    });

    test('getEpg returns empty list for unknown channel', () async {
      expect(await storage.getEpg('unknown.tv'), isEmpty);
    });
  });

  group('AwatvStorage favorites box', () {
    test('favoritesBox is a Box<int>', () {
      expect(storage.favoritesBox, isA<Box<int>>());
    });

    test('favoritesBox round-trips int values', () async {
      await storage.favoritesBox.put('chan-1', 1);
      expect(storage.favoritesBox.containsKey('chan-1'), isTrue);
      expect(storage.favoritesBox.get('chan-1'), 1);
    });
  });

  group('AwatvStorage prefs box', () {
    test('prefsBox is a Box<dynamic>', () {
      expect(storage.prefsBox, isA<Box<dynamic>>());
    });

    test('prefsBox stores arbitrary values', () async {
      await storage.prefsBox.put('theme', 'dark');
      await storage.prefsBox.put('count', 7);
      expect(storage.prefsBox.get('theme'), 'dark');
      expect(storage.prefsBox.get('count'), 7);
    });
  });

  group('AwatvStorage init guard', () {
    test('listSources before init() throws StorageException', () async {
      // Use a fresh, uninitialised instance.
      final fresh = AwatvStorage();
      await expectLater(
        fresh.listSources(),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('AwatvStorage singleton', () {
    test('AwatvStorage.instance returns same instance across calls', () {
      final a = AwatvStorage.instance;
      final b = AwatvStorage.instance;
      expect(identical(a, b), isTrue);
    });
  });

  group('AwatvStorage recordings', () {
    test('putRecording then listRecordings round-trips', () async {
      final t = RecordingTask(
        id: 'rec-1',
        channelId: 'src::ch',
        channelName: 'Channel',
        streamUrl: 'http://example/live.ts',
        status: RecordingStatus.scheduled,
        createdAt: DateTime.utc(2026, 4, 28),
      );
      await storage.putRecording(t);
      final list = await storage.listRecordings();
      expect(list, hasLength(1));
      expect(list.first.id, 'rec-1');
      expect(list.first.status, RecordingStatus.scheduled);
    });

    test('deleteRecording removes the entry', () async {
      final t = RecordingTask(
        id: 'rec-2',
        channelId: 'src::ch',
        channelName: 'Channel',
        streamUrl: 'http://example/live.ts',
        status: RecordingStatus.completed,
        createdAt: DateTime.utc(2026, 4, 28),
      );
      await storage.putRecording(t);
      await storage.deleteRecording('rec-2');
      final list = await storage.listRecordings();
      expect(list, isEmpty);
    });
  });

  group('AwatvStorage downloads', () {
    test('putDownload then listDownloads round-trips with progress', () async {
      final t = DownloadTask(
        id: 'dl-1',
        itemId: 'dl-1',
        title: 'Movie',
        sourceUrl: 'http://example/movie.mp4',
        status: DownloadStatus.running,
        createdAt: DateTime.utc(2026, 4, 28),
        totalBytes: 1024 * 1024 * 200,
        bytesReceived: 1024 * 1024 * 50,
      );
      await storage.putDownload(t);
      final list = await storage.listDownloads();
      expect(list, hasLength(1));
      expect(list.first.totalBytes, 1024 * 1024 * 200);
      expect(list.first.bytesReceived, 1024 * 1024 * 50);
      expect(list.first.progress, closeTo(0.25, 0.001));
    });

    test('getDownload returns the right task and null for missing id',
        () async {
      final t = DownloadTask(
        id: 'dl-2',
        itemId: 'dl-2',
        title: 'Movie',
        sourceUrl: 'http://example/movie.mp4',
        status: DownloadStatus.completed,
        createdAt: DateTime.utc(2026, 4, 28),
      );
      await storage.putDownload(t);
      final got = await storage.getDownload('dl-2');
      expect(got, isNotNull);
      expect(got!.title, 'Movie');
      expect(await storage.getDownload('nope'), isNull);
    });
  });
}
