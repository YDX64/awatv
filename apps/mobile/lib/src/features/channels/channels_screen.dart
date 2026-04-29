import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/channels/epg_providers.dart';
import 'package:awatv_mobile/src/features/channels/group_filter_chips.dart';
import 'package:awatv_mobile/src/features/channels/sort_mode_provider.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_session.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/discovery/share_helper.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Live-channel grid.
///
/// Top: horizontally scrollable group filter chips (with multi-select +
/// per-surface persisted selection).
/// Body: 2-column responsive grid of `ChannelTile`s. On wider devices it
/// scales up to 3-4 columns.
///
/// The grid runs the chip-selected groups through the active sort mode
/// before rendering — see [_filtered] for the pipeline.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the un-filtered `liveChannelsProvider` directly so the new
    // chip-based multi-select filter is the only filter in play —
    // otherwise the legacy `channelGroupFilterProvider` (single-group)
    // would silently double-filter behind the new UI.
    final channelsAsync = ref.watch(liveChannelsProvider);
    final groupsAsync = ref.watch(liveChannelGroupsProvider);
    final filter = ref.watch(groupFilterProvider(SortSurface.live));
    final mode = ref.watch(sortModeProvider(SortSurface.live));

    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read(liveViewModePrefProvider.notifier).setIfUnset(
              isWide ? LiveViewMode.grid : LiveViewMode.list,
            ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canli Kanallar'),
        actions: [
          const SortModeButton(surface: SortSurface.live),
          IconButton(
            tooltip: 'TV Rehberi',
            icon: const Icon(Icons.grid_view_outlined),
            onPressed: () async {
              await ref
                  .read(liveViewModePrefProvider.notifier)
                  .set(LiveViewMode.grid);
              if (!context.mounted) return;
              unawaited(context.push<void>('/live/epg'));
            },
          ),
          IconButton(
            tooltip: 'Listeleri yonet',
            icon: const Icon(Icons.queue_music_outlined),
            onPressed: () => context.push('/playlists'),
          ),
        ],
      ),
      body: Column(
        children: [
          groupsAsync.when(
            loading: () => const SizedBox(height: 56),
            error: (Object _, StackTrace __) => const SizedBox.shrink(),
            data: (List<String> values) => channelsAsync.when(
              loading: () => GroupFilterChips(
                surface: SortSurface.live,
                groups: values,
                counts: const <String, int>{},
              ),
              error: (Object _, StackTrace __) => GroupFilterChips(
                surface: SortSurface.live,
                groups: values,
                counts: const <String, int>{},
              ),
              data: (List<Channel> all) => GroupFilterChips(
                surface: SortSurface.live,
                groups: values,
                counts: _countByGroup(all, values),
              ),
            ),
          ),
          Expanded(
            child: channelsAsync.when(
              loading: () => const LoadingView(label: 'Kanallar yukleniyor'),
              error: (Object err, StackTrace st) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(liveChannelsProvider),
              ),
              data: (List<Channel> values) {
                final filtered = _filtered(values, filter, mode);
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.live_tv_outlined,
                    title: 'Kanal bulunamadi',
                    message: filter.selected.isEmpty
                        ? 'Listeni yenileyip tekrar dene.'
                        : 'Secili gruplarda kanal yok.',
                    actionLabel: 'Yenile',
                    onAction: () =>
                        ref.invalidate(liveChannelsProvider),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(liveChannelsProvider);
                    await ref.read(liveChannelsProvider.future);
                  },
                  child: LayoutBuilder(
                    builder: (BuildContext ctx, BoxConstraints c) {
                      final width = c.maxWidth;
                      final cols = width > 900
                          ? 4
                          : width > 600
                              ? 3
                              : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(DesignTokens.spaceM),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: DesignTokens.spaceM,
                          mainAxisSpacing: DesignTokens.spaceM,
                          childAspectRatio: DesignTokens.channelTileAspect,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final ch = filtered[i];
                          return ChannelTile(
                            name: ch.name,
                            logoUrl: ch.logoUrl,
                            group: ch.groups.isEmpty ? null : ch.groups.first,
                            onTap: () => _play(context, ch),
                            onLongPress: () => _showChannelContextSheet(
                              context,
                              ref,
                              ch,
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pipeline: groups (chips) → sort. When [filter] selects nothing, no
  /// group filtering is applied (i.e. "Tumu").
  List<Channel> _filtered(
    List<Channel> all,
    GroupFilterState filter,
    SortMode mode,
  ) {
    final scoped = filter.selected.isEmpty
        ? all
        : all
            .where((Channel c) =>
                c.groups.any((String g) => filter.selected.contains(g)))
            .toList();
    return mode.sortChannels(scoped);
  }

  Map<String, int> _countByGroup(List<Channel> items, List<String> groups) {
    final out = <String, int>{};
    for (final g in groups) {
      out[g] = items.where((Channel c) => c.groups.contains(g)).length;
    }
    return out;
  }

  void _play(BuildContext context, Channel channel) {
    final headers = <String, String>{};
    final ua = channel.extras['http-user-agent'] ??
        channel.extras['user-agent'];
    final referer = channel.extras['http-referrer'] ??
        channel.extras['referer'] ??
        channel.extras['Referer'];
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }

    final urls = streamUrlVariants(channel.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: channel.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final args = PlayerLaunchArgs(
      source: variants.isEmpty
          ? MediaSource(
              url: proxify(channel.streamUrl),
              title: channel.name,
              userAgent: ua,
              headers: headers.isEmpty ? null : headers,
            )
          : variants.first,
      fallbacks: variants.length <= 1
          ? const <MediaSource>[]
          : variants.sublist(1),
      title: channel.name,
      subtitle: channel.groups.isEmpty ? null : channel.groups.first,
      itemId: channel.id,
      kind: HistoryKind.live,
      isLive: true,
    );

    context.push('/play', extra: args);
  }

  /// Adds [channel] to the multi-stream session and routes the user
  /// to `/multistream` so they see it appear in the grid.
  ///
  /// Free users see the paywall sheet first; existing-channel and
  /// session-full conditions surface as snacks so the user understands
  /// why nothing happened.
  void _addToMultiStream(
    BuildContext sheetCtx,
    WidgetRef ref,
    Channel channel,
  ) {
    // Pop the long-press sheet first so the snack / paywall lands on
    // a clean route rather than under the bottom sheet scrim.
    Navigator.of(sheetCtx).pop();
    final root = sheetCtx;
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.multiScreen));
    if (!allowed) {
      PremiumLockSheet.show(root, PremiumFeature.multiScreen);
      return;
    }
    final session = ref.read(multiStreamSessionProvider);
    if (session.isFull) {
      ScaffoldMessenger.of(root).showSnackBar(
        const SnackBar(
          content: Text(
            'Daha fazla ekleyemezsiniz, en az birini cikarin.',
          ),
        ),
      );
      return;
    }
    final addedIndex =
        ref.read(multiStreamSessionProvider.notifier).addChannel(channel);
    final messenger = ScaffoldMessenger.of(root);
    if (addedIndex == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kanal eklenemedi.')),
      );
      return;
    }
    // Navigate to the multi-stream view so the user sees the tile
    // they just added. The route is already-open-aware: if /multistream
    // is the current top-of-stack go_router still tolerates push() and
    // simply paints over itself, but the cleaner path is `go` so the
    // new route replaces the stack entry.
    if (GoRouter.of(root).routerDelegate.currentConfiguration.uri.path !=
        '/multistream') {
      root.push('/multistream');
    }
  }

  /// Bottom-sheet surfaced via long-press on a [ChannelTile]. Hosts the
  /// favourite toggle, channel-detail link and the new "Paylas" entry
  /// (which builds a deep link via [ShareHelper.shareChannel]).
  Future<void> _showChannelContextSheet(
    BuildContext context,
    WidgetRef ref,
    Channel channel,
  ) async {
    final favs = ref.read(favoritesServiceProvider);
    // FavoritesService exposes `isFavorite` as Future<bool>; resolve once
    // before painting the sheet so the icon doesn't have to flicker.
    final isFav = await favs.isFavorite(channel.id);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.primary,
                  foregroundColor:
                      Theme.of(ctx).colorScheme.onPrimary,
                  child: const Icon(Icons.live_tv_rounded),
                ),
                title: Text(channel.name),
                subtitle: channel.groups.isEmpty
                    ? null
                    : Text(channel.groups.first),
              ),
              const Divider(height: 0),
              ListTile(
                leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                ),
                title: Text(
                  isFav ? 'Favorilerden cikar' : 'Favorilere ekle',
                ),
                onTap: () async {
                  await favs.toggle(channel.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detaylar'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/channel/${channel.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Paylas'),
                subtitle: const Text(
                  'AWAtv kullananlar bu kanali acabilir',
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ShareHelper.shareChannel(context, channel);
                },
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_rounded),
                title: const Text('Coklu izle'),
                subtitle: const Text(
                  'Bu kanali coklu izleme ekranina ekle',
                ),
                onTap: () => _addToMultiStream(ctx, ref, channel),
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          ),
        );
      },
    );
  }
}

