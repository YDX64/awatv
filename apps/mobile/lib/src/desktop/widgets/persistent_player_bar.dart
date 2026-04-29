import 'dart:async';
import 'dart:ui';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/desktop/always_on_top.dart';
import 'package:awatv_mobile/src/desktop/widgets/now_playing_state.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_mobile/src/features/player/widgets/cast_device_picker.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/cast/cast_provider.dart';
import 'package:awatv_mobile/src/shared/player/active_player_controller.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// IPTV-Expert-class persistent mini player bar.
///
/// Pinned to the bottom of the desktop content pane. Hidden when nothing
/// is playing (animated reveal/dismiss); reveals smoothly when
/// [nowPlayingProvider] starts emitting non-null state.
///
/// Layout:
/// ┌────────────────────────────────────────────────────────────────────┐
/// │ [40x40 thumb] Title              [▶] [⏭] [🔊]──[bar]── [📡][📌][⛶]│
/// │                Subtitle                                            │
/// │ ─── progress (1px) ───                                            │
/// └────────────────────────────────────────────────────────────────────┘
class PersistentPlayerBar extends ConsumerWidget {
  const PersistentPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nowPlayingProvider);

    return AnimatedSwitcher(
      duration: DesignTokens.motionPanelSlide,
      switchInCurve: Curves.easeOutQuint,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> anim) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      child: state == null
          ? const SizedBox.shrink(key: ValueKey<String>('hidden'))
          : _Bar(
              key: const ValueKey<String>('visible'),
              state: state,
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.state, super.key});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgAlpha = isDark
        ? DesignTokens.glassBgAlphaDark
        : DesignTokens.glassBgAlphaLight;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DesignTokens.glassBlurStrong,
          sigmaY: DesignTokens.glassBlurStrong,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest
                .withValues(alpha: bgAlpha + 0.05),
            border: Border(
              top: BorderSide(
                color: scheme.outline.withValues(alpha: 0.18),
              ),
            ),
          ),
          child: SizedBox(
            height: DesignTokens.persistentPlayerBarHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ProgressLine(state: state),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceM,
                    ),
                    child: Row(
                      children: <Widget>[
                        _Thumb(state: state),
                        const SizedBox(width: DesignTokens.spaceM),
                        Expanded(child: _Titles(state: state)),
                        const SizedBox(width: DesignTokens.spaceM),
                        _TransportControls(state: state),
                        const SizedBox(width: DesignTokens.spaceS),
                        _RightControls(state: state),
                      ],
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

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (state.isLive) {
      // Live — striped pattern walking left-to-right. Matches the IPTV
      // "live indicator" affordance without copying any specific design.
      return SizedBox(
        height: 2,
        child: _LiveStripes(color: scheme.secondary),
      );
    }
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: state.progress,
        backgroundColor: scheme.outline.withValues(alpha: 0.25),
        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
      ),
    );
  }
}

class _LiveStripes extends StatefulWidget {
  const _LiveStripes({required this.color});
  final Color color;

  @override
  State<_LiveStripes> createState() => _LiveStripesState();
}

