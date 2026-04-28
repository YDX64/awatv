import 'dart:async';

import 'package:awatv_mobile/src/shared/cast/cast_provider.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-modal that lists discovered cast receivers and lets the user
/// connect or disconnect.
///
/// The sheet is fully self-contained:
/// - On open it kicks off [CastController.discover] (or surfaces the
///   AirPlay picker on iOS).
/// - Watches [castSessionStreamProvider] for state transitions.
/// - On close it stops discovery so SSDP / mDNS traffic doesn't keep
///   running while the player is back in foreground.
///
/// The picker is presented through [CastDevicePicker.show]; callers are
/// responsible for providing the active player controller so the
/// "connect" path can mirror playback in one go.
class CastDevicePicker extends ConsumerStatefulWidget {
  const CastDevicePicker({
    required this.onConnectAndMirror,
    required this.onDisconnect,
    super.key,
  });

  /// Called when the user picks a device. The host screen runs
  /// `CastController.connect(device)` followed by `mirror(...)` so the
  /// stream actually starts on the TV — this widget just signals the
  /// intent.
  final Future<void> Function(CastDevice device) onConnectAndMirror;

  /// Called when the user taps "Bağlantıyı kes" while connected.
  final Future<void> Function() onDisconnect;

  /// Convenience entry point — pushes the picker as a styled bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(CastDevice device) onConnectAndMirror,
    required Future<void> Function() onDisconnect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      useSafeArea: true,
      builder: (BuildContext sheetCtx) => CastDevicePicker(
        onConnectAndMirror: onConnectAndMirror,
        onDisconnect: onDisconnect,
      ),
    );
  }

  @override
  ConsumerState<CastDevicePicker> createState() => _CastDevicePickerState();
}

class _CastDevicePickerState extends ConsumerState<CastDevicePicker> {
  bool _kickedOff = false;

  @override
  void initState() {
    super.initState();
    // Defer to post-frame so the sheet is on screen before we touch the
    // engine — keeps the open animation smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(castControllerProvider);
      // On iOS we hand off to the system AirPlay picker rather than
      // showing our own list — Apple's picker is the only sanctioned
      // path. We still call discover() so any ad-hoc devices the
      // engine knows about populate the fallback list.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await controller.showAirPlayPicker();
      }
      await controller.discover();
      _kickedOff = true;
    });
  }

  @override
  void dispose() {
    // Stop discovery so we don't keep flooding the LAN when the player
    // is back in front. The engine itself remains alive — kept-alive at
    // the provider level — only its discovery loop is paused.
    if (_kickedOff) {
      // Read the controller via ProviderContainer to avoid using ref
      // during dispose (which Riverpod warns about). Fire-and-forget
      // — discovery is a best-effort cleanup.
      unawaited(
        ProviderScope.containerOf(context, listen: false)
            .read(castControllerProvider)
            .stopDiscovery(),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(castSessionStreamProvider);

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXL),
        ),
        child: Material(
          color: scheme.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Grabber(scheme: scheme),
                _Header(scheme: scheme),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spaceM,
                      0,
                      DesignTokens.spaceM,
                      DesignTokens.spaceL,
                    ),
                    child: session.when(
                      data: (CastSession s) => _SessionView(
                        session: s,
                        onPickDevice: widget.onConnectAndMirror,
                        onDisconnect: widget.onDisconnect,
                      ),
                      loading: () => const _ShimmerList(),
                      error: (Object e, _) => _ErrorPanel(message: '$e'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceS),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceS,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cast_rounded, color: scheme.primary),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              "Yayını TV'ye gönder",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  const _SessionView({
    required this.session,
    required this.onPickDevice,
    required this.onDisconnect,
  });

  final CastSession session;
  final Future<void> Function(CastDevice device) onPickDevice;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (session) {
      CastIdle() => const _ShimmerList(),
      CastDiscovering() => const _ShimmerList(),
      CastDevicesAvailable(devices: final devices) => devices.isEmpty
          ? const _EmptyState()
          : _DeviceList(devices: devices, onPick: onPickDevice),
      CastConnecting(target: final t) => _ConnectingPanel(target: t),
      CastConnected(target: final t, state: final st) => _ConnectedPanel(
          target: t,
          state: st,
          onDisconnect: onDisconnect,
          tint: scheme.primary,
        ),
      CastError(message: final m) => _ErrorPanel(message: m),
    };
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.onPick});

  final List<CastDevice> devices;
  final Future<void> Function(CastDevice device) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final dev in devices)
          ListTile(
            key: ValueKey<String>('cast-device-${dev.id}'),
            leading: _DeviceIcon(kind: dev.kind, scheme: scheme),
            title: Text(
              dev.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              dev.manufacturer == null
                  ? dev.kind.displayName
                  : '${dev.manufacturer} • ${dev.kind.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await onPick(dev);
              if (!context.mounted) return;
              await Navigator.of(context).maybePop();
            },
          ),
      ],
    );
  }
}

class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.kind, required this.scheme});
  final CastDeviceKind kind;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      CastDeviceKind.chromecast => Icons.cast_rounded,
      CastDeviceKind.airplay => Icons.airplay_rounded,
      CastDeviceKind.dlna => Icons.tv_rounded,
    };
    return CircleAvatar(
      backgroundColor: scheme.primary.withValues(alpha: 0.14),
      child: Icon(icon, color: scheme.primary),
    );
  }
}

class _ConnectingPanel extends StatelessWidget {
  const _ConnectingPanel({required this.target});
  final CastDevice target;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceL),
      child: Column(
        children: <Widget>[
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Text(
            '${target.name} cihazına bağlanılıyor...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _ConnectedPanel extends StatelessWidget {
  const _ConnectedPanel({
    required this.target,
    required this.state,
    required this.onDisconnect,
    required this.tint,
  });

  final CastDevice target;
  final CastPlaybackState state;
  final Future<void> Function() onDisconnect;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.cast_connected_rounded, color: tint),
                const SizedBox(width: DesignTokens.spaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        target.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.currentTitle ?? 'Yayın aktif',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          FilledButton.tonalIcon(
            onPressed: () async {
              await onDisconnect();
              if (!context.mounted) return;
              await Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.cast_rounded),
            label: const Text('Bağlantıyı kes'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceL),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.tv_off_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            'Yayın gönderilebilecek cihaz bulunamadı.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            'TV ile aynı Wi-Fi ağında olduğunuzdan emin olun.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceL),
      child: Column(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 48),
          const SizedBox(height: DesignTokens.spaceS),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ShimmerRow(),
        _ShimmerRow(),
        _ShimmerRow(),
      ],
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXs),
      child: Row(
        children: <Widget>[
          ShimmerSkeleton.box(width: 40, height: 40, radius: 20),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ShimmerSkeleton.text(width: 160, height: 14),
                const SizedBox(height: DesignTokens.spaceXs),
                ShimmerSkeleton.text(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