/// Detail screen for a single channel — EPG + favorite + play CTA. Reached
/// via `/channel/:id` (long-press from the grid).
class ChannelDetailScreen extends ConsumerWidget {
  const ChannelDetailScreen({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ref.watch(channelByIdProvider(channelId));
    return Scaffold(
      appBar: AppBar(),
      body: channel.when(
        loading: () => const LoadingView(),
        error: (Object err, StackTrace st) =>
            ErrorView(message: err.toString()),
        data: (Channel? c) {
          if (c == null) {
            return const EmptyState(
              icon: Icons.help_outline,
              title: 'Kanal bulunamadi',
            );
          }
          return Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                if (c.groups.isNotEmpty) ...[
                  const SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    c.groups.join(' / '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
                const SizedBox(height: DesignTokens.spaceL),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Oynat'),
                  onPressed: () {
                    final urls = streamUrlVariants(c.streamUrl)
                        .map(proxify)
                        .toList();
                    final variants = MediaSource.variants(
                      urls,
                      title: c.name,
                      userAgent: c.extras['http-user-agent'],
                    );
                    final args = PlayerLaunchArgs(
                      source: variants.isEmpty
                          ? MediaSource(
                              url: proxify(c.streamUrl),
                              title: c.name,
                              userAgent: c.extras['http-user-agent'],
                            )
                          : variants.first,
                      fallbacks: variants.length <= 1
                          ? const <MediaSource>[]
                          : variants.sublist(1),
                      title: c.name,
                      itemId: c.id,
                      kind: HistoryKind.live,
                      isLive: true,
                    );
                    context.push('/play', extra: args);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
