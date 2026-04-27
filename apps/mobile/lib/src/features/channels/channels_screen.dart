import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Live-channel grid.
///
/// Top: horizontally scrollable group filter chips.
/// Body: 2-column responsive grid of `ChannelTile`s. On wider devices it
/// scales up to 3-4 columns.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(filteredLiveChannelsProvider);
    final groups = ref.watch(liveChannelGroupsProvider);
    final activeGroup = ref.watch(channelGroupFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canli Kanallar'),
        actions: [
          IconButton(
            tooltip: 'Listeleri yonet',
            icon: const Icon(Icons.queue_music_outlined),
            onPressed: () => context.push('/playlists'),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: groups.when(
              loading: () => const SizedBox.shrink(),
              error: (Object err, StackTrace st) => const SizedBox.shrink(),
              data: (List<String> values) {
                if (values.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceM,
                    vertical: DesignTokens.spaceS,
                  ),
                  itemCount: values.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: DesignTokens.spaceS),
                  itemBuilder: (BuildContext ctx, int i) {
                    if (i == 0) {
                      return ChoiceChip(
                        label: const Text('Tumu'),
                        selected: activeGroup == null,
                        onSelected: (_) => ref
                            .read(channelGroupFilterProvider.notifier)
                            .select(null),
                      );
                    }
                    final g = values[i - 1];
                    return ChoiceChip(
                      label: Text(g),
                      selected: activeGroup == g,
                      onSelected: (_) => ref
                          .read(channelGroupFilterProvider.notifier)
                          .select(g),
                    );
                  },
                );
              },
            ),
          ),
          Expanded(
            child: channels.when(
              loading: () => const LoadingView(label: 'Kanallar yukleniyor'),
              error: (Object err, StackTrace st) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(filteredLiveChannelsProvider),
              ),
              data: (List<Channel> values) {
                if (values.isEmpty) {
                  return EmptyState(
                    icon: Icons.live_tv_outlined,
                    title: 'Kanal bulunamadi',
                    message: activeGroup == null
                        ? 'Listeni yenileyip tekrar dene.'
                        : '"$activeGroup" grubunda kanal yok.',
                    actionLabel: 'Yenile',
                    onAction: () =>
                        ref.invalidate(filteredLiveChannelsProvider),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(filteredLiveChannelsProvider);
                    await ref.read(filteredLiveChannelsProvider.future);
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
                        itemCount: values.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final ch = values[i];
                          return ChannelTile(
                            name: ch.name,
                            logoUrl: ch.logoUrl,
                            group: ch.groups.isEmpty ? null : ch.groups.first,
                            onTap: () => _play(context, ch),
                            onLongPress: () =>
                                context.push('/channel/${ch.id}'),
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

    final source = MediaSource(
      url: channel.streamUrl,
      title: channel.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );

    final args = PlayerLaunchArgs(
      source: source,
      title: channel.name,
      subtitle: channel.groups.isEmpty ? null : channel.groups.first,
      itemId: channel.id,
      kind: HistoryKind.live,
      isLive: true,
    );

    context.push('/play', extra: args);
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
                    final args = PlayerLaunchArgs(
                      source: MediaSource(
                        url: c.streamUrl,
                        title: c.name,
                        userAgent: c.extras['http-user-agent'],
                      ),
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
