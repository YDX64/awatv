import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/downloads/downloads_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/features/watchlist/watchlist_toggle.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

class _Body extends ConsumerWidget {
  const _Body({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _ActionRow(vod: vod),
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

/// Play / Indir / Fragman action row at the bottom of the VOD detail
/// page. The Indir button is Premium-gated and replaced by an
/// "Oynat (cevrimdisi)" CTA once the file lives on disk.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPathAsync = ref.watch(downloadedLocalPathProvider(vod.id));
    final localPath = localPathAsync.valueOrNull;
    final downloadsAsync = ref.watch(downloadsProvider);
    DownloadTask? task;
    for (final t in downloadsAsync.value ?? const <DownloadTask>[]) {
      if (t.id == vod.id) {
        task = t;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(localPath != null ? 'Cevrimdisi oynat' : 'Oynat'),
                onPressed: () => _onPlay(context, localPath),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            // Watchlist (saat ikonu) — favoriden ayri "sonra izle" listesi.
            // Ayni satirda fragmanin yaninda dursun ki kullanici tek
            // bakista kalp / saat / fragman ucusunu gorsun.
            WatchlistToggleButton(
              itemId: vod.id,
              kind: HistoryKind.vod,
              title: vod.title,
              posterUrl: vod.posterUrl,
              year: vod.year,
              compact: true,
            ),
            const SizedBox(width: DesignTokens.spaceS),
            OutlinedButton.icon(
              icon: const Icon(Icons.movie_filter_outlined),
              label: const Text('Fragman'),
              onPressed: () => _onTrailer(context, ref),
            ),
          ],
        ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(height: DesignTokens.spaceS),
          _DownloadButton(vod: vod, task: task),
        ],
      ],
    );
  }

  Future<void> _onTrailer(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final tmdbId = vod.tmdbId;
    if (tmdbId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fragman bulunamadi')),
      );
      return;
    }
    try {
      final youtubeId = await ref
          .read(metadataServiceProvider)
          .trailerYoutubeId(tmdbId, MediaType.movie);
      if (youtubeId == null || youtubeId.isEmpty) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Fragman bulunamadi')),
        );
        return;
      }
      if (!context.mounted) return;
      context.push(
        Uri(
          path: '/trailer/$youtubeId',
          queryParameters: <String, String>{'title': vod.title},
        ).toString(),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fragman yüklenemedi: $e')),
      );
    }
  }

  void _onPlay(BuildContext context, String? localPath) {
    if (localPath != null) {
      final src = MediaSource(
        url: 'file://$localPath',
        title: vod.title,
      );
      final args = PlayerLaunchArgs(
        source: src,
        title: vod.title,
        subtitle: 'Cevrimdisi',
        itemId: vod.id,
        kind: HistoryKind.vod,
      );
      context.push('/play', extra: args);
      return;
    }
    final urls = streamUrlVariants(vod.streamUrl).map(proxify).toList();
    final all = MediaSource.variants(urls, title: vod.title);
    final args = PlayerLaunchArgs(
      source: all.isEmpty
          ? MediaSource(
              url: proxify(vod.streamUrl),
              title: vod.title,
            )
          : all.first,
      fallbacks: all.length <= 1
          ? const <MediaSource>[]
          : all.sublist(1),
      title: vod.title,
      subtitle: vod.year == null ? null : '${vod.year}',
      itemId: vod.id,
      kind: HistoryKind.vod,
    );
    context.push('/play', extra: args);
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.vod, this.task});

  final VodItem vod;
  final DownloadTask? task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(downloadsServiceProvider);
    final t = task;

    if (t == null || t.status == DownloadStatus.cancelled) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.download_outlined),
        label: const Text('Indir'),
        onPressed: () async {
          final allowed =
              ref.read(canUseFeatureProvider(PremiumFeature.downloads));
          if (!allowed) {
            await PremiumLockSheet.show(context, PremiumFeature.downloads);
            return;
          }
          await svc.enqueue(vod);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${vod.title} indiriliyor')),
          );
        },
      );
    }

    switch (t.status) {
      case DownloadStatus.completed:
        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.offline_pin_outlined),
                label: const Text('Indirildi'),
                onPressed: () => context.push('/downloads'),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => svc.delete(t.id),
            ),
          ],
        );
      case DownloadStatus.running:
      case DownloadStatus.pending:
        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pause_rounded),
                label: Text(
                  t.totalBytes > 0
                      ? '%${(t.progress * 100).toStringAsFixed(0)} • '
                          'duraklat'
                      : 'Indiriliyor • duraklat',
                ),
                onPressed: () => svc.pause(t.id),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            IconButton(
              tooltip: 'Iptal',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => svc.cancel(t.id),
            ),
          ],
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  t.status == DownloadStatus.failed
                      ? 'Tekrar dene'
                      : 'Devam et',
                ),
                onPressed: () => svc.resume(t.id),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => svc.delete(t.id),
            ),
          ],
        );
      case DownloadStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}