class _LiveStripesState extends State<_LiveStripes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext _, Widget? __) {
        return CustomPaint(
          painter: _StripePainter(
            color: widget.color,
            phase: _ctrl.value,
          ),
        );
      },
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    const stripeWidth = 12.0;
    final offset = phase * stripeWidth;
    for (var x = -stripeWidth + offset;
        x < size.width + stripeWidth;
        x += stripeWidth) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + stripeWidth * 0.6, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) =>
      old.phase != phase || old.color != color;
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = DesignTokens.persistentPlayerThumbSize;
    final hasUrl = state.thumbnailUrl != null && state.thumbnailUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: Container(
        width: size,
        height: size,
        color: scheme.surface,
        alignment: Alignment.center,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: state.thumbnailUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                fadeInDuration: DesignTokens.motionFast,
                errorWidget: (BuildContext _, String __, Object ___) =>
                    _fallbackIcon(scheme),
              )
            : _fallbackIcon(scheme),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme scheme) {
    final IconData icon;
    switch (state.kind) {
      case HistoryKind.live:
        icon = Icons.live_tv_rounded;
      case HistoryKind.vod:
        icon = Icons.movie_outlined;
      case HistoryKind.series:
        icon = Icons.video_library_outlined;
    }
    return Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.6));
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (state.isLive) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusS),
                ),
                child: Text(
                  'CANLI',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: scheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
            ],
            Expanded(
              child: Text(
                state.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (state.subtitle != null && state.subtitle!.isNotEmpty)
          Text(
            state.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
  }
}

class _TransportControls extends ConsumerWidget {
  const _TransportControls({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(activePlayerControllerProvider);
    final castActive = ref.watch(castIsActiveProvider);
    final hasController = controller != null;

    // Channel-prev/next is only meaningful for live broadcasts. VOD/series
    // viewers use the detail screens to find the next item.
    final liveNav = state.isLive;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (liveNav)
          _IconBtn(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Onceki kanal',
            onTap: hasController
                ? () => _stepLiveChannel(context, ref, controller, -1)
                : null,
          ),
        _IconBtn(
          icon: state.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          tooltip: state.isPlaying ? 'Duraklat' : 'Oynat',
          accent: true,
          onTap: hasController
              ? () => _togglePlay(ref, controller, castActive: castActive)
              : null,
        ),
        if (liveNav)
          _IconBtn(
            icon: Icons.skip_next_rounded,
            tooltip: 'Sonraki kanal',
            onTap: hasController
                ? () => _stepLiveChannel(context, ref, controller, 1)
                : null,
          ),
      ],
    );
  }

  /// Routes a play/pause through the cast session when one is connected,
  /// otherwise toggles the local engine. The bar updates its mirror via
  /// the player screen's state listener — we don't optimistically flip
  /// the icon here because that would diverge from the engine's actual
  /// state on slow devices.
  Future<void> _togglePlay(
    WidgetRef ref,
    AwaPlayerController controller, {
    required bool castActive,
  }) async {
    if (castActive) {
      await ref.read(castControllerProvider).togglePlayPause();
      return;
    }
    if (state.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  /// Walks the current category's live-channels list ±[direction] and
  /// asks the active controller to open the new source. Wraps around at
  /// either end so the user can keep flicking through channels without
  /// hitting a hard stop.
  Future<void> _stepLiveChannel(
    BuildContext context,
    WidgetRef ref,
    AwaPlayerController controller,
    int direction,
  ) async {
    final selection = ref.read(categorySelectionProvider);
    if (selection == null || selection.kind != CategoryKind.live) {
      // No live category in play — surface a hint instead of failing
      // silently. Picking a category brings the channel list to life.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kanal listesi açık değil — Canlı TV kategorisini seçin.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final channelsAsync = ref.read(selectedLiveChannelsProvider);
    final channels = channelsAsync.valueOrNull;
    if (channels == null || channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geçilebilecek kanal bulunamadı.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final currentId = state.itemId;
    var idx = currentId == null
        ? -1
        : channels.indexWhere((Channel c) => c.id == currentId);
    if (idx < 0) idx = 0;
    final nextIdx = (idx + direction) % channels.length;
    final next = channels[nextIdx < 0 ? nextIdx + channels.length : nextIdx];

    // Build the fallback chain the same way the channels screen does so
    // panel-specific URL shapes still get tried in order.
    final headers = <String, String>{};
    final ua = next.extras['http-user-agent'] ?? next.extras['user-agent'];
    final referer = next.extras['http-referrer'] ??
        next.extras['referer'] ??
        next.extras['Referer'];
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    final urls = streamUrlVariants(next.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: next.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );

    // Update the persistent bar payload eagerly so the title/subtitle/
    // logo flip the moment the user clicks — the engine catches up
    // through the player screen's state listener once the new stream
    // produces frames.
    ref.read(nowPlayingProvider.notifier).start(
          NowPlaying(
            title: next.name,
            kind: HistoryKind.live,
            subtitle: next.groups.isEmpty ? null : next.groups.first,
            thumbnailUrl: next.logoUrl,
            itemId: next.id,
            isLive: true,
            isPlaying: true,
            source: variants.isEmpty ? null : variants.first,
          ),
        );

    try {
      if (variants.isEmpty) {
        await controller.open(
          MediaSource(
            url: proxify(next.streamUrl),
            title: next.name,
            userAgent: ua,
            headers: headers.isEmpty ? null : headers,
          ),
        );
      } else {
        await controller.openWithFallbacks(variants);
      }
    } on PlayerException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kanal açılamadı: ${e.message}')),
      );
    }
  }
}

class _RightControls extends ConsumerWidget {
  const _RightControls({required this.state});

  final NowPlaying state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(alwaysOnTopProvider);
    final itemId = state.itemId;
    final controller = ref.watch(activePlayerControllerProvider);
    final castActive = ref.watch(castIsActiveProvider);
    final castDevice = ref.watch(castConnectedDeviceNameProvider);

    // Expand prefers the player route when we still have the [MediaSource]
    // — that re-opens the full-screen player without a round-trip through
    // the detail screen. When the source isn't available (e.g. the bar
    // was repainted with a stub state) we fall back to the detail page.
    String? expandRoute() {
      if (itemId == null || itemId.isEmpty) return null;
      switch (state.kind) {
        case HistoryKind.live:
          return '/channel/$itemId';
        case HistoryKind.vod:
          return '/movie/$itemId';
        case HistoryKind.series:
          return '/series/$itemId';
      }
    }

    void onExpand() {
      final source = state.source;
      if (source != null) {
        context.push(
          '/play',
          extra: PlayerLaunchArgs(
            source: source,
            title: state.title,
            subtitle: state.subtitle,
            itemId: itemId,
            kind: state.kind,
            isLive: state.isLive,
          ),
        );
        return;
      }
      final route = expandRoute();
      if (route != null) context.push(route);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Volume slider — collapses to an icon button on tight widths so
        // the bar still fits on a 1100dp window. Hidden while a cast
        // session is connected because volume is routed to the receiver
        // through the cast control surface instead.
        _VolumeControl(
          controller: controller,
          castActive: castActive,
        ),
        const SizedBox(width: DesignTokens.spaceXs),
        _CastButton(
          state: state,
          controller: controller,
          castActive: castActive,
          castDeviceName: castDevice,
        ),
        _IconBtn(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          tooltip: pinned ? 'Ust katmandan kaldir' : 'En ustte tut',
          accent: pinned,
          onTap: () =>
              ref.read(alwaysOnTopProvider.notifier).toggle(),
        ),
        _IconBtn(
          icon: Icons.open_in_full_rounded,
          tooltip: 'Tam ekrana ac',
          onTap: (state.source == null && expandRoute() == null)
              ? null
              : onExpand,
        ),
        _IconBtn(
          icon: Icons.close_rounded,
          tooltip: 'Kapat',
          onTap: () => ref.read(nowPlayingProvider.notifier).clear(),
        ),
      ],
    );
  }
}

