import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/loading_view.dart';
import 'series_providers.dart';

class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(allSeriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Diziler')),
      body: series.when(
        loading: () => const LoadingView(label: 'Diziler yukleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
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
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allSeriesProvider);
              await ref.read(allSeriesProvider.future);
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
                    final s = items[i];
                    return PosterCard(
                      title: s.title,
                      posterUrl: s.posterUrl,
                      year: s.year,
                      rating: s.rating,
                      onTap: () => context.push('/series/${s.id}'),
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
