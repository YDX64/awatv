import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Movies grid — poster cards. Tap navigates to `/movie/:id`.
class VodScreen extends ConsumerWidget {
  const VodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(allVodProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Filmler')),
      body: vod.when(
        loading: () => const LoadingView(label: 'Filmler yukleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
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
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allVodProvider);
              await ref.read(allVodProvider.future);
            },
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints c) {
                final width = c.maxWidth;
                final cols = width > 1100
                    ? 6
                    : width > 800
                        ? 5
                        : width > 600
                            ? 4
                            : 3;
                return GridView.builder(
                  padding: const EdgeInsets.all(DesignTokens.spaceM),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: DesignTokens.spaceM,
                    mainAxisSpacing: DesignTokens.spaceM,
                    childAspectRatio: DesignTokens.posterAspect,
                  ),
                  itemCount: items.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final v = items[i];
                    return PosterCard(
                      title: v.title,
                      posterUrl: v.posterUrl,
                      year: v.year,
                      rating: v.rating,
                      onTap: () => context.push('/movie/${v.id}'),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
