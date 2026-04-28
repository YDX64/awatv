import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/channels/epg_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot live channel grid.
///
/// Reuses the same Riverpod data source as the mobile grid — only the
/// presentation differs (4-col responsive grid, larger tiles, focus ring).
///
/// A focusable "Rehber" button at the top swaps the body to a TV-optimised
/// EPG grid (larger row height, D-pad focus highlight, OK plays the
/// highlighted programme if it's airing now).
class TvLiveScreen extends ConsumerStatefulWidget {
  const TvLiveScreen({super.key});

  @override
  ConsumerState<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends ConsumerState<TvLiveScreen> {
  bool _showEpg = false;

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _showEpg ? 'TV Rehberi' : 'Canli Kanallar',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _RehberButton(
                active: _showEpg,
                onToggle: () => setState(() => _showEpg = !_showEpg),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceM),
          if (!_showEpg) ...<Widget>[
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
          ],
          Expanded(
            child: _showEpg
                ? _TvEpgGrid(
                    onPlay: (Channel ch) => _play(context, ch),
                  )
                : channels.when(
                    loading: () =>
                        const LoadingView(label: 'Kanallar yukleniyor'),
                    error: (Object err, StackTrace _) => ErrorView(
                      message: err.toString(),
                      onRetry: () =>
                          ref.invalidate(filteredLiveChannelsProvider),
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
                          onAction: () => ref
                              .invalidate(filteredLiveChannelsProvider),
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
}

/// TV-flavoured "Rehber" toggle. Renders as a pill with an icon + label.
/// Reacts to focus with the same brand glow as the rest of the TV UI.
class _RehberButton extends StatefulWidget {
  const _RehberButton({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback onToggle;

  @override
  State<_RehberButton> createState() => _RehberButtonState();
}

class _RehberButtonState extends State<_RehberButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (bool v) => setState(() => _focused = v),
      onShowHoverHighlight: (bool v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onToggle();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            widget.onToggle();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: DesignTokens.motionFast,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceM,
          ),
          decoration: BoxDecoration(
            color: widget.active
                ? scheme.primary.withValues(alpha: 0.85)
                : scheme.surfaceContainerHighest
                    .withValues(alpha: _focused ? 0.95 : 0.6),
            borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.active ? Icons.grid_view : Icons.grid_view_outlined,
                size: 24,
                color: widget.active ? Colors.white : scheme.onSurface,
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Text(
                'Rehber',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: widget.active ? Colors.white : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV-optimized EPG grid view.
///
/// Larger row height for readability from the couch + a focus model where
/// the user moves a "current" cell pointer with arrow keys and OK plays
/// the highlighted programme when it's airing now.
class _TvEpgGrid extends ConsumerStatefulWidget {
  const _TvEpgGrid({required this.onPlay});

  final ValueChanged<Channel> onPlay;

  @override
  ConsumerState<_TvEpgGrid> createState() => _TvEpgGridState();
}

class _TvEpgGridState extends ConsumerState<_TvEpgGrid> {
  final EpgGridScrollController _scroll = EpgGridScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'tv-epg-focus');

  // 2-D cursor over (channelIndex, programmeIndex within row).
  int _row = 0;
  int _col = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(filteredLiveChannelsProvider);
    final clockAsync = ref.watch(epgClockProvider);
    final now = clockAsync.valueOrNull ?? DateTime.now();
    final scheme = Theme.of(context).colorScheme;

    return channelsAsync.when(
      loading: () => const LoadingView(label: 'Rehber yukleniyor'),
      error: (Object err, StackTrace _) => ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(filteredLiveChannelsProvider),
      ),
      data: (List<Channel> channels) {
        if (channels.isEmpty) {
          return const EmptyState(
            icon: Icons.live_tv_outlined,
            title: 'Kanal yok',
          );
        }
        final tvgIds = <String>[
          for (final c in channels)
            if (c.tvgId != null && c.tvgId!.isNotEmpty) c.tvgId!,
        ];
        final epgKey = EpgWindowKey(tvgIds: tvgIds);
        final epgAsync = ref.watch(epgWindowProvider(epgKey));

        return epgAsync.when(
          loading: () => const LoadingView(label: 'EPG hazirlaniyor'),
          error: (Object err, StackTrace _) => ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(epgWindowProvider(epgKey)),
          ),
          data: (Map<String, List<EpgProgramme>> byChannel) {
            // Bound the cursor to the current data shape.
            if (_row >= channels.length) _row = channels.length - 1;
            if (_row < 0) _row = 0;
            final row = channels[_row];
            final rowProgs = byChannel[row.tvgId ?? ''] ??
                const <EpgProgramme>[];
            final cappedCol = rowProgs.isEmpty
                ? 0
                : _col.clamp(0, rowProgs.length - 1);
            final focusedId = rowProgs.isEmpty
                ? null
                : '${rowProgs[cappedCol].channelTvgId}@${rowProgs[cappedCol].start.toIso8601String()}';

            final gridChannels = <EpgGridChannel>[
              for (final c in channels)
                EpgGridChannel(
                  id: c.id,
                  tvgId: c.tvgId ?? '',
                  name: c.name,
                  logoUrl: c.logoUrl,
                  subtitle: c.groups.isEmpty ? null : c.groups.first,
                ),
            ];
            final mapped = <String, List<EpgGridProgramme>>{};
            byChannel.forEach((String tvgId, List<EpgProgramme> list) {
              mapped[tvgId] = <EpgGridProgramme>[
                for (final p in list)
                  EpgGridProgramme(
                    id: '${p.channelTvgId}@${p.start.toIso8601String()}',
                    tvgId: p.channelTvgId,
                    start: p.start,
                    stop: p.stop,
                    title: p.title,
                    description: p.description,
                    category: p.category,
                  ),
              ];
            });

            return Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (FocusNode _, KeyEvent event) =>
                  _onKey(event, channels, byChannel, now),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusL),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: EpgGrid(
                  channels: gridChannels,
                  programmes: mapped,
                  now: now,
                  pixelsPerMinute: 8,
                  rowHeight: 96,
                  channelColumnWidth: 220,
                  timeRowHeight: 56,
                  scrollController: _scroll,
                  focusedProgrammeId: focusedId,
                  onProgrammeTap: (event) {
                    final ch = channels.firstWhere(
                      (Channel c) => c.id == event.channel.id,
                      orElse: () => channels.first,
                    );
                    final p = event.programme;
                    final isLive = !now.isBefore(p.start) &&
                        now.isBefore(p.stop);
                    if (isLive) widget.onPlay(ch);
                  },
                  onChannelTap: (gridCh) {
                    final ch = channels.firstWhere(
                      (Channel c) => c.id == gridCh.id,
                      orElse: () => channels.first,
                    );
                    widget.onPlay(ch);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  KeyEventResult _onKey(
    KeyEvent event,
    List<Channel> channels,
    Map<String, List<EpgProgramme>> byChannel,
    DateTime now,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_row > 0) {
        setState(() {
          _row -= 1;
          _col = 0;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_row < channels.length - 1) {
        setState(() {
          _row += 1;
          _col = 0;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final tvg = channels[_row].tvgId ?? '';
    final rowList = byChannel[tvg] ?? const <EpgProgramme>[];
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_col > 0) {
        setState(() => _col -= 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_col < rowList.length - 1) {
        setState(() => _col += 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      if (rowList.isEmpty) return KeyEventResult.ignored;
      final p = rowList[_col.clamp(0, rowList.length - 1)];
      final isLive = !now.isBefore(p.start) && now.isBefore(p.stop);
      if (isLive) widget.onPlay(channels[_row]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
