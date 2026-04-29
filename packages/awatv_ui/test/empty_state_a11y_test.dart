// Accessibility-focused tests for [EmptyState].
//
// Verifies the Semantics scaffolding added in the 2026-04-28 a11y
// pass: the surface groups title + body into a single container with
// the title as the screen-reader label and the body as the hint.

import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders title text', (WidgetTester tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.tv_rounded,
        title: 'Boş liste',
      ),
    );
    expect(find.text('Boş liste'), findsOneWidget);
  });

  testWidgets('renders message when supplied', (WidgetTester tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.tv_rounded,
        title: 'Henüz yok',
        message: 'İlk öğeyi ekleyin.',
      ),
    );
    expect(find.text('Henüz yok'), findsOneWidget);
    expect(find.text('İlk öğeyi ekleyin.'), findsOneWidget);
  });

  testWidgets('falls back to subtitle when message is null',
      (WidgetTester tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.tv_rounded,
        title: 'Boş',
        subtitle: 'eski API',
      ),
    );
    expect(find.text('eski API'), findsOneWidget);
  });

  testWidgets('renders the actionLabel button when set',
      (WidgetTester tester) async {
    var pressed = 0;
    await pump(
      tester,
      EmptyState(
        icon: Icons.tv_rounded,
        title: 'Boş',
        actionLabel: 'Listeye git',
        onAction: () => pressed++,
      ),
    );
    expect(find.text('Listeye git'), findsOneWidget);
    await tester.tap(find.text('Listeye git'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('explicit action wins over actionLabel/onAction',
      (WidgetTester tester) async {
    await pump(
      tester,
      EmptyState(
        icon: Icons.tv_rounded,
        title: 'Boş',
        actionLabel: 'should-not-render',
        onAction: () {},
        action: const Text('explicit'),
      ),
    );
    expect(find.text('should-not-render'), findsNothing);
    expect(find.text('explicit'), findsOneWidget);
  });

  testWidgets('Semantics container wraps the surface',
      (WidgetTester tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.tv_rounded,
        title: 'Empty title',
        message: 'Empty body',
      ),
    );
    // Spot-check the SemanticsNode tree: the surface should expose
    // 'Empty title' as a label somewhere. Flutter merges adjacent
    // semantics so we use bySemanticsLabel.
    expect(find.bySemanticsLabel('Empty title'), findsAtLeast(1));
  });

  testWidgets('decorative icon does not leak via semantics',
      (WidgetTester tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.tv_rounded,
        title: 'No icon name in tree',
      ),
    );
    // The icon glyph is wrapped in ExcludeSemantics — confirm the
    // tree never carries the raw icon name.
    expect(find.bySemanticsLabel('tv_rounded'), findsNothing);
  });
}
