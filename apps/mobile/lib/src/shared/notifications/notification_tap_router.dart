import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/notifications/awatv_notifications.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Listens for OS notification taps and deep-links the app to the right
/// surface — `/play` for an EPG reminder when the channel id resolves,
/// `/reminders` otherwise.
///
/// Wired in `awa_tv_app.dart` via a [ConsumerStatefulWidget] subtree that
/// grabs the GoRouter so we can push from a non-widget callback.
class NotificationTapRouter extends ConsumerStatefulWidget {
  const NotificationTapRouter({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationTapRouter> createState() =>
      _NotificationTapRouterState();
}

class _NotificationTapRouterState
    extends ConsumerState<NotificationTapRouter> {
  StreamSubscription<NotificationTap>? _sub;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(awatvNotificationsProvider);
    _sub = notifier.tapsStream.listen(_onTap);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onTap(NotificationTap tap) async {
    if (!mounted) return;
    if (tap.kind != 'reminder') return;
    final channelId = tap.channelId;
    if (channelId == null || channelId.isEmpty) {
      // Best we can do is take them to the reminders list.
      if (mounted) GoRouter.of(context).push('/reminders');
      return;
    }
    Channel? channel;
    try {
      channel = await ref.read(channelByIdProvider(channelId).future);
    } on Object {
      channel = null;
    }
    if (!mounted) return;
    if (channel == null) {
      GoRouter.of(context).push('/reminders');
      return;
    }
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
      itemId: channel.id,
      kind: HistoryKind.live,
      isLive: true,
    );
    if (!mounted) return;
    if (tap.autoTuneIn) {
      GoRouter.of(context).push('/play', extra: args);
    } else {
      // Default: take user to reminders so they can decide. Tapping the
      // entry in that screen plays the channel.
      GoRouter.of(context).push('/reminders');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
