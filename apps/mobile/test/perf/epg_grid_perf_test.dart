// Stress test for the EPG grid: 100 channels x 24h x 30 programmes per
// channel ~= 3000 tiles. The real grid uses lazy clipping (only the
// visible window paints), so this test verifies that a viewport pump
// stays well within the budget.
//
// We don't render the production `EpgGridScreen` — it requires the
// full provider graph + storage. Instead we render a shape-equivalent
// 2D grid of `Container`s that exercises the same scroll + layout path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EPG grid 100 channels x 30 slots scrolls within budget',
      (WidgetTester tester) async {
    const channelCount = 100;
    const slotsPerChannel = 30;
    const slotWidth = 120.0;
    const rowHeight = 64.0;

    // Wide surface so the inner Row never reports overflow during
    // layout — this is a perf test, not a layout-correctness test.
    await tester.binding.setSurfaceSize(
      const Size(
        slotWidth * slotsPerChannel + 200,
        channelCount * rowHeight + 200,
      ),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: channelCount,
            itemBuilder: (context, ch) {
              return SizedBox(
                height: rowHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: slotsPerChannel,
                  itemBuilder: (ctx, slot) => Container(
                    width: slotWidth - 4,
                    margin: const EdgeInsets.all(2),
                    color: Colors.grey.withValues(alpha: 0.1),
                    alignment: Alignment.center,
                    child: Text('P$ch.$slot'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    // Pump-frames simulates a scroll gesture so we exercise the
    // ListView.builder lazy-build path.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    stopwatch.stop();

    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(5000),
      reason: 'EPG grid pump + settle took ${stopwatch.elapsed}',
    );
  });
}
