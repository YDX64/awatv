import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/catchup/catchup_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Catchup / replay TV screen.
///
/// Two-pane layout (rail of catchup-eligible channels on the left, list
/// of past programmes on the right). On phones the rail collapses to a
/// horizontally-scrolling chip strip above the list.
///
/// Catchup is a Premium-gated feature — free users still see the screen
/// (so they understand what they get with premium) but past programmes
/// surface a paywall on tap.
class CatchupScreen extends ConsumerWidget {
  const CatchupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(catchupChannelsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catchup'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(catchupChannelsProvider),
          ),
        ],
      ),
      body: channelsAsync.when(
        loading: () => const LoadingView(label: 'Catchup hazirlaniyor'),
        error: (Object err, StackTrace _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(catchupChannelsProvider),
        ),
        data: (List<Channel> channels) {
          if (channels.isEmpty) {
            return EmptyState(
              icon: Icons.replay_circle_filled_outlined,
              title: 'Catchup destegi yok',
              message:
                  'Catchup, Xtream Codes panellerinde calisir. Bir Xtream '
                  'listesi ekledikten sonra burada gecmis 24-72 saatin '
                  'kanallari listelenir.',
              actionLabel: 'Listeleri yonet',
              onAction: () => context.push('/playlists'),
            );
          }
          final selectedId = ref.watch(selectedCatchupChannelIdProvider);
          // Auto-select the first channel on first paint so the
          // programmes pane has something to render.
          final activeId = selectedId ?? channels.first.id;
          if (selectedId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(selectedCatchupChannelIdProvider.notifier)
                  .select(activeId);
            });
          }
          return LayoutBuilder(
            builder: (BuildContext _, BoxConstraints constraints) {
              final wide = constraints.maxWidth >= 720;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: 280,
                      child: _ChannelRail(
                        channels: channels,
                        activeId: activeId,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _ProgrammesPane(channelId: activeId),
                    ),
                  ],
                );
              }
              return Column(
                children: <Widget>[
                  _ChannelChips(
                    channels: channels,
                    activeId: activeId,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _ProgrammesPane(channelId: activeId),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ChannelRail extends ConsumerWidget {
  const _ChannelRail({required this.channels, required this.activeId});

  final List<Channel> channels;
  final String activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (BuildContext _, int i) {
        final c = channels[i];
        final selected = c.id == activeId;
        return Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          child: InkWell(
            onTap: () => ref
                .read(selectedCatchupChannelIdProvider.notifier)
                .select(c.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceM,
                vertical: DesignTokens.spaceS,
              ),
              child: Row(
                children: <Widget>[
                  _ChannelLogo(url: c.logoUrl),
                  const SizedBox(width: DesignTokens.spaceM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? scheme.primary : null,
                          ),
                        ),
                        if (c.groups.isNotEmpty)
                          Text(
                            c.groups.first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelChips extends ConsumerWidget {
  const _ChannelChips({required this.channels, required this.activeId});

  final List<Channel> channels;
  final String activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceS,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: DesignTokens.spaceXs),
        itemBuilder: (BuildContext _, int i) {
          final c = channels[i];
          final selected = c.id == activeId;
          return ChoiceChip(
            label: Text(c.name),
            selected: selected,
            onSelected: (_) => ref
                .read(selectedCatchupChannelIdProvider.notifier)
                .select(c.id),
          );
        },
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      child: Icon(
        Icons.live_tv_outlined,
        size: 18,
        color: scheme.onSurface.withValues(alpha: 0.5),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => placeholder,
        placeholder: (_, __) => placeholder,
      ),
    );
  }
}

class _ProgrammesPane extends ConsumerWidget {
  const _ProgrammesPane({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progAsync = ref.watch(catchupProgrammesProvider(channelId));
    return progAsync.when(
      loading: () => const LoadingView(label: 'Programlar yukleniyor'),
      error: (Object err, StackTrace _) => ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(catchupProgrammesProvider(channelId)),
      ),
      data: (List<CatchupProgramme> all) {
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.history_toggle_off_outlined,
            title: 'Bu kanalda arsiv yok',
            message:
                'Panel bu kanal icin gecmis programlari saklamiyor. '
                'Diger bir kanali secebilirsin.',
          );
        }
        // Sort newest first so the most recent past programmes are on
        // top — mirrors what users expect from a "geri sar" surface.
        final sorted = [...all]..sort((a, b) => b.start.compareTo(a.start));
        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          itemCount: sorted.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: DesignTokens.spaceXs),
          itemBuilder: (BuildContext _, int i) {
            final p = sorted[i];
            return _ProgrammeRow(channelId: channelId, programme: p);
          },
        );
      },
    );
  }
}

class _ProgrammeRow extends ConsumerWidget {
  const _ProgrammeRow({
    required this.channelId,
    required this.programme,
  });

  final String channelId;
  final CatchupProgramme programme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isPast = programme.isPast(now);
    final isFuture = programme.isFuture(now);
    final isLive = !isPast && !isFuture;
    final canPlay = programme.hasArchive && (isPast || isLive);

    final start = programme.start.toLocal();
    final stop = programme.stop.toLocal();
    final dateLabel = '${_pad(start.day)}.${_pad(start.month)} '
        '${_pad(start.hour)}:${_pad(start.minute)} - '
        '${_pad(stop.hour)}:${_pad(stop.minute)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        onTap: canPlay ? () => _onPlay(context, ref) : null,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.18),
            ),
          ),
          padding: const EdgeInsets.all(DesignTokens.spaceM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 6,
                height: 56,
                decoration: BoxDecoration(
                  color: !programme.hasArchive
                      ? scheme.onSurface.withValues(alpha: 0.18)
                      : isLive
                          ? scheme.tertiary
                          : isFuture
                              ? scheme.outline
                              : scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      programme.title.isEmpty ? 'Program' : programme.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    if (programme.description != null &&
                        programme.description!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: DesignTokens.spaceXs),
                      Text(
                        programme.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              if (!programme.hasArchive)
                _RowBadge(
                  label: 'arsiv yok',
                  color: scheme.onSurface.withValues(alpha: 0.4),
                )
              else if (isLive)
                _RowBadge(
                  label: 'simdi',
                  color: scheme.tertiary,
                )
              else if (isFuture)
                _RowBadge(
                  label: 'yakin',
                  color: scheme.outline,
                )
              else
                IconButton(
                  tooltip: 'Geri sar',
                  icon: const Icon(Icons.replay_rounded),
                  onPressed: () => _onPlay(context, ref),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPlay(BuildContext context, WidgetRef ref) async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.catchup));
    if (!allowed) {
      await PremiumLockSheet.show(context, PremiumFeature.catchup);
      return;
    }
    final channelsAsync = ref.read(catchupChannelsProvider);
    Channel? channel;
    for (final c in channelsAsync.value ?? const <Channel>[]) {
      if (c.id == channelId) {
        channel = c;
        break;
      }
    }
    if (channel == null) return;
    final svc = ref.read(catchupServiceProvider);
    final url = await svc.urlForCatchup(channel, programme);
    if (url == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Catchup URL olusturulamadi.'),
        ),
      );
      return;
    }
    if (!context.mounted) return;
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
      title: '${channel.name} • ${programme.title}',
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final args = PlayerLaunchArgs(
      source: src,
      title: programme.title,
      subtitle: channel.name,
      itemId: '${channel.id}::catchup::${programme.start.toIso8601String()}',
      kind: HistoryKind.live,
      // Catchup is technically a finite stream — but Xtream timeshift
      // returns it as TS-over-HTTP without seek, so treat as live.
      isLive: kIsWeb,
    );
    context.push('/play', extra: args);
  }
}

class _RowBadge extends StatelessWidget {
  const _RowBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

String _pad(int v) => v.toString().padLeft(2, '0');
