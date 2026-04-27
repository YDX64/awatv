import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot series grid — same poster grid as VOD but pushes
/// `/series/:id` instead.
class TvSeriesScreen extends ConsumerWidget {
  const TvSeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(allSeriesProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Diziler',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Expanded(
            child: series.when(
              loading: () => const LoadingView(label: 'Diziler yukleniyor'),
              error: (Object err, StackTrace _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(allSeriesProvider),
              ),
              data: (List<SeriesItem> items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.video_library_outlined,
                    title: 'Dizi yok',
                    message: 'Senkronladigin listede dizi bulunamadi.',
                  );
                }
                return LayoutBuilder(
                  builder: (BuildContext _, BoxConstraints c) {
                    final cols = c.maxWidth > 1800
                        ? 7
                        : c.maxWidth > 1400
                            ? 6
                            : 5;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: DesignTokens.spaceL,
                        mainAxisSpacing: DesignTokens.spaceL,
                        childAspectRatio: DesignTokens.posterAspect,
                      ),
                      itemCount: items.length,
                      itemBuilder: (BuildContext _, int i) {
                        final s = items[i];
                        return FocusableTile(
                          autofocus: i == 0,
                          semanticLabel: s.title,
                          onTap: () => context.push('/series/${s.id}'),
                          child: PosterCard(
                            title: s.title,
                            posterUrl: s.posterUrl,
                            year: s.year,
                            rating: s.rating,
                            showCaption: false,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