/// Cast button — opens the existing [CastDevicePicker] modal. Hands the
/// connect+mirror sequence into the cast controller; when a session is
/// already active the icon flips to "connected" and the same tap reveals
/// the disconnect path inside the picker (the picker already owns that
/// state machine).
class _CastButton extends StatelessWidget {
  const _CastButton({
    required this.state,
    required this.controller,
    required this.castActive,
    required this.castDeviceName,
  });

  final NowPlaying state;
  final AwaPlayerController? controller;
  final bool castActive;
  final String? castDeviceName;

  @override
  Widget build(BuildContext context) {
    final tooltip = castActive
        ? (castDeviceName == null
            ? 'Yayın aktif'
            : '$castDeviceName cihazına yayın aktif')
        : 'Yayinla';
    final icon = castActive
        ? Icons.cast_connected_rounded
        : Icons.cast_rounded;
    return _IconBtn(
      icon: icon,
      tooltip: tooltip,
      accent: castActive,
      onTap: controller == null ? null : () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final c = controller;
    if (c == null) return;
    // Capture the source before showing the modal — once it pops the bar
    // may have been re-painted with a different stream.
    final source = state.source;
    final container = ProviderScope.containerOf(context, listen: false);
    final cast = container.read(castControllerProvider);

    await CastDevicePicker.show(
      context,
      onConnectAndMirror: (CastDevice device) async {
        await cast.connect(device);
        if (source == null) {
          // The bar was opened against a stub state with no resolved
          // source — skip the mirror step rather than crashing the
          // engine. The user will need to re-open the player to mirror.
          return;
        }
        try {
          await cast.mirror(
            source,
            localController: c,
            title: state.title,
            subtitle: state.subtitle,
            artworkUrl: state.thumbnailUrl,
            isLive: state.isLive,
          );
        } on CastNotConnectedException {
          // The picker is showing CastError — let it own the messaging.
        } on Object catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Yayın başlatılamadı: $e')),
          );
        }
      },
      onDisconnect: () async {
        await cast.unmirror(localController: c);
      },
    );
  }
}

