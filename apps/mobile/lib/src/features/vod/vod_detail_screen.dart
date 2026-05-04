import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/downloads/downloads_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/vod/vod_credits_provider.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Movie detail with backdrop hero, plot, rating, play & trailer buttons.
///
/// Layout follows Streas RN spec § 3 — 280-tall backdrop with a 35%
/// black scrim, floating circular back button, NEW badge, 26px title,
/// meta row (year + rating badge + duration), genre wrap, cherry-filled
/// Play button, three secondary action cards, synopsis, cast row, and
/// "Benzer Filmler" horizontal poster row.
class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({required this.vodId, super.key});

  final String vodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(vodByIdProvider(vodId));
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
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
    final scheme = theme.colorScheme;
    return CustomScrollView(
      slivers: <Widget>[
        // 280-tall hero with 35%-black scrim per spec § 3.1.
        SliverAppBar(
          expandedHeight: 280,
          stretch: true,
          backgroundColor: const Color(0xFF0A0A0A),
          leading: const _CircleBackButton(),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
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
                  Container(color: scheme.surface),
                Container(color: const Color(0x59000000)),
                // Bottom-fade gradient so the title legibly transitions
                // into the page background — Streas runs a darker scrim
                // at the foot of the banner.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 90,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0x00000000),
                          Color(0xFF0A0A0A),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              DesignTokens.spaceM,
              DesignTokens.spaceL,
              DesignTokens.spaceXl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Title — 26px Inter Bold per spec.
                Text(
                  vod.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceS),
                // Meta strip (year + rating badge + duration).
                _MetaStrip(vod: vod),
                const SizedBox(height: DesignTokens.spaceM),
                // Genre wrap — 12px radius surface chips.
                if (vod.genres.isNotEmpty) ...<Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final g in vod.genres) _GenreChip(label: g),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                ],
                // Action button row — full-width Play, then three
                // outlined cards (Watchlist, Trailer, Indir).
                _PlayButton(vod: vod),
                const SizedBox(height: DesignTokens.spaceM),
                _ActionCardsRow(vod: vod),
                const SizedBox(height: DesignTokens.spaceL),
                // Synopsis paragraph — 14px regular muted, lineHeight 22.
                if (vod.plot != null && vod.plot!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignTokens.spaceL),
                    child: Text(
                      vod.plot!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 22 / 14,
                      ),
                    ),
                  ),
                // Cast / crew row — placeholder until TMDB credits land
                // in Phase 3 per spec § 7. Renders empty state if blank.
                _CastRow(vod: vod),
                const SizedBox(height: DesignTokens.spaceL),
                // "Benzer Filmler" — same-genre fallback row.
                _SimilarRow(vod: vod),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Floating back button — 40 circle, 60% black backing per Streas spec § 3.1.
// ---------------------------------------------------------------------------

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (context.canPop()) context.pop();
          },
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meta strip — year + rating badge + duration
// ---------------------------------------------------------------------------

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Colors.white.withValues(alpha: 0.65);
    return Wrap(
      spacing: DesignTokens.spaceM,
      runSpacing: DesignTokens.spaceXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (vod.year != null)
          Text(
            '${vod.year}',
            style: TextStyle(
              fontSize: 13,
              color: mutedColor,
            ),
          ),
        if (vod.rating != null)
          // Cherry-pill IMDb rating per spec § 3.1.
          RatingPill(rating: vod.rating!),
        const _RatingBadge(label: 'TV-14'),
        if (vod.durationMin != null)
          Text(
            '${vod.durationMin} dk',
            style: TextStyle(
              fontSize: 13,
              color: mutedColor,
            ),
          ),
      ],
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary play button — full-width cherry-filled
// ---------------------------------------------------------------------------

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final localPathAsync = ref.watch(downloadedLocalPathProvider(vod.id));
    final localPath = localPathAsync.valueOrNull;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(
          localPath != null ? 'Cevrimdisi oynat' : 'Oynat',
        ),
        onPressed: () => _onPlay(context, localPath),
      ),
    );
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
    if (vod.streamUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu film için oynatma adresi yok.'),
        ),
      );
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

