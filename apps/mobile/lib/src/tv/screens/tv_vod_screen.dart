import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot movie grid. 6-col poster wall on a 1080p TV.
class TvVodScreen extends ConsumerWidget {
  const TvVodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(allVodProvider);
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
            'Filmler',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Expanded(
            child: vod.when(
              loading: () => const LoadingView(label: 'Filmler yukleniyor'),
              error: (Object err, StackTrace _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(allVodProvider),
              ),
              data: (List<VodItem> items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.movie_outlined,
                    title: 'Film yok',
                    message: 'Senkronladigin listede film bulunamadi.',
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
                        final v = items[i];
                        return FocusableTile(
                          autofocus: i == 0,
                          semanticLabel: v.title,
                          onTap: () => context.push('/movie/${v.id}'),
                          child: PosterCard(
                            title: v.title,
                            posterUrl: v.posterUrl,
                            year: v.year,
                            rating: v.rating,
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
