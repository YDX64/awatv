import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/channels/epg_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
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

/// TV-Rehberi screen.
///
/// Shows the live channels as rows × time as columns. The data flow is:
///   - `filteredLiveChannelsProvider` → channels in the active group
///   - `epgWindowProvider` → batched programmes for those channels
///   - `epgClockProvider` → ticking now-line / airing-now styling
///
/// Tapping a programme tile picks an action depending on its time bucket:
///   - airing now → push `/play` with the channel
///   - past or future → bottom-sheet with details + "Hatırlat" (premium)
class EpgGridScreen extends ConsumerStatefulWidget {
  const EpgGridScreen({super.key});

  @override
  ConsumerState<EpgGridScreen> createState() => _EpgGridScreenState();
}

class _EpgGridScreenState extends ConsumerState<EpgGridScreen> {
  final EpgGridScrollController _scroll = EpgGridScrollController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channelsAsync = ref.watch(filteredLiveChannelsProvider);
    final clockAsync = ref.watch(epgClockProvider);
    final activeGroup = ref.watch(channelGroupFilterProvider);

    final now = clockAsync.valueOrNull ?? DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TV Rehberi'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Şimdi',
            icon: const Icon(Icons.adjust_rounded),
            onPressed: _scroll.scrollToNow,
          ),
        ],
      ),
      body: channelsAsync.when(
        loading: () => const LoadingView(label: 'Rehber yukleniyor'),
        error: (Object err, StackTrace _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(filteredLiveChannelsProvider),
        ),
        data: (List<Channel> channels) {
          if (channels.isEmpty) {
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

          // Build the EPG-grid channel list. Channels without a tvg-id stay
          // in the rows but render the "EPG yok" placeholder.
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
              // Translate core EpgProgramme → grid programmes.
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

              return Padding(
                padding: const EdgeInsets.all(DesignTokens.spaceM),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusL),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  child: EpgGrid(
                    channels: gridChannels,
                    programmes: mapped,
                    now: now,
                    scrollController: _scroll,
                    onProgrammeTap: (event) =>
                        _onProgrammeTap(channels, event, now),
                    onChannelTap: (gridCh) =>
                        _onChannelTap(channels, gridCh),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _onChannelTap(List<Channel> channels, EpgGridChannel ch) {
    context.push('/channel/${ch.id}');
  }

  void _onProgrammeTap(
    List<Channel> channels,
    EpgGridProgrammeEvent event,
    DateTime now,
  ) {
    final ch = channels.firstWhere(
      (Channel c) => c.id == event.channel.id,
      orElse: () => channels.first,
    );
    final p = event.programme;
    final isLive = !now.isBefore(p.start) && now.isBefore(p.stop);
    if (isLive) {
      _play(ch);
    } else {
      _showProgrammeDetails(ch, p, now);
    }
  }

  void _play(Channel channel) {
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

  Future<void> _showProgrammeDetails(
    Channel channel,
    EpgGridProgramme p,
    DateTime now,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetCtx) => _ProgrammeDetailSheet(
        channel: channel,
        programme: p,
        now: now,
        onPlay: () {
          Navigator.of(sheetCtx).pop();
          _play(channel);
        },
        onRemind: () => _onRemind(sheetCtx, channel, p),
        onCatchup: () => _onCatchup(sheetCtx, channel, p),
      ),
    );
  }

  Future<void> _onCatchup(
    BuildContext sheetCtx,
    Channel channel,
    EpgGridProgramme p,
  ) async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.catchup));
    if (!allowed) {
      Navigator.of(sheetCtx).pop();
      if (!mounted) return;
      await PremiumLockSheet.show(context, PremiumFeature.catchup);
      return;
    }
    final svc = ref.read(catchupServiceProvider);
    final epgProg = EpgProgramme(
      channelTvgId: channel.tvgId ?? channel.id,
      start: p.start,
      stop: p.stop,
      title: p.title,
      description: p.description,
      category: p.category,
    );
    final url = await svc.urlForEpg(channel, epgProg);
    if (url == null) {
      if (!mounted) return;
      Navigator.of(sheetCtx).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu kanal icin catchup URL olusturulamadi (M3U veya '
            'Xtream disi kaynak).',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(sheetCtx).pop();

    final headers = <String, String>{};
    final ua = channel.extras['http-user-agent'] ??
        channel.extras['user-agent'];
    final referer = channel.extras['http-referrer'] ??
        channel.extras['referer'] ??
        channel.extras['Referer'];
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    final src = MediaSource(
      url: url,
      title: '${channel.name} • ${p.title}',
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final args = PlayerLaunchArgs(
      source: src,
      title: p.title,
      subtitle: channel.name,
      itemId: '${channel.id}::catchup::${p.start.toIso8601String()}',
      kind: HistoryKind.live,
    );
    context.push('/play', extra: args);
  }

  Future<void> _onRemind(
    BuildContext sheetCtx,
    Channel channel,
    EpgGridProgramme p,
  ) async {
    final allowed = ref.read(canUseFeatureProvider(PremiumFeature.cloudSync));
    if (!allowed) {
      Navigator.of(sheetCtx).pop();
      if (!mounted) return;
      await PremiumLockSheet.show(context, PremiumFeature.cloudSync);
      return;
    }
    // Premium reminder scheduling is deferred — confirm intent and close.
    Navigator.of(sheetCtx).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${p.title}" hatirlatici eklendi'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ProgrammeDetailSheet extends StatelessWidget {
  const _ProgrammeDetailSheet({
    required this.channel,
    required this.programme,
    required this.now,
    required this.onPlay,
    required this.onRemind,
    required this.onCatchup,
  });

  final Channel channel;
  final EpgGridProgramme programme;
  final DateTime now;
  final VoidCallback onPlay;
  final VoidCallback onRemind;
  final VoidCallback onCatchup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFuture = programme.start.isAfter(now);
    final isPast = programme.stop.isBefore(now);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXL),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceL,
          DesignTokens.spaceM,
          DesignTokens.spaceL,
          DesignTokens.spaceL,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusS),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              channel.name,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              programme.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              '${_fmt(programme.start)} – ${_fmt(programme.stop)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (programme.category != null &&
                programme.category!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceS),
              _CategoryChip(label: programme.category!),
            ],
            if (programme.description != null &&
                programme.description!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              Text(
                programme.description!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: DesignTokens.spaceL),
            if (isFuture)
              FilledButton.icon(
                onPressed: onRemind,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Hatirlat'),
              )
            else if (isPast) ...<Widget>[
              FilledButton.icon(
                onPressed: onCatchup,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Geri sar'),
              ),
              const SizedBox(height: DesignTokens.spaceS),
              OutlinedButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.live_tv_outlined),
                label: const Text('Kanali simdi ac'),
              ),
            ] else
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Simdi izle'),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceS,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