/// Compact volume slider that lives inline in the bar. We keep the
/// surface stateful so the slider can scrub locally between engine
/// reads — the engine doesn't echo volume changes back through any of
/// our streams, so we treat this widget as the source of truth for the
/// current level until the user re-opens the bar.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({
    required this.controller,
    required this.castActive,
  });

  final AwaPlayerController? controller;
  final bool castActive;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  // 0..1; the engine API takes 0..100, we scale at write time.
  double _value = 1;
  bool _expanded = false;
  Timer? _collapseTimer;

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _expanded = false);
    });
  }

  IconData get _icon {
    if (_value <= 0.001) return Icons.volume_off_rounded;
    if (_value < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  Future<void> _setVolume(double v) async {
    setState(() => _value = v.clamp(0.0, 1.0));
    final c = widget.controller;
    if (c != null) {
      try {
        await c.setVolume(_value * 100);
      } on Object {
        // best-effort — losing a stray slider event isn't worth a UI
        // surface, and the next drag will retry.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.castActive) {
      // Volume is routed to the receiver while casting. We hide the
      // slider so users don't expect it to control local audio.
      return const SizedBox.shrink();
    }
    final disabled = widget.controller == null;
    return MouseRegion(
      onEnter: (_) {
        if (disabled) return;
        setState(() => _expanded = true);
        _collapseTimer?.cancel();
      },
      onExit: (_) {
        if (disabled) return;
        _scheduleCollapse();
      },
      child: AnimatedContainer(
        duration: DesignTokens.motionFast,
        curve: Curves.easeOut,
        width: _expanded ? 144 : 32,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _IconBtn(
              icon: _icon,
              tooltip: disabled
                  ? 'Ses seviyesi'
                  : (_value <= 0.001 ? 'Sesi aç' : 'Sessize al'),
              onTap: disabled
                  ? null
                  : () async {
                      if (_value <= 0.001) {
                        await _setVolume(0.7);
                      } else {
                        await _setVolume(0);
                      }
                    },
            ),
            if (_expanded)
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: _value,
                    onChanged: disabled
                        ? null
                        : (double v) {
                            _collapseTimer?.cancel();
                            _setVolume(v);
                          },
                    onChangeEnd: (_) => _scheduleCollapse(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool accent;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = widget.onTap == null;
    final fg = disabled
        ? scheme.onSurface.withValues(alpha: 0.30)
        : widget.accent
            ? scheme.primary
            : _hover
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.75);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: DesignTokens.motionFast,
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hover && !disabled
                  ? scheme.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}
