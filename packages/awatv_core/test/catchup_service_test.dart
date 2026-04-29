// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [CatchupService].
///
/// The service depends on a real `XtreamClient` to fetch the
/// `get_simple_data_table` payload and to render timeshift URLs. We
/// don't make a real network call here — the tests exercise:
///
///   * empty / non-Xtream paths return empty lists / null URLs
///   * missing credentials short-circuit
///   * channelsWithCatchup() filters live + Xtream-only correctly
///   * id parsing extracts the trailing stream id
void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late CatchupService svc;
  late Dio dio;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_catchup_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 1)));
    svc = CatchupService(storage: storage, dio: dio);
  });

  tearDown(() async {
    dio.close(force: true);
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  PlaylistSource m3uSource() => PlaylistSource(
        id: 'm3u-src',
        name: 'M3U Provider',
        kind: PlaylistKind.m3u,
        url: 'http://example.test/list.m3u',
        addedAt: DateTime.utc(2026),
      );

  PlaylistSource xtreamSource({String? user, String? pass}) => PlaylistSource(
        id: 'xtream-src',
        name: 'Xtream Provider',
        kind: PlaylistKind.xtream,
        url: 'http://xtream.test',
        username: user,
        password: pass,
        addedAt: DateTime.utc(2026),
      );

  Channel ch({
    required String sourceId,
    String suffix = '101',
    ChannelKind kind = ChannelKind.live,
  }) =>
      Channel(
        id: '$sourceId::$suffix',
        sourceId: sourceId,
        name: 'Test Channel',
        streamUrl: 'http://x.test/stream',
        kind: kind,
      );

  group('programmesFor', () {
    test('returns empty list for unknown source', () async {
      final res = await svc.programmesFor(ch(sourceId: 'no-such-src'));
      expect(res, isEmpty);
    });

    test('returns empty list for M3U source', () async {
      await storage.putSource(m3uSource());
      final res = await svc.programmesFor(ch(sourceId: 'm3u-src'));
      expect(res, isEmpty);
    });

    test('returns empty list for xtream source w/o credentials', () async {
      await storage.putSource(xtreamSource());
      final res = await svc.programmesFor(ch(sourceId: 'xtream-src'));
      expect(res, isEmpty);
    });

    test('returns empty list when channel id has no numeric tail', () async {
      await storage.putSource(xtreamSource(user: 'u', pass: 'p'));
      // The fetch will fail because we point at a closed port; the
      // service catches that and returns []. We assert the public
      // contract: empty list, no exceptions.
      final res = await svc.programmesFor(
        const Channel(
          id: 'xtream-src::not-a-number',
          sourceId: 'xtream-src',
          name: 'Word',
          streamUrl: 'http://x.test/word',
          kind: ChannelKind.live,
        ),
      );
      expect(res, isEmpty);
    });
  });

  group('urlForEpg', () {
    test('returns null when source is missing', () async {
      final url = await svc.urlForEpg(
        ch(sourceId: 'missing'),
        EpgProgramme(
          channelTvgId: 'chan',
          start: DateTime.utc(2026, 4, 27, 10),
          stop: DateTime.utc(2026, 4, 27, 11),
          title: 'Foo',
        ),
      );
      expect(url, isNull);
    });

    test('returns null for non-Xtream source', () async {
      await storage.putSource(m3uSource());
      final url = await svc.urlForEpg(
        ch(sourceId: 'm3u-src'),
        EpgProgramme(
          channelTvgId: 'chan',
          start: DateTime.utc(2026, 4, 27, 10),
          stop: DateTime.utc(2026, 4, 27, 11),
          title: 'Foo',
        ),
      );
      expect(url, isNull);
    });

    test('returns null when channel id has no numeric tail', () async {
      await storage.putSource(xtreamSource(user: 'u', pass: 'p'));
      final url = await svc.urlForEpg(
        const Channel(
          id: 'xtream-src::not-numeric',
          sourceId: 'xtream-src',
          name: 'X',
          streamUrl: 'http://x',
          kind: ChannelKind.live,
        ),
        EpgProgramme(
          channelTvgId: 'chan',
          start: DateTime.utc(2026, 4, 27, 10),
          stop: DateTime.utc(2026, 4, 27, 11),
          title: 'Foo',
        ),
      );
      expect(url, isNull);
    });

    test('returns a URL when source + channel are valid', () async {
      await storage.putSource(xtreamSource(user: 'u', pass: 'p'));
      final url = await svc.urlForEpg(
        ch(sourceId: 'xtream-src', suffix: '9001'),
        EpgProgramme(
          channelTvgId: 'chan',
          start: DateTime.utc(2026, 4, 27, 10),
          stop: DateTime.utc(2026, 4, 27, 11),
          title: 'Foo',
        ),
      );
      expect(url, isNotNull);
      // The Xtream timeshift URL should reference the stream id we
      // extracted from the channel id's numeric tail.
      expect(url, contains('9001'));
    });
  });

  group('channelsWithCatchup', () {
    test('filters out non-Xtream sources', () async {
      await storage.putSource(m3uSource());
      // Insert an M3U live channel; expect to get back nothing.
      await storage.putChannels('m3u-src', <Channel>[ch(sourceId: 'm3u-src')]);
      final list = await svc.channelsWithCatchup();
      expect(list, isEmpty);
    });

    test('keeps Xtream live channels with credentials', () async {
      await storage.putSource(xtreamSource(user: 'u', pass: 'p'));
      await storage.putChannels('xtream-src', <Channel>[
        ch(sourceId: 'xtream-src', suffix: '1'),
        ch(sourceId: 'xtream-src', suffix: '2'),
      ]);
      final list = await svc.channelsWithCatchup();
      expect(list, hasLength(2));
    });

    test('drops VOD channels even on Xtream source', () async {
      await storage.putSource(xtreamSource(user: 'u', pass: 'p'));
      await storage.putChannels('xtream-src', <Channel>[
        ch(sourceId: 'xtream-src', suffix: '1', kind: ChannelKind.vod),
        ch(sourceId: 'xtream-src', suffix: '2'),
      ]);
      final list = await svc.channelsWithCatchup();
      expect(list.map((Channel c) => c.id), <String>['xtream-src::2']);
    });
  });
}
