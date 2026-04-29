import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extra coverage for [AwatvStorage] focused on the metadata-cache,
/// download / recording / reminder boxes, and the listSources sort
/// stability across deletions.
void main() {
  late Directory tmp;
  late AwatvStorage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_storage_extra_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
  });

  tearDown(() async {
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('metadata json cache', () {
    test('round-trips Map without TTL', () async {
      const key = 'test:1';
      await storage.putMetadataJson(key, <String, dynamic>{'a': 1, 'b': 2});
      final got = await storage.getMetadataJson(key);
      expect(got, isNotNull);
      expect(got!['a'], 1);
      expect(got['b'], 2);
    });

    test('returns null for unknown key', () async {
      final got = await storage.getMetadataJson('nope');
      expect(got, isNull);
    });

    test('TTL: returns the value when within window', () async {
      const key = 'ttl:in';
      await storage.putMetadataJson(key, <String, dynamic>{'x': 1});
      final got =
          await storage.getMetadataJson(key, ttl: const Duration(hours: 24));
      expect(got, isNotNull);
    });

    test('TTL: returns null when stale', () async {
      const key = 'ttl:stale';
      await storage.putMetadataJson(key, <String, dynamic>{'x': 1});
      // Sleep just enough to push past a 1ms TTL.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final got =
          await storage.getMetadataJson(key, ttl: const Duration(microseconds: 1));
      expect(got, isNull);
    });
  });

  group('download box', () {
    test('putDownload + getDownload round-trips', () async {
      final task = DownloadTask(
        id: 'd1',
        itemId: 'd1',
        title: 'Foo',
        sourceUrl: 'http://x/y',
        containerExt: 'mp4',
        status: DownloadStatus.pending,
        createdAt: DateTime.utc(2026, 4, 27),
      );
      await storage.putDownload(task);
      final got = await storage.getDownload('d1');
      expect(got, isNotNull);
      expect(got!.id, 'd1');
      expect(got.title, 'Foo');
    });

    test('listDownloads sorts newest-first by createdAt', () async {
      await storage.putDownload(DownloadTask(
        id: 'old',
        itemId: 'old',
        title: 'Old',
        sourceUrl: 'http://x/o',
        containerExt: 'mp4',
        status: DownloadStatus.completed,
        createdAt: DateTime.utc(2026, 4, 1),
      ));
      await storage.putDownload(DownloadTask(
        id: 'new',
        itemId: 'new',
        title: 'New',
        sourceUrl: 'http://x/n',
        containerExt: 'mp4',
        status: DownloadStatus.completed,
        createdAt: DateTime.utc(2026, 4, 27),
      ));
      final list = await storage.listDownloads();
      expect(list.first.id, 'new');
      expect(list.last.id, 'old');
    });

    test('deleteDownload removes the row', () async {
      await storage.putDownload(DownloadTask(
        id: 'gone',
        itemId: 'gone',
        title: 'Gone',
        sourceUrl: 'http://x/y',
        containerExt: 'mp4',
        status: DownloadStatus.completed,
        createdAt: DateTime.now().toUtc(),
      ));
      await storage.deleteDownload('gone');
      expect(await storage.getDownload('gone'), isNull);
    });
  });

  group('recording box', () {
    test('putRecording + listRecordings round-trips', () async {
      final task = RecordingTask(
        id: 'r1',
        channelId: 'src::c',
        channelName: 'TRT 1',
        streamUrl: 'http://x/y',
        status: RecordingStatus.scheduled,
        createdAt: DateTime.utc(2026, 4, 27),
        scheduledAt: DateTime.utc(2026, 4, 27, 11),
        duration: const Duration(minutes: 30),
      );
      await storage.putRecording(task);
      final list = await storage.listRecordings();
      expect(list, hasLength(1));
      expect(list.first.id, 'r1');
      expect(list.first.scheduledAt, DateTime.utc(2026, 4, 27, 11));
    });

    test('deleteRecording removes the row', () async {
      await storage.putRecording(RecordingTask(
        id: 'gone',
        channelId: 'c',
        channelName: 'C',
        streamUrl: 'http://x',
        status: RecordingStatus.cancelled,
        createdAt: DateTime.now().toUtc(),
      ));
      await storage.deleteRecording('gone');
      expect(await storage.listRecordings(), isEmpty);
    });
  });

  group('source ordering', () {
    test('listSources sorts ascending by addedAt', () async {
      final s1 = PlaylistSource(
        id: '1',
        name: '1',
        kind: PlaylistKind.m3u,
        url: 'http://1',
        addedAt: DateTime.utc(2026, 4, 1),
      );
      final s2 = PlaylistSource(
        id: '2',
        name: '2',
        kind: PlaylistKind.m3u,
        url: 'http://2',
        addedAt: DateTime.utc(2026, 4, 2),
      );
      await storage.putSource(s2);
      await storage.putSource(s1);
      final out = await storage.listSources();
      expect(out.map((PlaylistSource p) => p.id), <String>['1', '2']);
    });
  });

  group('init guards', () {
    test('init is idempotent', () async {
      // Already initialised in setUp; calling again must not throw.
      await storage.init(subDir: tmp.path);
      await storage.init(subDir: tmp.path);
      // listSources still works.
      expect(await storage.listSources(), isEmpty);
    });
  });
}
