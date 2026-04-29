import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/group_filter_chips.dart';
import 'package:awatv_mobile/src/features/channels/sort_mode_provider.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Movies grid — poster cards. Tap navigates to `/movie/:id`.
///
/// Top: chip strip filtering by genre with multi-select + persistence.
/// AppBar: sort menu (8 modes covering year + rating + alphabetical).
class VodScreen extends ConsumerWidget {
  const VodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(allVodProvider);
    final filter = ref.watch(groupFilterProvider(SortSurface.vod));
    final mode = ref.watch(sortModeProvider(SortSurface.vod));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filmler'),
        actions: const <Widget>[
          SortModeButton(surface: SortSurface.vod),
        ],
      ),
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
          final genres = _genres(items);
          final filtered = _filter(items, filter, mode);
          return Column(
            children: <Widget>[
              GroupFilterChips(
                surface: SortSurface.vod,
                groups: genres,
                counts: _countByGroup(items, genres),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.movie_filter_outlined,
                        title: 'Bu filtreye uyan film yok',
                        message: 'Farkli bir tur deneyin.',
                      )
                    : RefreshIndicator(
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
                              padding:
                                  const EdgeInsets.all(DesignTokens.spaceM),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: DesignTokens.spaceM,
                                mainAxisSpacing: DesignTokens.spaceM,
                                childAspectRatio: DesignTokens.posterAspect,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (BuildContext ctx, int i) {
                                final v = filtered[i];
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<String> _genres(List<VodItem> items) {
    final set = <String>{};
    for (final v in items) {
      for (final g in v.genres) {
        final t = g.trim();
        if (t.isNotEmpty) set.add(t);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, int> _countByGroup(List<VodItem> items, List<String> groups) {
    final out = <String, int>{};
    for (final g in groups) {
      out[g] = items.where((VodItem v) => v.genres.contains(g)).length;
    }
    return out;
  }

  List<VodItem> _filter(
    List<VodItem> all,
    GroupFilterState filter,
    SortMode mode,
  ) {
    final scoped = filter.selected.isEmpty
        ? all
        : all
            .where((VodItem v) =>
                v.genres.any((String g) => filter.selected.contains(g)))
            .toList();
    return mode.sortVod(scoped);
  }
}
