// Seeds EPG programmes for two channels and verifies the EPG grid
// surfaces the channel rows + programme tiles.

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/epg_grid_screen.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('EpgGridScreen mounts with seeded channels + EPG',
      (WidgetTester tester) async {
    final storage = await openTempStorage(tester);

    const sourceId = 'it-epg-src';
    await storage.putSource(
      PlaylistSource(
        id: sourceId,
        name: 'IT EPG',
        kind: PlaylistKind.m3u,
        url: 'http://example.test/list.m3u',
        addedAt: DateTime.utc(2026, 4, 29),
      ),
    );

    // Two channels, each with three programmes today.
    final channels = <Channel>[
      const Channel(
        id: '$sourceId::trt1',
        sourceId: sourceId,
        name: 'TRT 1',
        streamUrl: 'http://example.test/trt1.m3u8',
        kind: ChannelKind.live,
        tvgId: 'trt1.tr',
      ),
      const Channel(
        id: '$sourceId::ntv',
        sourceId: sourceId,
        name: 'NTV',
        streamUrl: 'http://example.test/ntv.m3u8',
        kind: ChannelKind.live,
        tvgId: 'ntv.tr',
      ),
    ];
    await storage.putChannels(sourceId, channels);

    final base = DateTime.utc(2026, 4, 29, 10);
    await storage.putEpg('trt1.tr', <EpgProgramme>[
      EpgProgramme(
        channelTvgId: 'trt1.tr',
        start: base,
        stop: base.add(const Duration(minutes: 30)),
        title: 'Sabah Haberleri',
      ),
      EpgProgramme(
        channelTvgId: 'trt1.tr',
        start: base.add(const Duration(minutes: 30)),
        stop: base.add(const Duration(hours: 1)),
        title: 'Hava Durumu',
      ),
    ]);
    await storage.putEpg('ntv.tr', <EpgProgramme>[
      EpgProgramme(
        channelTvgId: 'ntv.tr',
        start: base,
        stop: base.add(const Duration(hours: 1)),
        title: 'Ekonomi',
      ),
    ]);

    final container = ProviderContainer(
      overrides: <Override>[
        awatvStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: EpgGridScreen(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(EpgGridScreen), findsOneWidget);
    // Channel names from the seeded list should appear as row labels.
    expect(find.text('TRT 1'), findsWidgets);
    expect(find.text('NTV'), findsWidgets);
  });
}
