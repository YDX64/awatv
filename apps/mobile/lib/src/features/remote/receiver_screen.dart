import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/remote/receiver_provider.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart';
import 'package:awatv_mobile/src/shared/remote/remote_protocol.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Receiver-side surface — the device that's showing the video.
///
/// On boot:
///   * generates a 6-character pair code,
///   * subscribes to the corresponding Supabase Realtime channel,
///   * shows a big QR + the typed code so a phone can scan or read it,
///   * lists incoming commands as they arrive.
///
/// The pairing URL is intentionally namespaced under the deployed web app
/// so a sender can paste it into any browser to land directly on the
/// /remote/send route.
const String _kPairingBaseUrl = 'https://awa-tv.awastats.com/#/remote/send';

class ReceiverScreen extends ConsumerWidget {
  const ReceiverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.hasSupabase) {
      return Scaffold(
        appBar: AppBar(title: const Text('Yayin ekrani')),
        body: const Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Bulut baglantisi gerekli',
            subtitle: 'Uzaktan kumanda icin AWAtv hesabi gerekiyor.',
          ),
        ),
      );
    }

    final session = ref.watch(receiverSessionControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Yayin ekrani')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Baglanilamadi',
            subtitle: e.toString(),
          ),
        ),
        data: (ReceiverSession data) => _ReceiverBody(session: data),
      ),
    );
  }
}

class _ReceiverBody extends ConsumerWidget {
  const _ReceiverBody({required this.session});
  final ReceiverSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pairingUrl = '$_kPairingBaseUrl?code=${session.code}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Telefonunu kumandaya cevir',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Telefonun kamerasini asagidaki QR koduna tut, ya da kodu manuel gir.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          Center(child: _QrPanel(data: pairingUrl)),
          const SizedBox(height: DesignTokens.spaceL),
          Center(child: _CodeDisplay(code: session.code)),
          const SizedBox(height: DesignTokens.spaceL),
          _ConnectionLine(
            connection: session.connection,
            peerOnline: session.peerOnline,
          ),
          const SizedBox(height: DesignTokens.spaceL),
          if (session.recentCommands.isNotEmpty) ...<Widget>[
            Text('Son komutlar', style: theme.textTheme.titleSmall),
            const SizedBox(height: DesignTokens.spaceS),
            _RecentCommandsList(commands: session.recentCommands),
            const SizedBox(height: DesignTokens.spaceL),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Paylasimi durdur'),
            onPressed: () async {
              await ref
                  .read(receiverSessionControllerProvider.notifier)
                  .stop();
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: QrImageView(
        data: data,
        size: 240,
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Kopyalamak icin dokun',
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kod kopyalandi: $code'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          child: Text(
            code,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionLine extends StatefulWidget {
  const _ConnectionLine({required this.connection, required this.peerOnline});
  final RemoteConnectionState connection;
  final bool peerOnline;

  @override
  State<_ConnectionLine> createState() => _ConnectionLineState();
}

class _ConnectionLineState extends State<_ConnectionLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = widget.peerOnline &&
        widget.connection == RemoteConnectionState.connected;
    final color = connected
        ? Colors.greenAccent
        : (widget.connection == RemoteConnectionState.error
            ? theme.colorScheme.error
            : theme.colorScheme.primary);

    final label = switch ((widget.connection, widget.peerOnline)) {
      (RemoteConnectionState.connecting, _) => 'Baglaniliyor...',
      (RemoteConnectionState.reconnecting, _) => 'Yeniden baglaniliyor...',
      (RemoteConnectionState.disconnected, _) => 'Baglanti koptu',
      (RemoteConnectionState.error, _) => 'Baglanti hatasi',
      (RemoteConnectionState.connected, false) =>
        'Telefonunuzun baglanmasi bekleniyor...',
      (RemoteConnectionState.connected, true) => 'Bagli',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext _, Widget? __) {
            return Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color
                    .withValues(alpha: connected ? 1 : 0.5 + 0.5 * _pulse.value),
              ),
            );
          },
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.84),
          ),
        ),
      ],
    );
  }
}

class _RecentCommandsList extends StatelessWidget {
  const _RecentCommandsList({required this.commands});
  final List<RemoteCommand> commands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
      ),
      child: Column(
        children: <Widget>[
          for (final cmd in commands)
            ListTile(
              dense: true,
              leading: Icon(_iconFor(cmd), color: theme.colorScheme.primary),
              title: Text(_labelFor(cmd)),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(RemoteCommand cmd) => switch (cmd) {
        RemotePlayPauseCommand() => Icons.play_circle_outline,
        RemoteSeekRelativeCommand(:final seconds) =>
          seconds < 0 ? Icons.replay_10 : Icons.forward_10,
        RemoteSeekAbsoluteCommand() => Icons.timer_outlined,
        RemoteVolumeCommand() => Icons.volume_up_outlined,
        RemoteMuteCommand(:final muted) =>
          muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
        RemoteChannelChangeCommand() => Icons.swap_vert_rounded,
        RemoteOpenScreenCommand() => Icons.open_in_new_rounded,
      };

  static String _labelFor(RemoteCommand cmd) => switch (cmd) {
        RemotePlayPauseCommand() => 'Oynat / duraklat',
        RemoteSeekRelativeCommand(:final seconds) =>
          seconds >= 0 ? '+$seconds sn ileri' : '$seconds sn geri',
        RemoteSeekAbsoluteCommand(:final position) =>
          'Konum: ${_format(position)}',
        RemoteVolumeCommand(:final volume) =>
          'Ses: ${(volume * 100).round()}%',
        RemoteMuteCommand(:final muted) => muted ? 'Sessiz' : 'Sesi ac',
        RemoteChannelChangeCommand(:final channelId) =>
          'Kanal: $channelId',
        RemoteOpenScreenCommand(:final route) => 'Ekran: $route',
      };

  static String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
