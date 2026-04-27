import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot live channel grid.
///
/// Reuses the same Riverpod data source as the mobile grid — only the
/// presentation differs (4-col responsive grid, larger tiles, focus ring).
class TvLiveScreen extends ConsumerWidget {
  const TvLiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(filteredLiveChannelsProvider);
    final groups = ref.watch(liveChannelGroupsProvider);
    final activeGroup = ref.watch(channelGroupFilterProvider);
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
            'Canli Kanallar',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          SizedBox(
            height: 56,
            child: groups.when(
              loading: () => const SizedBox.shrink(),
              error: (Object _, StackTrace __) => const SizedBox.shrink(),
              data: (List<String> values) {
                if (values.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: values.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: DesignTokens.spaceM),
                  itemBuilder: (BuildContext ctx, int i) {
                    final isAll = i == 0;
                    final g = isAll ? null : values[i - 1];
                    final selected =
                        isAll ? activeGroup == null : activeGroup == g;
                    return _GroupChip(
                      label: isAll ? 'Tumu' : g!,
                      selected: selected,
                      onTap: () => ref
                          .read(channelGroupFilterProvider.notifier)
                          .select(g),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Expanded(
            child: channels.when(
              loading: () => const LoadingView(label: 'Kanallar yukleniyor'),
              error: (Object err, StackTrace _) => ErrorView(
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
                return LayoutBuilder(
                  builder: (BuildContext _, BoxConstraints c) {
                    final cols = c.maxWidth > 1600 ? 5 : 4;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: DesignTokens.spaceL,
                        mainAxisSpacing: DesignTokens.spaceL,
                        childAspectRatio: 16 / 11,
                      ),
                      itemCount: values.length,
                      itemBuilder: (BuildContext _, int i) {
                        final ch = values[i];
                        return _TvChannelTile(
                          channel: ch,
                          autofocus: i == 0,
                          onPlay: () => _play(context, ch),
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

class _GroupChip extends StatefulWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_GroupChip> createState() => _GroupChipState();
}

class _GroupChipState extends State<_GroupChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      onShowFocusHighlight: (bool v) => setState(() => _focused = v),
      onShowHoverHighlight: (bool v) => setState(() => _focused = v),
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DesignTokens.motionFast,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceM,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.primary.withValues(alpha: 0.85)
                : scheme.surfaceContainerHighest
                    .withValues(alpha: _focused ? 0.95 : 0.6),
            borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
            border: Border.all(
              color: _focused
                  ? scheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: _focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.5),
                      blurRadius: 16,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.selected
                  ? Colors.white
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// TV-flavoured channel tile — bigger, focus-aware logo + name. Doesn't
/// reuse mobile's ChannelTile because that widget is glass + small text.
class _TvChannelTile extends StatelessWidget {
  const _TvChannelTile({
    required this.channel,
    required this.onPlay,
    this.autofocus = false,
  });

  final Channel channel;
  final VoidCallback onPlay;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FocusableTile(
      autofocus: autofocus,
      onTap: onPlay,
      semanticLabel: channel.name,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DesignTokens.radiusL),
                ),
                child: _LogoOrPlaceholder(channel: channel),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceM,
                vertical: DesignTokens.spaceS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (channel.groups.isNotEmpty)
                    Text(
                      channel.groups.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoOrPlaceholder extends StatelessWidget {
  const _LogoOrPlaceholder({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = channel.logoUrl;
    if (url == null || url.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              scheme.primary.withValues(alpha: 0.35),
              scheme.secondary.withValues(alpha: 0.20),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          channel.name.isEmpty ? '?' : channel.name.characters.first,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface.withValues(alpha: 0.9),
          ),
        ),
      );
    }
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        fadeInDuration: DesignTokens.motionFast,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
