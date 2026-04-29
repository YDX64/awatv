import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Watch later list — distinct from favourites.
///
/// Three tabs: Hepsi / Filmler / Diziler. Tap opens the matching detail
/// screen (`/movie/:id` or `/series/:id`); long-press removes the item
/// in place.
class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch list'),
        bottom: TabBar(
          controller: _tab,
          tabs: const <Widget>[
            Tab(text: 'Hepsi'),
            Tab(text: 'Filmler'),
            Tab(text: 'Diziler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const <Widget>[
          _WatchlistGrid(filter: null),
          _WatchlistGrid(filter: HistoryKind.vod),
          _WatchlistGrid(filter: HistoryKind.series),
        ],
      ),
    );
  }
}

class _WatchlistGrid extends ConsumerWidget {
  const _WatchlistGrid({required this.filter});

  final HistoryKind? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(watchlistEntriesProvider(filter));
    return asyncEntries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace _) =>
          ErrorView(message: err.toString()),
      data: (List<WatchlistEntry> list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.watch_later_outlined,
            title: 'Watchlist henuz bos',
            message: 'Bir film begendiysen kalp degil saat ikonuna bas.',
            actionLabel: filter == HistoryKind.series
                ? 'Dizilere goz at'
                : 'Filmlere goz at',
            onAction: () => context.go(
              filter == HistoryKind.series ? '/series' : '/movies',
            ),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
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
              itemCount: list.length,
              itemBuilder: (BuildContext _, int i) {
                final e = list[i];
                return GestureDetector(
                  onLongPress: () async {
                    final svc = ref.read(watchlistServiceProvider);
                    await svc.remove(e.itemId);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text('${e.title} listeden cikarildi'),
                        action: SnackBarAction(
                          label: 'Geri al',
                          onPressed: () => svc.add(e),
                        ),
                      ),
                    );
                  },
                  child: PosterCard(
                    title: e.title,
                    posterUrl: e.posterUrl,
                    year: e.year,
                    onTap: () => _openDetail(context, e),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openDetail(BuildContext context, WatchlistEntry e) {
    switch (e.kind) {
      case HistoryKind.vod:
        context.push('/movie/${e.itemId}');
      case HistoryKind.series:
        context.push('/series/${e.itemId}');
      case HistoryKind.live:
        // Defensive — service rejects live, but keep the switch exhaustive.
        break;
    }
  }
}
