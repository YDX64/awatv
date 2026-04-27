import 'package:awatv_mobile/src/app/awa_tv_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AwaTvApp boots and renders MaterialApp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: AwaTvApp()),
    );
    // First frame: router redirect resolves & we expect *some* MaterialApp.
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
