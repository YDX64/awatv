import 'dart:async';

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/keyboard_shortcuts.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_buffering_overlay.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_controls_layer.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_gestures.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_settings_sheet.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/remote/player_bridge.dart';
import 'package:awatv_mobile/src/shared/remote/receiver_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen, Netflix-tier player.
///
/// Composition strategy:
/// - [AwaPlayerView] renders the video frame (no chrome of its own).
/// - [PlayerGestures] sits over the frame and recognises taps, double-taps,
///   vertical/horizontal drags, and pinch.
/// - [PlayerControlsLayer] paints the top bar / centre cluster / bottom bar
///   on top, fading in/out as a unit.
/// - [PlayerBufferingOverlay] fades in over both when the engine reports
///   buffering for >200ms after the first frame.
///
/// Lifecycle:
///   - on init: locks orientation list (landscape preferred), sets immersive
///     UI, creates the controller, kicks off play, starts the 5s history
///     write timer for VOD/episodes.
///   - on dispose: tears everything down and restores the system chrome.
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
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<int?>? _heightSub;
  Timer? _hideTimer;
  Timer? _historyTimer;
  Timer? _lowBwTimer;

  bool _showControls = true;
  bool _isPaused = false;
  bool _buffering = false;
  bool _scrubbing = false;
  bool _firstFrameSeen = false;
  Duration _position = Duration.zero;
  Duration _bufferedPos = Duration.zero;
  Duration? _total;
  String? _errorMessage;
  int? _videoHeight;
  bool _lowBandwidth = false;

  // Brightness/volume mirrors that survive a single drag — actual
  // brightness control requires a native plugin and is intentionally
  // out of scope per AGENT instructions; volume goes through media_kit.
  double _volume = 1; // 0..1
  BoxFit _videoFit = BoxFit.contain;

  PlayerGestureFeedback _gestureFeedback = const PlayerGestureFeedback(
    kind: PlayerGestureKind.none,
    value: 0,
  );

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
      // Constructing the controller can throw synchronously the first
      // time per process (media_kit init); catching it below means the
      // user sees a readable error panel instead of the screen never
      // appearing. We deliberately use `.empty()` here so playback only
      // starts via `openWithFallbacks` below — that gives us a single
      // place to drive the variant chain instead of racing an immediate
      // open() against subscriber wiring.
      final c = AwaPlayerController.empty();
      _controller = c;
      // Surface the controller into the build immediately so AwaPlayerView
      // can attach its texture before bytes start flowing.
      setState(() {});

      _stateSub = c.states.listen(
        _onPlayerState,
        onError: (Object e, StackTrace s) {
          if (!mounted) return;
          setState(() => _errorMessage = e.toString());
        },
      );

      _positionSub = c.positions.listen((Duration p) {
        if (!mounted) return;
        setState(() {
          _position = p;
          if (!_firstFrameSeen && p > Duration.zero) {
            _firstFrameSeen = true;
          }
        });
      });

      _bufferedSub = c.buffered.listen((Duration b) {
        if (!mounted) return;
        setState(() => _bufferedPos = b);
        _evaluateLowBandwidth();
      });

      _heightSub = c.videoHeightStream.listen((int? h) {
        if (!mounted) return;
        setState(() => _videoHeight = h);
      });

      // Walk the variant chain — each panel/stream may need a different
      // URL shape (`.ts` vs `.m3u8`, `/live/` prefix, etc.). The first
      // source that produces a Playing state wins; if all fail, the
      // controller emits PlayerError and we surface the message in the
      // panel.
      final sources = widget.args.allSources;
      try {
        await c.openWithFallbacks(sources);
      } on PlayerException catch (e) {
        // Don't bail early — the screen still wants to register the
        // history ticker (cheap) and surface the error via setState.
        if (mounted) setState(() => _errorMessage = e.message);
      }

      if (!widget.args.isLive && widget.args.itemId != null) {
        _startHistoryTicker();
      }

      // If a receiver session is already running on this device, hand
      // the active controller to the bridge so remote-control commands
      // route into this player and so its now-playing state echoes
      // back to the connected sender. No-op when no session is active.
      _publishToBridgeIfReceiving();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  /// Wires this player into the remote-control bridge when (and only
  /// when) a receiver session is already alive. Pure additive — players
  /// outside any remote flow don't pay the channel-open cost.
  void _publishToBridgeIfReceiving() {
    final session = ref.read(receiverSessionControllerProvider);
    if (!session.hasValue) return;
    final c = _controller;
    if (c == null) return;
    // Touch the bridge so it instantiates and listens for commands.
    ref.read(ensurePlayerBridgeProvider);
    ref.read(activePlaybackProvider.notifier).set(
          PlaybackContext(
            controller: c,
            title: widget.args.title,
            subtitle: widget.args.subtitle,
            itemId: widget.args.itemId,
            isLive: widget.args.isLive,
          ),
        );
  }

  void _onPlayerState(PlayerState state) {
    if (!mounted) return;
    switch (state) {
      case PlayerPlaying(:final position, :final total):
        setState(() {
          _isPaused = false;
          _buffering = false;
          _position = position;
          _total = total;
          _errorMessage = null;
        });
      case PlayerPaused(:final position, :final total):
        setState(() {
          _isPaused = true;
          _buffering = false;
          _position = position;
          _total = total;
          _showControls = true;
        });
      case PlayerLoading():
        setState(() {
          _buffering = true;
          _errorMessage = null;
        });
      case PlayerEnded():
        setState(() {
          _isPaused = true;
          _showControls = true;
        });
      case PlayerError(:final message):
        setState(() => _errorMessage = message);
      case PlayerIdle():
        break;
    }
  }

  void _evaluateLowBandwidth() {
    // Treat <2s buffer ahead of the playhead as "low" — flip the badge on
    // after this condition holds for 5s, off as soon as it recovers.
    final aheadMs = _bufferedPos.inMilliseconds - _position.inMilliseconds;
    final isLow = aheadMs >= 0 && aheadMs < 2000;
    if (!isLow) {
      _lowBwTimer?.cancel();
      _lowBwTimer = null;
      if (_lowBandwidth) setState(() => _lowBandwidth = false);
      return;
    }
    if (_lowBwTimer != null) return;
    _lowBwTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _lowBandwidth = true);
    });
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

  void _revealControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_isPaused || _scrubbing) return;
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      if (!_isPaused && !_scrubbing) {
        setState(() => _showControls = false);
      }
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

  Future<void> _skipBy(Duration delta) async {
    final c = _controller;
    if (c == null || widget.args.isLive) return;
    final total = _total;
    final next = _position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (total != null && next > total ? total : next);
    await c.seek(clamped);
    _revealControls();
  }

  void _onPipRequested() {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.pictureInPicture));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.pictureInPicture);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PiP destegi Phase 2 te platform kanali ile aktiflesir.'),
      ),
    );
  }

  void _onCastRequested() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Yayın gönderme yakında geliyor.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSettingsRequested() async {
    final c = _controller;
    if (c == null) return;
    _hideTimer?.cancel();
    await PlayerSettingsSheet.show(context, controller: c);
    if (!mounted) return;
    _scheduleHide();
  }

  Future<void> _onVolumeDelta(double delta) async {
    final c = _controller;
    if (c == null) return;
    _volume = (_volume + delta).clamp(0.0, 1.0);
    await c.setVolume(_volume * 100);
  }

  Future<void> _onBrightnessDelta(double _) async {
    // Native brightness control would need a platform plugin; we keep the
    // gesture wired so the HUD shows feedback, but the actual screen
    // brightness call is intentionally a no-op here. If the host picks up
    // a brightness plugin later, it can subclass and override this.
  }

  Future<void> _onPinchToggle() async {
    setState(() {
      _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    });
  }

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
  /// playback position by a relative amount.
  Future<void> _seekRelative(Duration delta) async {
    if (widget.args.isLive) {
      _revealControls();
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
    _lowBwTimer?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _heightSub?.cancel();
    // Detach this player from the remote-control bridge before tearing
    // down the controller so the bridge does not hold a dangling ref.
    // Wrapped because the provider scope may already be gone if the
    // app is being torn down entirely.
    try {
      ref.read(activePlaybackProvider.notifier).clear();
    } on Object {
      // ignore: best-effort cleanup
    }
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

  NetworkStatusKind? _statusKindForOverlay() {
    if (widget.args.isLive) return NetworkStatusKind.live;
    if (_buffering) return NetworkStatusKind.buffering;
    if (_videoHeight != null && _videoHeight! >= 2160) {
      return NetworkStatusKind.fourK;
    }
    if (_lowBandwidth) return NetworkStatusKind.lowBandwidth;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isDesktop = ref.watch(isDesktopFormProvider);
    final statusKind = _statusKindForOverlay();
    final showBuffering = _buffering && !_isPaused && _firstFrameSeen;

    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        // On web/desktop, mouse movement reveals controls — matches the
        // muscle memory users have from YouTube/Netflix on desktop.
        onHover: kIsWeb ? (_) => _revealControls() : null,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (controller != null)
              AwaPlayerView(controller: controller, fit: _videoFit)
            else
              const ColoredBox(color: Colors.black),
            // Gestures intercept taps before the controls layer; they
            // toggle visibility and drive scrub/volume HUDs.
            PlayerGestures(
              onTap: _toggleControls,
              onSkipBack: () => _skipBy(const Duration(seconds: -10)),
              onSkipForward: () => _skipBy(const Duration(seconds: 10)),
              onBrightnessDelta: _onBrightnessDelta,
              onVolumeDelta: _onVolumeDelta,
              onSeekRelative: (int s) =>
                  _skipBy(Duration(seconds: s)),
              onPinchToggle: _onPinchToggle,
              onGestureFeedback: (PlayerGestureFeedback fb) {
                if (!mounted) return;
                setState(() => _gestureFeedback = fb);
              },
              enableSeekDrag: !widget.args.isLive,
              child: const SizedBox.expand(),
            ),
            PlayerGestureHud(feedback: _gestureFeedback),
            PlayerBufferingOverlay(visible: showBuffering),
            if (_errorMessage != null) _ErrorPanel(message: _errorMessage!),
            // Controls layer fades as a single unit for a cohesive feel.
            IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: DesignTokens.motionMedium,
                curve: DesignTokens.motionEmphasized,
                child: PlayerControlsLayer(
                  title: widget.args.title ?? '',
                  subtitle: widget.args.subtitle,
                  isLive: widget.args.isLive,
                  isPaused: _isPaused,
                  position: _position,
                  total: _total,
                  buffered: _bufferedPos,
                  onTogglePlay: _togglePlay,
                  onSeekTo: _seekTo,
                  onSkipBack: () =>
                      _skipBy(const Duration(seconds: -10)),
                  onSkipForward: () =>
                      _skipBy(const Duration(seconds: 10)),
                  onClose: _onClose,
                  onCastRequested: _onCastRequested,
                  onSettingsRequested: _onSettingsRequested,
                  onScrubStartChanged: (bool active) {
                    setState(() => _scrubbing = active);
                    if (!active) _scheduleHide();
                  },
                  statusBadge: statusKind == null
                      ? null
                      : NetworkStatusBadge(kind: statusKind),
                ),
              ),
            ),
            // PiP / engine toggles tucked into the top-right corner so
            // they remain reachable without bloating the new top bar.
            if (_showControls)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: DesignTokens.spaceXxl,
                      right: DesignTokens.spaceXs,
                    ),
                    child: Column(
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Picture in picture',
                          onPressed: _onPipRequested,
                          icon: const Icon(
                            Icons.picture_in_picture_alt_rounded,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Oynatıcı motoru',
                          onPressed: _onBackendToggleRequested,
                          icon: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
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
            onExit: _onClose,
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

  void _onClose() {
    if (context.canPop()) context.pop();
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
          children: <Widget>[
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
