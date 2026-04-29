// Accessibility-focused tests for [ErrorView].

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

  testWidgets('renders the message', (WidgetTester tester) async {
    await pump(
      tester,
      const ErrorView(message: 'Network timed out'),
    );
    expect(find.text('Network timed out'), findsOneWidget);
  });

  testWidgets('uses default English title when none supplied',
      (WidgetTester tester) async {
    await pump(
      tester,
      const ErrorView(message: 'msg'),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('custom title overrides default', (WidgetTester tester) async {
    await pump(
      tester,
      const ErrorView(
        title: 'Bağlantı hatası',
        message: 'Tekrar dene',
      ),
    );
    expect(find.text('Bağlantı hatası'), findsOneWidget);
  });

  testWidgets('retry button is rendered when onRetry is set',
      (WidgetTester tester) async {
    var retried = 0;
    await pump(
      tester,
      ErrorView(message: 'fail', onRetry: () => retried++),
    );
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('retry button is hidden when onRetry is null',
      (WidgetTester tester) async {
    await pump(
      tester,
      const ErrorView(message: 'fail'),
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('error illustration is excluded from semantics',
      (WidgetTester tester) async {
    await pump(
      tester,
      const ErrorView(
        message: 'msg',
      ),
    );
    // The icon is decorative — must not surface as a Semantics label.
    expect(find.bySemanticsLabel('error_outline_rounded'), findsNothing);
  });
}
