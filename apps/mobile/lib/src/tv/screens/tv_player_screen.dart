import 'dart:async';

import 'package:awatv_mobile/src/features/player/widgets/player_buffering_overlay.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_settings_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen TV player.
///
/// Differences from the mobile player:
///   - Controls do not auto-hide. On a TV the user expects D-pad presses
///     to summon controls predictably; auto-hide creates a "where am I"
///     problem.
///   - Up/Down toggles play/pause; Left/Right seeks 10s on VOD; Back
///     exits.
///   - No orientation lock (TVs are already landscape, plus rotating
///     a TV's `SystemChrome` is ignored).
///   - Visual chrome mirrors the mobile redesign — bigger fonts, gradient
///     scrims, status badge — so the brand reads consistently on both.
class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({required this.args, super.key});

  final PlayerLaunchArgs args;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen>
    with WidgetsBindingObserver {
  AwaPlayerController? _controller;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<int?>? _heightSub;
  Timer? _historyTimer;

  bool _showControls = true;
  bool _isPaused = false;
  bool _buffering = false;
  bool _firstFrameSeen = false;
  Duration _position = Duration.zero;
  Duration _bufferedPos = Duration.zero;
  Duration? _total;
  String? _errorMessage;
  int? _videoHeight;

  late final FocusNode _surfaceFocus = FocusNode(debugLabel: 'tv_player');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _surfaceFocus.requestFocus();
    });
  }

  Future<void> _bootController() async {
    try {
      final c = AwaPlayerController.create(widget.args.source);
      _controller = c;

      _stateSub = c.states.listen(
        _onPlayerState,
        onError: (Object e, StackTrace _) {
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
      });
      _heightSub = c.videoHeightStream.listen((int? h) {
        if (!mounted) return;
        setState(() => _videoHeight = h);
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
        });
      case PlayerLoading():
        setState(() {
          _buffering = true;
          _errorMessage = null;
        });
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
        // History writes are best-effort.
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
  }

  Future<void> _seekBy(Duration delta) async {
    final c = _controller;
    if (c == null || widget.args.isLive) return;
    final next = _position + delta;
    final clamped = next.isNegative
        ? Duration.zero
        : (_total != null && next > _total!)
            ? _total!
            : next;
    await c.seek(clamped);
  }

  Future<void> _openSettings() async {
    final c = _controller;
    if (c == null) return;
    await PlayerSettingsSheet.show(context, controller: c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      _togglePlay();
      setState(() => _showControls = true);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(const Duration(seconds: -10));
      setState(() => _showControls = true);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(const Duration(seconds: 10));
      setState(() => _showControls = true);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      setState(() => _showControls = true);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      // 'M' opens the audio/subtitle/quality menu — same key VLC uses.
      _openSettings();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      if (context.canPop()) context.pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  NetworkStatusKind? _statusKindForOverlay() {
    if (widget.args.isLive) return NetworkStatusKind.live;
    if (_buffering) return NetworkStatusKind.buffering;
    if (_videoHeight != null && _videoHeight! >= 2160) {
      return NetworkStatusKind.fourK;
    }
    return null;
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _heightSub?.cancel();
    _controller?.dispose();
    _surfaceFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
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
    final showBuffering = _buffering && !_isPaused && _firstFrameSeen;
    final statusKind = _statusKindForOverlay();
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
            overlays: SystemUiOverlay.values,
          );
        }
      },
      child: Focus(
        focusNode: _surfaceFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (controller != null)
                AwaPlayerView(controller: controller)
              else
                const ColoredBox(color: Colors.black),
              PlayerBufferingOverlay(visible: showBuffering),
              if (_errorMessage != null) _ErrorPanel(message: _errorMessage!),
              if (_showControls)
                _TvControlsLayer(
                  title: widget.args.title ?? '',
                  subtitle: widget.args.subtitle,
                  isLive: widget.args.isLive,
                  isPaused: _isPaused,
                  position: _position,
                  total: _total,
                  buffered: _bufferedPos,
                  statusKind: statusKind,
                  onClose: () {
                    if (context.canPop()) context.pop();
                  },
                ),
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.all(DesignTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.white, size: 72),
            const SizedBox(height: DesignTokens.spaceM),
            const Text(
              'Oynatma hatasi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvControlsLayer extends StatelessWidget {
  const _TvControlsLayer({
    required this.title,
    required this.isLive,
    required this.isPaused,
    required this.position,
    required this.total,
    required this.buffered,
    required this.statusKind,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool isLive;
  final bool isPaused;
  final Duration position;
  final Duration? total;
  final Duration buffered;
  final NetworkStatusKind? statusKind;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xCC000000),
            Color(0x33000000),
            Color(0xCC000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (statusKind != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: DesignTokens.spaceS,
                      ),
                      child: NetworkStatusBadge(kind: statusKind!),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: DesignTokens.motionFast,
                    transitionBuilder: (Widget c, Animation<double> a) =>
                        ScaleTransition(scale: a, child: c),
                    child: Icon(
                      isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      key: ValueKey<bool>(isPaused),
                      color: Colors.white,
                      size: 96,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!isLive && total != null)
                _ProgressRow(
                  position: position,
                  total: total!,
                  buffered: buffered,
                ),
              const SizedBox(height: DesignTokens.spaceL),
              const Center(
                child: Text(
                  'OK: oynat / durdur     <- ->: 10sn ileri-geri     M: ayarlar     Geri: kapat',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.position,
    required this.total,
    required this.buffered,
  });
  final Duration position;
  final Duration total;
  final Duration buffered;

  @override
  Widget build(BuildContext context) {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final bufferedFrac = total.inMilliseconds == 0
        ? 0.0
        : (buffered.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      children: <Widget>[
        Text(
          _format(position),
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(width: DesignTokens.spaceM),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: <Widget>[
                  Container(color: Colors.white24),
                  FractionallySizedBox(
                    widthFactor: bufferedFrac,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(color: BrandColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spaceM),
        Text(
          _format(total),
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
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
