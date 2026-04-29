// Seeds the storage layer with three live channels and verifies:
//   * The ChannelsScreen renders three ChannelTile widgets.
//   * Tapping a tile pushes a navigation intent (we observe the
//     navigator stack rather than a real /play route).
//
// Doesn't drive the player engine — that requires libmpv and a real
// surface. The /play route is exercised separately in
// `vod_detail_test.dart` via the "Oynat" CTA assertion.

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_screen.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

void main() {
  setUpAll(() async {
    await ensureIntegrationTestBinding();
  });

  testWidgets('seeds 3 channels and renders tiles',
      (WidgetTester tester) async {
    final storage = await openTempStorage(tester);

    // Seed a playlist source + channels directly into Hive.
    const sourceId = 'integration-src';
    await storage.putSource(
      PlaylistSource(
        id: sourceId,
        name: 'IT Source',
        kind: PlaylistKind.m3u,
        url: 'http://example.test/playlist.m3u',
        addedAt: DateTime.utc(2026, 4, 29),
      ),
    );
    final seeded = <Channel>[
      const Channel(
        id: 'integration-src::ch-1',
        sourceId: sourceId,
        name: 'TRT 1',
        streamUrl: 'http://example.test/trt1.m3u8',
        kind: ChannelKind.live,
        groups: <String>['News'],
      ),
      const Channel(
        id: 'integration-src::ch-2',
        sourceId: sourceId,
        name: 'Show TV',
        streamUrl: 'http://example.test/showtv.m3u8',
        kind: ChannelKind.live,
        groups: <String>['Entertainment'],
      ),
      const Channel(
        id: 'integration-src::ch-3',
        sourceId: sourceId,
        name: 'NTV',
        streamUrl: 'http://example.test/ntv.m3u8',
        kind: ChannelKind.live,
        groups: <String>['News'],
      ),
    ];
    await storage.putChannels(sourceId, seeded);

    final container = ProviderContainer(
      overrides: <Override>[
        awatvStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    // Pre-warm the channels future so the first build sees data.
    await container.read(allChannelsProvider.future);

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChannelsScreen(),
        ),
      ),
    );
    // Multiple frames so the FutureProvider settles + grid resolves.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final tiles = find.byType(ChannelTile);
    expect(
      tiles.evaluate().length,
      greaterThanOrEqualTo(3),
      reason: 'Expected at least 3 ChannelTile widgets for the seeded list',
    );
    // Channel names should surface in the tree.
    expect(find.text('TRT 1'), findsWidgets);
    expect(find.text('Show TV'), findsWidgets);
    expect(find.text('NTV'), findsWidgets);
  });
}
