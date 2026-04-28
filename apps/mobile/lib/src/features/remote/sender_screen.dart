import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/pair_code.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:awatv_mobile/src/shared/remote/sender_provider.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sender-side surface — the phone acting as a remote control.
///
/// Two states:
///   1. No code yet → keypad form. The user pastes / types the 6-char code
///      they see on the receiver and taps "Connect".
///   2. Code set → connection screen. Subscribes to the Supabase channel,
///      shows a now-playing card and the remote-control surface.
///
/// `code` is supplied through a query parameter on the route so deep
/// links from a QR scan auto-connect without manual entry.
class SenderScreen extends ConsumerStatefulWidget {
  const SenderScreen({this.initialCode, super.key});

  /// Optional pre-filled pair code, normally extracted from `?code=` on
  /// the route. Falls through the keypad form so the user can also fix
  /// typos before submitting.
  final String? initialCode;

  @override
  ConsumerState<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends ConsumerState<SenderScreen> {
  String? _activeCode;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialCode;
    if (raw != null) {
      final n = normalisePairCode(raw);
      if (isValidPairCode(n)) _activeCode = n;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.hasSupabase) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kumanda')),
        body: const Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Bulut baglantisi gerekli',
            subtitle: 'Uzaktan kumanda icin AWAtv hesabi gerekiyor.',
          ),
        ),
      );
    }

    final code = _activeCode;
    if (code == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kumanda')),
        body: _PairForm(
          onSubmitted: (String c) => setState(() => _activeCode = c),
        ),
      );
    }

    return _SenderConnected(
      code: code,
      onDisconnect: () => setState(() => _activeCode = null),
    );
  }
}

class _PairForm extends StatefulWidget {
  const _PairForm({required this.onSubmitted});
  final ValueChanged<String> onSubmitted;

  @override
  State<_PairForm> createState() => _PairFormState();
}

class _PairFormState extends State<_PairForm> {
  late final TextEditingController _ctrl = TextEditingController();
  String _normalised = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = isValidPairCode(_normalised);

    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: DesignTokens.spaceL),
          Icon(
            Icons.settings_remote_rounded,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            'Eslestirme kodu',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Yayini gosteren cihazinda goeruelen 6 haneli kodu gir.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              hintText: 'ABC234',
              border: OutlineInputBorder(),
            ),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(kPairCodeLength),
            ],
            onChanged: (String v) {
              setState(() => _normalised = normalisePairCode(v));
            },
            onSubmitted: (String _) {
              if (canSubmit) widget.onSubmitted(_normalised);
            },
          ),
          const SizedBox(height: DesignTokens.spaceL),
          FilledButton(
            onPressed: canSubmit
                ? () => widget.onSubmitted(_normalised)
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Bagla'),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          // QR scanner is intentionally deferred — we don't have a
          // mobile_scanner dependency yet (see CLAUDE.md). Once it ships,
          // a "Tara" button replaces this hint.
          Text(
            'Ipucu: Diger cihazda gosterilen QR koda tarayicidan dokunarak buraya yonlendirilebilirsin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderConnected extends ConsumerWidget {
  const _SenderConnected({required this.code, required this.onDisconnect});
  final String code;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSession =
        ref.watch(senderSessionControllerProvider(code));

    return Scaffold(
      appBar: AppBar(
        title: Text('Kumanda  ·  $code'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Baglantiyi kes',
            icon: const Icon(Icons.link_off_rounded),
            onPressed: () {
              ref.invalidate(senderSessionControllerProvider(code));
              onDisconnect();
            },
          ),
        ],
      ),
      body: asyncSession.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Baglanilamadi',
            subtitle: e.toString(),
            action: FilledButton(
              onPressed: onDisconnect,
              child: const Text('Tekrar dene'),
            ),
          ),
        ),
        data: (SenderSession session) => _RemoteSurface(
          code: code,
          session: session,
        ),
      ),
    );
  }
}

class _RemoteSurface extends ConsumerWidget {
  const _RemoteSurface({required this.code, required this.session});

