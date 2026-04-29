// Smoke tests for the awatv_core data models. Each verifies value
// equality (where freezed generates it), JSON round-trips, and the
// few helper getters / static methods.

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Channel', () {
    test('buildId prefers tvgId', () {
      final id = Channel.buildId(
        sourceId: 'src',
        name: 'Channel',
        tvgId: 'tvg-1',
        streamId: 's1',
      );
      expect(id, 'src::tvg-1');
    });

    test('buildId falls back to streamId when tvgId is empty', () {
      final id = Channel.buildId(
        sourceId: 'src',
        name: 'Channel',
        streamId: 's1',
      );
      expect(id, 'src::s1');
    });

    test('buildId falls back to name when no ids supplied', () {
      final id = Channel.buildId(sourceId: 'src', name: 'Channel');
      expect(id, 'src::Channel');
    });

    test('json round-trip preserves fields', () {
      const c = Channel(
        id: 'src::1',
        sourceId: 'src',
        name: 'TRT 1',
        streamUrl: 'http://x/y',
        kind: ChannelKind.live,
        tvgId: 'trt-1',
        logoUrl: 'http://x/logo.png',
        groups: <String>['News', 'Public'],
      );
      final j = c.toJson();
      final back = Channel.fromJson(j);
      expect(back.id, c.id);
      expect(back.name, c.name);
      expect(back.kind, c.kind);
      expect(back.groups, c.groups);
    });
  });

  group('VodItem', () {
    test('json round-trip', () {
      const v = VodItem(
        id: 'src::v1',
        sourceId: 'src',
        title: 'Movie',
        streamUrl: 'http://x/y.mp4',
        year: 2024,
        rating: 7.8,
        durationMin: 105,
        genres: <String>['Action', 'Drama'],
      );
      final back = VodItem.fromJson(v.toJson());
      expect(back, equals(v));
    });

    test('default genres list is empty', () {
      const v = VodItem(
        id: '1',
        sourceId: 's',
        title: 't',
        streamUrl: 'http://x',
      );
      expect(v.genres, isEmpty);
    });
  });

  group('SeriesItem', () {
    test('json round-trip', () {
      const s = SeriesItem(
        id: 'src::s1',
        sourceId: 'src',
        title: 'Series',
        seasons: <int>[1, 2, 3],
        year: 2024,
        rating: 8.2,
      );
      final back = SeriesItem.fromJson(s.toJson());
      expect(back, equals(s));
    });
  });

  group('Episode', () {
    test('json round-trip preserves season + number + url', () {
      const e = Episode(
        id: 'ep1',
        seriesId: 'src::s1',
        season: 2,
        number: 5,
        title: 'Pilot',
        streamUrl: 'http://x/s2e5.mp4',
        durationMin: 45,
      );
      final back = Episode.fromJson(e.toJson());
      expect(back.id, e.id);
      expect(back.seriesId, e.seriesId);
      expect(back.season, 2);
      expect(back.number, 5);
      expect(back.streamUrl, e.streamUrl);
    });
  });

  group('PlaylistSource', () {
    test('json round-trip', () {
      final src = PlaylistSource(
        id: '1',
        name: 'Provider',
        kind: PlaylistKind.xtream,
        url: 'http://x.test',
        username: 'u',
        password: 'p',
        addedAt: DateTime.utc(2026),
      );
      final back = PlaylistSource.fromJson(src.toJson());
      expect(back.id, src.id);
      expect(back.kind, PlaylistKind.xtream);
      expect(back.username, 'u');
      expect(back.password, 'p');
      expect(back.addedAt.toUtc(), src.addedAt.toUtc());
    });
  });

  group('EpgProgramme', () {
    test('round-trips through JSON', () {
      final p = EpgProgramme(
        channelTvgId: 'trt-1',
        start: DateTime.utc(2026, 4, 27, 10),
        stop: DateTime.utc(2026, 4, 27, 11),
        title: 'News',
        description: 'Daily roundup',
      );
      final back = EpgProgramme.fromJson(p.toJson());
      expect(back.title, 'News');
      expect(back.description, 'Daily roundup');
    });
  });

  group('HistoryEntry', () {
    test('round-trips through JSON', () {
      final h = HistoryEntry(
        itemId: 'src::v1',
        kind: HistoryKind.vod,
        position: const Duration(minutes: 12),
        total: const Duration(minutes: 60),
        watchedAt: DateTime.utc(2026, 4, 27),
      );
      final back = HistoryEntry.fromJson(h.toJson());
      expect(back.itemId, h.itemId);
      expect(back.kind, HistoryKind.vod);
      expect(back.position, h.position);
      expect(back.total, h.total);
    });
  });

  group('DownloadTask', () {
    test('progress is 0 when totalBytes is 0', () {
      final t = DownloadTask(
        id: '1',
        itemId: '1',
        title: 't',
        sourceUrl: 'http://x',
        status: DownloadStatus.pending,
        createdAt: DateTime.now().toUtc(),
      );
      expect(t.progress, 0);
    });

    test('progress is bytes/total clamped to [0,1]', () {
      final t = DownloadTask(
        id: '1',
        itemId: '1',
        title: 't',
        sourceUrl: 'http://x',
        status: DownloadStatus.running,
        createdAt: DateTime.now().toUtc(),
        bytesReceived: 50,
        totalBytes: 200,
      );
      expect(t.progress, 0.25);
    });

    test('progress clamps over-100% values to 1.0', () {
      final t = DownloadTask(
        id: '1',
        itemId: '1',
        title: 't',
        sourceUrl: 'http://x',
        status: DownloadStatus.running,
        createdAt: DateTime.now().toUtc(),
        bytesReceived: 1000,
        totalBytes: 200,
      );
      expect(t.progress, 1.0);
    });

    test('json round-trips status enum + timestamps', () {
      final t = DownloadTask(
        id: 'd',
        itemId: 'd',
        title: 'foo',
        sourceUrl: 'http://x',
        status: DownloadStatus.completed,
        createdAt: DateTime.utc(2026, 4, 27),
        startedAt: DateTime.utc(2026, 4, 27, 10),
        finishedAt: DateTime.utc(2026, 4, 27, 11),
        bytesReceived: 1024,
        totalBytes: 1024,
      );
      final back = DownloadTask.fromJson(t.toJson());
      expect(back.status, DownloadStatus.completed);
      expect(back.startedAt!.toUtc(), t.startedAt!.toUtc());
      expect(back.finishedAt!.toUtc(), t.finishedAt!.toUtc());
      expect(back.bytesReceived, 1024);
    });
  });

  group('RecordingTask', () {
    test('copyWith preserves untouched fields', () {
      final t = RecordingTask(
        id: 'r',
        channelId: 'c',
        channelName: 'C',
        streamUrl: 'http://x',
        status: RecordingStatus.scheduled,
        createdAt: DateTime.utc(2026),
        userAgent: 'AWAtv',
        referer: 'http://x',
      );
      final next = t.copyWith(status: RecordingStatus.completed);
      expect(next.status, RecordingStatus.completed);
      expect(next.id, t.id);
      expect(next.userAgent, t.userAgent);
      expect(next.referer, t.referer);
    });

    test('json round-trips backend + duration', () {
      final t = RecordingTask(
        id: 'r',
        channelId: 'c',
        channelName: 'C',
        streamUrl: 'http://x',
        status: RecordingStatus.completed,
        createdAt: DateTime.utc(2026),
        startedAt: DateTime.utc(2026, 1, 1, 10),
        finishedAt: DateTime.utc(2026, 1, 1, 11),
        duration: const Duration(minutes: 30),
        backend: RecordingBackend.ffmpeg,
        bytesWritten: 9999,
        outputPath: '/tmp/r.mp4',
      );
      final back = RecordingTask.fromJson(t.toJson());
      expect(back.duration, const Duration(minutes: 30));
      expect(back.backend, RecordingBackend.ffmpeg);
      expect(back.bytesWritten, 9999);
      expect(back.outputPath, '/tmp/r.mp4');
    });
  });
}
