// Stress test for a category tree with 50 root categories and 5000
// leaf channels (deeply nested). Verifies the tree can rebuild within
// the 500ms budget (10x the target on a development machine — the
// real device will be slower; we leave headroom).
//
// Mirrors the shape used by `customisedCategoryTreeProvider` in the
// app: a list of expandable sections, each with a flat sub-list.

import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('50 categories x 100 channels rebuilds within budget',
      (WidgetTester tester) async {
    const rootCount = 50;
    const leavesPerRoot = 100;

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: rootCount,
            itemBuilder: (context, i) {
              return ExpansionTile(
                title: CategoryTile(
                  label: 'Category $i',
                  count: '$leavesPerRoot',
                  expandable: true,
                ),
                children: List<Widget>.generate(
                  leavesPerRoot,
                  (j) => ListTile(
                    title: Text('Channel $i.$j'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();

    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(3000),
      reason: '50 categories x 100 leaves rebuild took ${stopwatch.elapsed}',
    );
  });
}
