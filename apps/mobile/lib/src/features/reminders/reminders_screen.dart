import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Lists every upcoming "Hatirlat" the user has set.
///
/// Each row exposes:
///   * Channel logo + name
///   * Programme title
///   * "Bugun 21:30" / "29 Nisan 19:00" rendered with `intl`
///   * "Otomatik gec" toggle (switches to the channel right when the
///     notification fires)
///   * "Iptal" action which cancels both the persisted entry and the
///     scheduled OS notification
///
/// Empty state nudges the user to set a reminder from `/live/epg`.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(upcomingRemindersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hatirlatmalar'),
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace _) =>
            ErrorView(message: err.toString()),
        data: (List<Reminder> list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_active_outlined,
              title: 'Henuz hatirlatma yok',
              message: 'Bir programi kacirmak istemiyorsan TV Rehberi '
                  'ekraninda "Hatirlat" dugmesine bas.',
              actionLabel: 'Rehbere git',
              onAction: () => context.go('/live/epg'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: DesignTokens.spaceS),
            itemBuilder: (BuildContext ctx, int i) =>
                _ReminderTile(reminder: list[i]),
          );
        },
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final localStart = reminder.start.toLocal();
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openChannel(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _ChannelArtwork(
                logoUrl: reminder.channelLogoUrl,
                channelName: reminder.channelName,
              ),
              const SizedBox(width: DesignTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      reminder.programmeTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reminder.channelName,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _humanWhen(localStart),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Tooltip(
                    message: reminder.autoTuneIn
                        ? 'Otomatik gecis acik'
                        : 'Otomatik gecis kapali',
                    child: Switch(
                      value: reminder.autoTuneIn,
                      onChanged: (bool v) async {
                        await ref
                            .read(remindersServiceProvider)
                            .setAutoTuneIn(reminder.id, value: v);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            content: Text(
                              v
                                  ? 'Yayin basladiginda kanal otomatik acilacak'
                                  : 'Otomatik gecis kapatildi',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(remindersServiceProvider)
                          .cancel(reminder.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          duration: Duration(seconds: 2),
                          content: Text('Hatirlatma iptal edildi'),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Iptal'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openChannel(BuildContext context, WidgetRef ref) async {
    final channel = await ref.read(
      channelByIdProvider(reminder.channelId).future,
    );
    if (channel == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${reminder.channelName} listede bulunamadi — '
            'kaynak yenilenmis olabilir.',
          ),
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
      subtitle: reminder.programmeTitle,
      itemId: channel.id,
      kind: HistoryKind.live,
      isLive: true,
    );
    context.push('/play', extra: args);
  }

  static String _humanWhen(DateTime localStart) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(
      localStart.year,
      localStart.month,
      localStart.day,
    );
    final diff = startDay.difference(today).inDays;
    final hhmm = DateFormat('HH:mm').format(localStart);
    if (diff == 0) return 'Bugun • $hhmm';
    if (diff == 1) return 'Yarin • $hhmm';
    final dayMonth =
        DateFormat('d MMM', 'tr_TR').format(localStart);
    return '$dayMonth • $hhmm';
  }
}

class _ChannelArtwork extends StatelessWidget {
  const _ChannelArtwork({
    required this.logoUrl,
    required this.channelName,
  });

  final String? logoUrl;
  final String channelName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _resolveArtwork(scheme),
    );
  }

  Widget _resolveArtwork(ColorScheme scheme) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        errorWidget: (BuildContext _, String __, Object ___) =>
            _fallback(scheme),
      );
    }
    return _fallback(scheme);
  }

  Widget _fallback(ColorScheme scheme) {
    final fallback = LogosFallback.urlFor(channelName);
    if (fallback != null) {
      return CachedNetworkImage(
        imageUrl: fallback,
        fit: BoxFit.contain,
        errorWidget: (BuildContext _, String __, Object ___) =>
            _initials(scheme),
      );
    }
    return _initials(scheme);
  }

  Widget _initials(ColorScheme scheme) {
    final letter = channelName.isNotEmpty
        ? channelName.characters.first.toUpperCase()
        : '?';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.4),
            scheme.surface,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
