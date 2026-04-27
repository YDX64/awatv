import 'dart:async';

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/keyboard_shortcuts.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen player with custom overlay controls.
///
/// Lifecycle:
///   - on init: locks to landscape, sets immersive UI, creates controller,
///     triggers play, starts position-tick history saver (5s).
///   - on dispose: restores orientation/UI, disposes controller.
///
/// Overlay controls:
///   - centre: play/pause big button.
///   - bottom: position / total / seek bar (hidden for live).
///   - top: title + close.
///   - auto-hide after 3 s of no interaction; tap toggles.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.args, super.key});

  final PlayerLaunchArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  AwaPlayerController? _controller;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _hideTimer;
  Timer? _historyTimer;

  bool _showControls = true;
  bool _isPaused = false;
  Duration _position = Duration.zero;
  Duration? _total;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    _bootController();
    _scheduleHide();
  }

  Future<void> _enterImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _exitImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _bootController() async {
    try {
      final c = AwaPlayerController.create(widget.args.source);
      _controller = c;

      _stateSub = c.states.listen(
        _onPlayerState,
        onError: (Object e, StackTrace s) {
          if (!mounted) return;
          setState(() => _errorMessage = e.toString());
        },
      );

      _positionSub = c.positions.listen((Duration p) {
        if (!mounted) return;
        setState(() => _position = p);
      });

      await c.play();

      if (!widget.args.isLive && widget.args.itemId != null) {
        _startHistoryTicker();
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  void _onPlayerState(PlayerState state) {
    if (!mounted) return;
    switch (state) {
      case PlayerPlaying(:final position, :final total):
        setState(() {
          _isPaused = false;
          _position = position;
          _total = total;
          _errorMessage = null;
        });
      case PlayerPaused(:final position, :final total):
        setState(() {
          _isPaused = true;
          _position = position;
          _total = total;
        });
      case PlayerLoading():
        setState(() => _errorMessage = null);
      case PlayerEnded():
        setState(() => _isPaused = true);
      case PlayerError(:final message):
        setState(() => _errorMessage = message);
      case PlayerIdle():
        break;
    }
  }

  void _startHistoryTicker() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final id = widget.args.itemId;
      if (id == null) return;
      final total = _total;
      if (total == null || total == Duration.zero) return;
      try {
        await ref
            .read(historyServiceProvider)
            .markPosition(id, _position, total);
      } on Object {
        // History writes are best-effort; we don't surface failures.
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (!_isPaused) setState(() => _showControls = false);
    });
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (_isPaused) {
      await c.play();
    } else {
      await c.pause();
    }
    _scheduleHide();
  }

  Future<void> _seekTo(Duration to) async {
    final c = _controller;
    if (c == null) return;
    await c.seek(to);
    _scheduleHide();
  }

  /// Picture-in-picture handoff. Surfaces the paywall lock sheet on
  /// the free tier; on premium it would call out to a platform channel
  /// — that wiring lands with multi-screen in Phase 2 (see
  /// `docs/ROADMAP.md`).
  void _onPipRequested() {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.pictureInPicture));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.pictureInPicture);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PiP destegi Phase 2 te platform kanali ile aktiflesir.',
        ),
      ),
    );
  }

  /// VLC backend toggle. Same gate semantics as PiP.
  void _onBackendToggleRequested() {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.vlcBackend));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.vlcBackend);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Oynatici motor secimi yakinda eklenecek.'),
      ),
    );
  }

  /// Used by desktop keyboard shortcuts (arrow keys, J/L) to nudge the
  /// playback position by a relative amount. Live streams ignore the
  /// seek but still flash the controls so the user gets feedback.
  Future<void> _seekRelative(Duration delta) async {
    if (widget.args.isLive) {
      setState(() => _showControls = true);
      _scheduleHide();
      return;
    }
    final total = _total;
    final next = _position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (total != null && next > total ? total : next);
    await _seekTo(clamped);
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _hideTimer?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _controller?.dispose();
    _exitImmersive();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller?.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isDesktop = ref.watch(isDesktopFormProvider);

    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null)
              AwaPlayerView(controller: controller)
            else
              const ColoredBox(color: Colors.black),
            if (_errorMessage != null) _ErrorPanel(message: _errorMessage!),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: DesignTokens.motionFast,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _ControlsLayer(
                  title: widget.args.title ?? '',
                  subtitle: widget.args.subtitle,
                  isLive: widget.args.isLive,
                  isPaused: _isPaused,
                  position: _position,
                  total: _total,
                  onTogglePlay: _togglePlay,
                  onSeek: _seekTo,
                  onClose: () {
                    if (context.canPop()) context.pop();
                  },
                  onPipRequested: _onPipRequested,
                  onBackendToggleRequested: _onBackendToggleRequested,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final body = isDesktop
        ? DesktopPlayerShortcuts(
            controller: controller,
            onTogglePlay: _togglePlay,
            onSeekRelative: _seekRelative,
            onToggleFullscreen: toggleDesktopFullscreen,
            onExit: () {
              if (context.canPop()) context.pop();
            },
            child: scaffold,
          )
        : scaffold;

    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) await _exitImmersive();
      },
      child: body,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 56),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              'Oynatma hatasi',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsLayer extends StatelessWidget {
  const _ControlsLayer({
    required this.title,
    required this.isLive,
    required this.isPaused,
    required this.position,
    required this.total,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onClose,
    required this.onPipRequested,
    required this.onBackendToggleRequested,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool isLive;
  final bool isPaused;
  final Duration position;
  final Duration? total;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onClose;
  final VoidCallback onPipRequested;
  final VoidCallback onBackendToggleRequested;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC000000),
            Color(0x33000000),
            Color(0xCC000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceM,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: onClose,
                      tooltip: 'Kapat',
                    ),
                    const SizedBox(width: DesignTokens.spaceS),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                    if (isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spaceS,
                          vertical: DesignTokens.spaceXs,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.error,
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusS),
                        ),
                        child: const Text(
                          'CANLI',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Picture in picture',
                      onPressed: onPipRequested,
                      icon: const Icon(
                        Icons.picture_in_picture_alt_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Oynatici motoru',
                      onPressed: onBackendToggleRequested,
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: IconButton.filled(
                iconSize: 56,
                onPressed: onTogglePlay,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                ),
                icon: Icon(
                  isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
              ),
            ),
            if (!isLive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceM,
                    DesignTokens.spaceS,
                    DesignTokens.spaceM,
                    DesignTokens.spaceL,
                  ),
                  child: Row(
                    children: [
                      Text(
                        _format(position),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: _safeProgress(position, total),
                          onChanged: total == null
                              ? null
                              : (double v) {
                                  final t = total!.inMilliseconds * v;
                                  onSeek(Duration(milliseconds: t.round()));
                                },
                        ),
                      ),
                      Text(
                        total == null ? '--:--' : _format(total!),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _safeProgress(Duration position, Duration? total) {
    if (total == null || total.inMilliseconds == 0) return 0;
    final r = position.inMilliseconds / total.inMilliseconds;
    if (r.isNaN || r.isInfinite) return 0;
    return r.clamp(0.0, 1.0);
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}