// ---------------------------------------------------------------------------
// Secondary actions row — three outlined cards (icon + label).
// ---------------------------------------------------------------------------

class _ActionCardsRow extends ConsumerWidget {
  const _ActionCardsRow({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _ActionCard(
            icon: Icons.favorite_outline_rounded,
            label: 'Favori',
            onTap: () {
              // Favorite toggle delegates to the existing watchlist-toggle
              // helper for haptic + haptic-error parity. The on-screen
              // feedback comes from the hosted toggle widget (snackbar).
              _toggleFavorite(context, ref);
            },
          ),
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Expanded(
          child: _ActionCard(
            icon: Icons.movie_filter_outlined,
            label: 'Fragman',
            onTap: () => _onTrailer(context, ref),
          ),
        ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: _ActionCard(
              icon: Icons.download_outlined,
              label: 'Indir',
              onTap: () => _onDownload(context, ref),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    // FavoritesService.toggle() flips the channel/VOD's favourite
    // state and emits on its broadcast stream so any listening grid
    // re-renders immediately. The id is global so VODs and channels
    // share the same key space.
    final svc = ref.read(favoritesServiceProvider);
    await svc.toggle(vod.id);
    if (!context.mounted) return;
    final added = await svc.isFavorite(vod.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${vod.title} favorilere eklendi'
              : '${vod.title} favorilerden cikarildi',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
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
      unawaited(
        context.push(
          Uri(
            path: '/trailer/$youtubeId',
            queryParameters: <String, String>{'title': vod.title},
          ).toString(),
        ),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fragman yüklenemedi: $e')),
      );
    }
  }

  Future<void> _onDownload(BuildContext context, WidgetRef ref) async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.downloads));
    if (!allowed) {
      await PremiumLockSheet.show(context, PremiumFeature.downloads);
      return;
    }
    await ref.read(downloadsServiceProvider).enqueue(vod);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${vod.title} indiriliyor')),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cast / crew row — TMDB-backed when a tmdbId is resolved.
// ---------------------------------------------------------------------------

class _CastRow extends ConsumerWidget {
  const _CastRow({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tmdbId = vod.tmdbId;
    final asyncCredits = ref.watch(vodCreditsProvider(tmdbId));
    return asyncCredits.when(
      // Stable skeleton while we hit the network or disk cache. We don't
      // want the row to flicker once data lands so the skeleton is
      // visually similar in height and layout to the loaded state.
      loading: _CastRowSkeleton.new,
      // Errors collapse the row entirely. The metadata service swallows
      // most failures and emits `TmdbCredits.empty`, so reaching this
      // branch means something pretty exceptional happened — better to
      // hide than to show a bare error toast.
      error: (Object _, StackTrace __) => const SizedBox.shrink(),
      data: (TmdbCredits credits) {
        if (credits.cast.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionHeading(text: 'Oyuncular'),
            const SizedBox(height: DesignTokens.spaceS),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: credits.cast.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: DesignTokens.spaceM),
                itemBuilder: (BuildContext _, int i) {
                  return _CastAvatar(member: credits.cast[i]);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CastRowSkeleton extends StatelessWidget {
  const _CastRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading(text: 'Oyuncular'),
        const SizedBox(height: DesignTokens.spaceS),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, __) =>
                const SizedBox(width: DesignTokens.spaceM),
            itemBuilder: (BuildContext _, int __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C1C1C),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 56,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 40,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.member});

  final TmdbCastMember member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = TmdbClient.profileUrl(member.profilePath);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Forward the actor's name as a query param so the stub screen
        // can render a real headline before its own filmography lookup
        // lands in Phase 4.
        final encoded = Uri.encodeQueryComponent(member.name);
        context.push('/cast/${member.id}?name=$encoded');
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipOval(
              child: SizedBox(
                width: 60,
                height: 60,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (BuildContext _, String __) => Container(
                          color: const Color(0xFF1C1C1C),
                        ),
                        errorWidget: (BuildContext _, String __, Object ___) =>
                            _AvatarFallback(scheme: scheme),
                      )
                    : _AvatarFallback(scheme: scheme),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (member.character.isNotEmpty)
              Text(
                member.character,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        color: Colors.white.withValues(alpha: 0.4),
        size: 28,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Similar" row — merges TMDB `/similar` (when available) with local
// genre-overlap scoring.
// ---------------------------------------------------------------------------

class _SimilarRow extends ConsumerWidget {
  const _SimilarRow({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allVodProvider);
    // Genre-overlap scoring on the local catalogue — always available, even
    // when the TMDB key isn't configured. Returns top 5 (or 12 when we have
    // no TMDB feed to merge with).
    final localTop = all.maybeWhen<List<VodItem>>(
      data: (List<VodItem> list) => _pickSimilar(list, limit: 5),
      orElse: () => const <VodItem>[],
    );
    final localFallback = all.maybeWhen<List<VodItem>>(
      data: (List<VodItem> list) => _pickSimilar(list, limit: 12),
      orElse: () => const <VodItem>[],
    );

    // TMDB-backed similar, when we have a tmdbId and the key is set. The
    // metadata service swallows errors and emits an empty list so we can
    // freely use `valueOrNull`.
    final asyncSimilar = ref.watch(vodSimilarTmdbIdsProvider(vod.tmdbId));
    final tmdbIds = asyncSimilar.valueOrNull ?? const <int>[];

    final list = tmdbIds.isEmpty
        ? localFallback
        : _mergeWithTmdb(
            local: localTop,
            tmdbIds: tmdbIds,
            allCatalog: all.valueOrNull ?? const <VodItem>[],
          );

    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeading(text: 'Benzer Filmler'),
        const SizedBox(height: DesignTokens.spaceS),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext _, int i) {
              final item = list[i];
              return _SimilarCard(vod: item);
            },
          ),
        ),
      ],
    );
  }

  List<VodItem> _pickSimilar(List<VodItem> all, {required int limit}) {
    if (vod.genres.isEmpty) {
      return all
          .where((VodItem v) => v.id != vod.id)
          .take(limit)
          .toList(growable: false);
    }
    final mySet = vod.genres.toSet();
    final scored = <_Scored>[];
    for (final v in all) {
      if (v.id == vod.id) continue;
      final overlap = v.genres.where(mySet.contains).length;
      if (overlap == 0) continue;
      scored.add(_Scored(item: v, score: overlap));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((s) => s.item).toList(growable: false);
  }

  /// Merge strategy: take the TMDB-recommended titles that we *also* have
  /// locally (top 5), then top up with the genre-overlap top 5 — deduped
  /// by tmdbId where available, falling back to vod id.
  List<VodItem> _mergeWithTmdb({
    required List<VodItem> local,
    required List<int> tmdbIds,
    required List<VodItem> allCatalog,
  }) {
    final byTmdb = <int, VodItem>{};
    for (final v in allCatalog) {
      final id = v.tmdbId;
      if (id != null && id != vod.tmdbId && v.id != vod.id) {
        byTmdb[id] = v;
      }
    }
    final out = <VodItem>[];
    final seenVodIds = <String>{};

    // 1) TMDB-recommended titles we actually own — top 5.
    for (final tid in tmdbIds) {
      final hit = byTmdb[tid];
      if (hit == null) continue;
      if (seenVodIds.add(hit.id)) {
        out.add(hit);
        if (out.length == 5) break;
      }
    }

    // 2) Top up with local genre-overlap until we hit 10 entries — skip
    //    anything we already added.
    for (final l in local) {
      if (out.length == 10) break;
      if (seenVodIds.add(l.id)) out.add(l);
    }
    return out;
  }
}

class _Scored {
  const _Scored({required this.item, required this.score});
  final VodItem item;
  final int score;
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.vod});

  final VodItem vod;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 110 / 165,
            child: Material(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.pushReplacement('/movie/${vod.id}'),
                child: vod.posterUrl != null && vod.posterUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: vod.posterUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: Colors.white24,
                          size: 32,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            vod.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