  final String code;
  final SenderSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(senderSessionControllerProvider(code).notifier);
    final receiverState = session.receiverState;
    final canControl = session.peerOnline &&
        session.connection == RemoteConnectionState.connected;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _NowPlayingCard(rstate: receiverState, peerOnline: session.peerOnline),
            const SizedBox(height: DesignTokens.spaceL),
            _TransportControls(
              receiver: receiverState,
              enabled: canControl,
              onPlayPause: () =>
                  controller.sendCommand(const RemotePlayPauseCommand()),
              onBack10: () => controller
                  .sendCommand(const RemoteSeekRelativeCommand(seconds: -10)),
              onForward10: () => controller
                  .sendCommand(const RemoteSeekRelativeCommand(seconds: 10)),
            ),
            const SizedBox(height: DesignTokens.spaceL),
            _VolumeRow(
              receiver: receiverState,
              enabled: canControl,
              onVolume: (double v) =>
                  controller.sendCommand(RemoteVolumeCommand(volume: v)),
              onToggleMute: () => controller
                  .sendCommand(RemoteMuteCommand(muted: !receiverState.muted)),
            ),
            const SizedBox(height: DesignTokens.spaceL),
            _ChannelRow(
              enabled: canControl,
              onPrev: () {
                final id = receiverState.currentChannelId;
                if (id == null || id.isEmpty) return;
                controller
                    .sendCommand(RemoteChannelChangeCommand(channelId: '$id::-'));
              },
              onNext: () {
                final id = receiverState.currentChannelId;
                if (id == null || id.isEmpty) return;
                controller
                    .sendCommand(RemoteChannelChangeCommand(channelId: '$id::+'));
              },
              onOpenGuide: () => controller
                  .sendCommand(const RemoteOpenScreenCommand(route: '/live')),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.rstate, required this.peerOnline});
  final ReceiverState rstate;
  final bool peerOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final title = rstate.currentTitle ?? 'Yayin yok';
    final subtitle = rstate.currentSubtitle ??
        (peerOnline ? 'Cihazda oynatma yok' : 'Yayin cihazi cevrimdisi');
    final art = rstate.currentArtwork;

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            child: SizedBox(
              width: 72,
              height: 72,
              child: art != null && art.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: art,
                      fit: BoxFit.cover,
                      placeholder: (BuildContext _, String __) =>
                          ColoredBox(color: scheme.surface),
                      errorWidget: (BuildContext _, String __, Object ___) =>
                          Container(
                        color: scheme.surface,
                        child: const Icon(Icons.tv_rounded),
                      ),
                    )
                  : Container(
                      color: scheme.surface,
                      child: const Icon(Icons.tv_rounded),
                    ),
            ),
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                _PlaybackBadge(playback: rstate.playback),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({required this.playback});
  final ReceiverPlayback playback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (playback) {
      ReceiverPlayback.playing => ('Oynatiliyor', Colors.greenAccent),
      ReceiverPlayback.paused => ('Duraklatildi', theme.colorScheme.primary),
      ReceiverPlayback.loading => ('Yukleniyor', theme.colorScheme.secondary),
      ReceiverPlayback.ended => ('Bitti', theme.colorScheme.outline),
      ReceiverPlayback.error => ('Hata', theme.colorScheme.error),
      ReceiverPlayback.idle => ('Bekliyor', theme.colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.receiver,
    required this.enabled,
    required this.onPlayPause,
    required this.onBack10,
    required this.onForward10,
  });

  final ReceiverState receiver;
  final bool enabled;
  final VoidCallback onPlayPause;
  final VoidCallback onBack10;
  final VoidCallback onForward10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = receiver.isPlaying;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _CircleIconButton(
          icon: Icons.replay_10_rounded,
          enabled: enabled,
          onTap: onBack10,
          size: 56,
        ),
        SizedBox(
          width: 80,
          height: 80,
          child: Material(
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.3),
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPlayPause : null,
              child: Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: theme.colorScheme.onPrimary,
                size: 44,
              ),
            ),
          ),
        ),
        _CircleIconButton(
          icon: Icons.forward_10_rounded,
          enabled: enabled,
          onTap: onForward10,
          size: 56,
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.size = 48,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.receiver,
    required this.enabled,
    required this.onVolume,
    required this.onToggleMute,
  });

  final ReceiverState receiver;
  final bool enabled;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: receiver.muted ? 'Sesi ac' : 'Sessiz',
          onPressed: enabled ? onToggleMute : null,
          icon: Icon(
            receiver.muted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        Expanded(
          child: Slider(
            value: receiver.muted ? 0 : receiver.volume.clamp(0.0, 1.0),
            onChanged: enabled ? onVolume : null,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(receiver.volume * 100).round()}%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.enabled,
    required this.onPrev,
    required this.onNext,
    required this.onOpenGuide,
  });

  final bool enabled;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: enabled ? onPrev : null,
          icon: const Icon(Icons.skip_previous_rounded),
          label: const Text('Kanal -'),
        ),
        FilledButton.tonalIcon(
          onPressed: enabled ? onOpenGuide : null,
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Rehber'),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Kanal +'),
        ),
      ],
    );
  }
}
