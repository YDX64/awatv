import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Movie detail with backdrop hero, plot, rating, play & trailer buttons.
class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({required this.vodId, super.key});

  final String vodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(vodByIdProvider(vodId));
    return Scaffold(
      body: vod.when(
        loading: () => const LoadingView(),
        error: (Object err, StackTrace st) =>
            ErrorView(message: err.toString()),
        data: (VodItem? v) {
          if (v == null) {
            return const EmptyState(
              icon: Icons.help_outline,
              title: 'Film bulunamadi',
            );
          }
          return _Body(vod: v);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (vod.backdropUrl != null)
                  CachedNetworkImage(
                    imageUrl: vod.backdropUrl!,
                    fit: BoxFit.cover,
                  )
                else if (vod.posterUrl != null)
                  CachedNetworkImage(
                    imageUrl: vod.posterUrl!,
                    fit: BoxFit.cover,
                  )
                else
                  Container(color: theme.colorScheme.surface),
                const GradientScrim(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ],
            ),
            title: Text(
              vod.title,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: DesignTokens.spaceS,
                  runSpacing: DesignTokens.spaceS,
                  children: [
                    if (vod.rating != null) RatingPill(rating: vod.rating!),
                    if (vod.year != null) _MetaChip(label: '${vod.year}'),
                    if (vod.durationMin != null)
                      _MetaChip(label: '${vod.durationMin} dk'),
                    for (final g in vod.genres) _MetaChip(label: g),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceL),
                if (vod.plot != null && vod.plot!.isNotEmpty) ...[
                  Text(vod.plot!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: DesignTokens.spaceL),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Oynat'),
                        onPressed: () {
                          final args = PlayerLaunchArgs(
                            source: MediaSource(
                              url: vod.streamUrl,
                              title: vod.title,
                            ),
                            title: vod.title,
                            subtitle:
                                vod.year == null ? null : '${vod.year}',
                            itemId: vod.id,
                            kind: HistoryKind.vod,
                          );
                          context.push('/play', extra: args);
                        },
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceM),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.movie_filter_outlined),
                      label: const Text('Fragman'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Fragman oynatici Phase 2 te eklenecek.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceXl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
