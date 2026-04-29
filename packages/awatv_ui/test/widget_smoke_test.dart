// Smoke tests for the rest of the awatv_ui design-system widgets.
// Each verifies the widget builds, renders its primary text, and
// surfaces tap behaviour where applicable.

import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  group('PosterCard', () {
    testWidgets('renders title + year', (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 160,
          child: PosterCard(title: 'Inception', year: 2010),
        ),
      );
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('2010'), findsOneWidget);
    });

    testWidgets('shows rating pill when rating is supplied',
        (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 160,
          child: PosterCard(title: 'Rated', rating: 8.5),
        ),
      );
      expect(find.byType(RatingPill), findsOneWidget);
    });

    testWidgets('hides caption when showCaption is false',
        (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 160,
          child: PosterCard(title: 'Ghost', showCaption: false),
        ),
      );
      expect(find.text('Ghost'), findsNothing);
    });

    testWidgets('tap fires onTap', (WidgetTester tester) async {
      var taps = 0;
      await pump(
        tester,
        SizedBox(
          width: 160,
          child: PosterCard(title: 'Tap me', onTap: () => taps++),
        ),
      );
      await tester.tap(find.byType(PosterCard));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('ChannelTile', () {
    testWidgets('renders channel name', (WidgetTester tester) async {
      await pump(
        tester,
        const ChannelTile(name: 'TRT 1'),
      );
      expect(find.text('TRT 1'), findsOneWidget);
    });

    testWidgets('renders nowPlaying line when supplied',
        (WidgetTester tester) async {
      await pump(
        tester,
        const ChannelTile(
          name: 'Show TV',
          nowPlaying: 'Akşam Haberleri',
        ),
      );
      expect(find.text('Akşam Haberleri'), findsOneWidget);
    });

    testWidgets('renders Next ... line when nextProgramme is set',
        (WidgetTester tester) async {
      await pump(
        tester,
        const ChannelTile(
          name: 'Star TV',
          nextProgramme: 'Akıl Oyunu',
        ),
      );
      expect(find.textContaining('Akıl Oyunu'), findsOneWidget);
    });
  });

  group('GlassButton', () {
    testWidgets('renders child label', (WidgetTester tester) async {
      await pump(
        tester,
        GlassButton(
          onPressed: () {},
          child: const Text('Devam et'),
        ),
      );
      expect(find.text('Devam et'), findsOneWidget);
    });

    testWidgets('icon argument adds a leading icon',
        (WidgetTester tester) async {
      await pump(
        tester,
        GlassButton(
          icon: Icons.play_arrow_rounded,
          onPressed: () {},
          child: const Text('Oynat'),
        ),
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('CategoryTile', () {
    testWidgets('renders label', (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: CategoryTile(label: 'Sports'),
        ),
      );
      expect(find.text('Sports'), findsOneWidget);
    });

    testWidgets('count badge appears when count is set',
        (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: CategoryTile(label: 'Movies', count: '128'),
        ),
      );
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('expandable variant shows chevron',
        (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: CategoryTile(label: 'Group', expandable: true),
        ),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  group('RatingPill', () {
    testWidgets('renders the rating to one decimal',
        (WidgetTester tester) async {
      await pump(tester, const RatingPill(rating: 7.45));
      // toStringAsFixed(1) → "7.5"
      expect(find.text('7.5'), findsOneWidget);
    });

    testWidgets('compact variant still shows value',
        (WidgetTester tester) async {
      await pump(tester, const RatingPill(rating: 9.2, compact: true));
      expect(find.text('9.2'), findsOneWidget);
    });
  });

  group('ShimmerSkeleton', () {
    testWidgets('poster variant builds without error',
        (WidgetTester tester) async {
      await pump(tester, ShimmerSkeleton.poster());
      // Verifies the skeleton renders past the first frame; we don't
      // assert on internal details (`Shimmer.fromColors`).
      expect(find.byType(ShimmerSkeleton), findsOneWidget);
    });

    testWidgets('text variant builds with explicit width',
        (WidgetTester tester) async {
      await pump(tester, ShimmerSkeleton.text(width: 200));
      expect(find.byType(ShimmerSkeleton), findsOneWidget);
    });

    testWidgets('box variant builds with explicit dimensions',
        (WidgetTester tester) async {
      await pump(tester, ShimmerSkeleton.box(width: 100, height: 50));
      expect(find.byType(ShimmerSkeleton), findsOneWidget);
    });

    testWidgets('Semantics announces "Loading"',
        (WidgetTester tester) async {
      await pump(tester, ShimmerSkeleton.poster());
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
  });

  group('NetworkStatusBadge', () {
    testWidgets('live variant renders the LIVE label',
        (WidgetTester tester) async {
      await pump(tester, const NetworkStatusBadge(kind: NetworkStatusKind.live));
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('hd variant renders the HD label',
        (WidgetTester tester) async {
      await pump(tester, const NetworkStatusBadge(kind: NetworkStatusKind.hd));
      expect(find.text('HD'), findsOneWidget);
    });

    testWidgets('compact mode hides the label',
        (WidgetTester tester) async {
      await pump(
        tester,
        const NetworkStatusBadge(
          kind: NetworkStatusKind.hd,
          compact: true,
        ),
      );
      // In compact mode the visual label disappears; the semantic label
      // remains for screen readers.
      expect(find.text('HD'), findsNothing);
    });

    testWidgets('attaches connection chip when label is supplied',
        (WidgetTester tester) async {
      await pump(
        tester,
        const NetworkStatusBadge(
          kind: NetworkStatusKind.hd,
          connectionLabel: 'Home Wi-Fi',
        ),
      );
      expect(find.text('Home Wi-Fi'), findsOneWidget);
    });
  });
}
