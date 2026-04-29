import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/desktop/always_on_top.dart';
import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/desktop/keyboard_shortcuts.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/desktop/pip_window.dart';
import 'package:awatv_mobile/src/desktop/widgets/now_playing_state.dart';
import 'package:awatv_mobile/src/features/player/player_backend_preference.dart';
import 'package:awatv_mobile/src/features/player/widgets/cast_device_picker.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_buffering_overlay.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_controls_layer.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_gestures.dart';
import 'package:awatv_mobile/src/features/parental/widgets/parental_lock_overlay.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_settings_sheet.dart';
import 'package:awatv_mobile/src/features/player/widgets/player_track_picker_sheet.dart';
import 'package:awatv_mobile/src/features/player/widgets/sleep_timer_sheet.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/background_playback/background_playback_controller.dart';
import 'package:awatv_mobile/src/shared/cast/cast_provider.dart';
import 'package:awatv_mobile/src/shared/channel_history/channel_history_provider.dart';
import 'package:awatv_mobile/src/shared/channel_history/channel_switcher.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_mobile/src/shared/parental/parental_controller.dart';
import 'package:awatv_mobile/src/shared/parental/parental_gate.dart';
import 'package:awatv_mobile/src/shared/parental/parental_settings.dart';
import 'package:awatv_mobile/src/shared/pip/mobile_pip.dart';
import 'package:awatv_mobile/src/shared/player/active_player_controller.dart';
import 'package:awatv_mobile/src/shared/player/sleep_timer.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
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
import 'package:window_manager/window_manager.dart';

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
  // Last time we published a position update to [nowPlayingProvider]. The
  // engine emits roughly 4 Hz; we throttle to 1 Hz so the persistent bar
  // doesn't ride a high-frequency rebuild train while the player is
  // composited on top of it.
  DateTime _lastNowPlayingPositionAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  bool _showControls = true;
  bool _isPaused = false;
  bool _buffering = false;
  bool _scrubbing = false;
  bool _firstFrameSeen = false;
  // True when we paused the player ourselves because the OS reported the
  // app was about to background (mobile only). Used by [didChangeAppLifecycleState]
  // to auto-resume on `resumed` so the user doesn't return to a frozen frame.
  bool _wasPlayingBeforeBackground = false;
  Duration _position = Duration.zero;
  Duration _bufferedPos = Duration.zero;
  Duration? _total;
  String? _errorMessage;
  int? _videoHeight;
  bool _lowBandwidth = false;

  /// Brief "Channel: BBC One" toast surfaced after a P+/P-/L switch.
  /// Cleared after [_kChannelToastDuration] so the player surface
  /// returns to a clean frame.
  String? _channelToastText;
  Timer? _channelToastTimer;
  static const Duration _kChannelToastDuration = Duration(seconds: 2);

  // Brightness/volume mirrors that survive a single drag — actual
  // brightness control requires a native plugin and is intentionally
  // out of scope per AGENT instructions; volume goes through media_kit.
  double _volume = 1; // 0..1
  BoxFit _videoFit = BoxFit.contain;

  PlayerGestureFeedback _gestureFeedback = const PlayerGestureFeedback(
    kind: PlayerGestureKind.none,
    value: 0,
  );

  /// Parental-gate decision for the current launch. Set to a non-`allowed`
  /// value when the active profile is forbidden from watching this
  /// content; the lock overlay reads this to render the correct title /
  /// subtitle. Reset to `allowed` after a successful PIN unlock.
  ParentalGateOutcome _parentalOutcome = ParentalGateOutcome.allowed;

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
      //
      // Honour the persisted backend preference. The factory falls back
      // to media_kit silently on platforms where VLC isn't supported
      // (web / macOS / Windows / Linux), so we can pass the user's
      // preference through unconditionally.
      final preferred = ref.read(playerBackendPreferenceProvider);
      final c = AwaPlayerController.empty(backend: preferred);
      _controller = c;
      // Surface the controller into the build immediately so AwaPlayerView
      // can attach its texture before bytes start flowing.
      setState(() {});

      // Publish to the persistent player bar + the controller registry as
      // soon as we have a controller. The bar paints from `nowPlayingProvider`
      // (display) and reaches back into `activePlayerControllerProvider`
      // (control) — both come up front so the bar can flip from "hidden" to
      // "visible with title + thumb" the instant the route mounts.
      _publishNowPlaying(c);
      ref.read(activePlayerControllerProvider.notifier).attach(c);

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
        _tickNowPlayingPosition(p);
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

      // Wire the player into the sleep timer so a fade/pause from the
      // notifier acts on the live engine. Reattaches automatically when
      // the user switches backend (the controller instance changes).
      ref.read(sleepTimerProvider.notifier).attachController(c);

      // Hand the controller to the OS media-session bridge so the lock
      // screen / Bluetooth headset / Android Auto can drive playback.
      // Returns null on web — that platform has no system playback UI
      // to populate, so we skip silently.
      try {
        final handler = ref.read(audioHandlerProvider);
        handler
          ?..bind(c)
          ..updateNowPlaying(
            id: widget.args.itemId ?? widget.args.title ?? 'awatv:stream',
            title: widget.args.title ?? 'AWAtv',
            artist: widget.args.subtitle,
            isLive: widget.args.isLive,
          );
      } on Object {
        // Best-effort — losing the lock-screen tile must never block
        // the on-screen playback.
      }

      // Push the active channel into the history so P+/P-/L work even
      // on first launch. Best-effort; never blocks playback.
      _pushChannelHistoryIfLive();

      // Evaluate parental gate against the active profile. Does nothing
      // when parental controls are disabled or the active profile is a
      // grown-up — see [ParentalGate.evaluate].
      _evaluateParentalGate();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  /// Pushes the launch's channel id onto the channel-history service so
  /// the smart-switcher P+/P-/L buttons have a starting position. No-op
  /// when the launch was for VOD or a series.
  void _pushChannelHistoryIfLive() {
    final id = widget.args.itemId;
    if (id == null || id.isEmpty) return;
    if (!widget.args.isLive) return;
    final svc = ref.read(channelHistoryServiceProvider);
    unawaited(svc.push(id));
  }

  /// Steps to the channel adjacent to the current one inside the live
  /// channel pool. P+ -> next, P- -> previous. Wraps around at edges,
  /// shows a toast with the resolved channel name.
  Future<void> _stepChannel(ChannelStepDirection direction) async {
    if (!widget.args.isLive) return;
    final pool = await ref.read(liveChannelsProvider.future);
    final next = pickAdjacentChannel(
      pool: pool,
      currentId: widget.args.itemId,
      direction: direction,
    );
    if (next == null) return;
    await _switchToChannel(next);
  }

  /// Toggles back to the second-most-recently-watched channel.
  Future<void> _switchToLastChannel() async {
    if (!widget.args.isLive) return;
    final pool = await ref.read(liveChannelsProvider.future);
    final history = ref.read(channelHistoryServiceProvider).entries;
    final next = pickLastChannel(
      pool: pool,
      historyIds: history,
      currentId: widget.args.itemId,
    );
    if (next == null) {
      _showChannelToast('Son kanal yok');
      return;
    }
    await _switchToChannel(next);
  }

  /// Numeric tune-to (Numpad 0..9). Picks the Nth live channel and
  /// switches to it; no-op outside the live context.
  Future<void> _tuneToNumericSlot(int slot) async {
    if (!widget.args.isLive) return;
    final pool = await ref.read(liveChannelsProvider.future);
    final next = pickByNumericSlot(pool: pool, slot: slot);
    if (next == null) return;
    await _switchToChannel(next);
  }

  /// Replaces the current player route with [target]. We use go_router's
  /// `pushReplacement` so the back stack stays the right depth — the
  /// user pressed P+, not "open another player on top".
  Future<void> _switchToChannel(Channel target) async {
    final headers = <String, String>{};
    final ua = target.extras['http-user-agent'] ??
        target.extras['user-agent'];
    final referer = target.extras['http-referrer'] ??
        target.extras['referer'] ??
        target.extras['Referer'];
    if (referer != null && referer.isNotEmpty) headers['Referer'] = referer;

    final urls =
        streamUrlVariants(target.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: target.name,
      userAgent: ua,
      headers: headers.isEmpty ? null : headers,
    );
    final args = PlayerLaunchArgs(
      source: variants.isEmpty
          ? MediaSource(
              url: proxify(target.streamUrl),
              title: target.name,
              userAgent: ua,
              headers: headers.isEmpty ? null : headers,
            )
          : variants.first,
      fallbacks: variants.length <= 1
          ? const <MediaSource>[]
          : variants.sublist(1),
      title: target.name,
      subtitle: target.groups.isEmpty ? null : target.groups.first,
      itemId: target.id,
      kind: HistoryKind.live,
      isLive: true,
    );

    // Record the push BEFORE the route swap so the new player route's
    // boot finds the up-to-date "current channel" at index 0.
    await ref.read(channelHistoryServiceProvider).push(target.id);

    _showChannelToast('Kanal: ${target.name}');

    if (!mounted) return;
    context.pushReplacement('/play', extra: args);
  }

  void _showChannelToast(String text) {
    _channelToastTimer?.cancel();
    setState(() => _channelToastText = text);
    _channelToastTimer = Timer(_kChannelToastDuration, () {
      if (!mounted) return;
      setState(() => _channelToastText = null);
    });
  }

  void _evaluateParentalGate() {
    final settings = ref.read(parentalSettingsProvider).valueOrNull ??
        const ParentalSettings();
    final profile = ref.read(activeProfileProvider);
    final controller = ref.read(parentalControllerProvider);
    final gate = ParentalGate(
      settings: settings,
      profile: profile,
      controller: controller,
    );
    // Heuristic: pass through whatever signal we have. Live channels
    // surface a category from `subtitle`/`title`; VOD payloads aren't
    // available here, so we lean on the rating-by-category check via
    // the bracketed subtitle (e.g. "Action / 18+").
    final outcome = gate.evaluate(
      category: widget.args.subtitle,
    );
    if (outcome != ParentalGateOutcome.allowed) {
      // Pause immediately so the kids profile doesn't catch a frame
      // before the overlay shows.
      _controller?.pause();
    }
    if (mounted) {
      setState(() => _parentalOutcome = outcome);
    } else {
      _parentalOutcome = outcome;
    }
  }

  void _onParentalUnlocked() {
    setState(() => _parentalOutcome = ParentalGateOutcome.allowed);
    // Resume playback if the controller was paused by the gate.
    _controller?.play();
  }

  void _onParentalCancel() {
    // The user backed out instead of entering a PIN — pop the player
    // route. Honour the same back behaviour the close button uses so
    // immersive UI restores cleanly via `_exitImmersive` in dispose.
    if (context.canPop()) context.pop();
  }

  /// Throttled position tee — pumps the engine's high-frequency position
  /// stream into the persistent bar at ~1 Hz. Live streams skip the
  /// duration write entirely (the bar paints the striped indicator
  /// instead). The throttle is a wall-clock check rather than a Timer so
  /// we avoid keeping a separate timer alive while the player itself is
  /// already pulsing.
  void _tickNowPlayingPosition(Duration position) {
    final now = DateTime.now();
    if (now.difference(_lastNowPlayingPositionAt).inMilliseconds < 1000) {
      return;
    }
    _lastNowPlayingPositionAt = now;
    ref.read(nowPlayingProvider.notifier).update(
          position: position,
          duration: widget.args.isLive ? Duration.zero : _total,
          isPlaying: !_isPaused,
        );
  }

  /// Pushes a fresh [NowPlaying] payload into the persistent-bar provider.
  /// Called once at boot (so the bar flips from hidden to visible) and
  /// then continuously through [_onPlayerState] / [_onPositionTick] for
  /// position + isPlaying updates.
  void _publishNowPlaying(AwaPlayerController c) {
    final args = widget.args;
    ref.read(nowPlayingProvider.notifier).start(
          NowPlaying(
            title: args.title ?? 'AWAtv',
            kind: args.kind ?? HistoryKind.vod,
            subtitle: args.subtitle,
            thumbnailUrl: null, // Player launch args don't carry artwork.
            itemId: args.itemId,
            isLive: args.isLive,
            isPlaying: true,
            source: args.source,
          ),
        );
  }

  /// Wires this player into the remote-control bridge and publishes the
  /// active playback context. We always publish (not just when a remote
  /// session is alive) so secondary consumers — the desktop system tray
  /// "now playing" label, future widgets — can read the title without
  /// each subscribing through the bridge.
  ///
  /// The remote bridge is only instantiated when a receiver session is
  /// active, so its method-channel cost is still gated.
  void _publishToBridgeIfReceiving() {
    final c = _controller;
    if (c == null) return;
    ref.read(activePlaybackProvider.notifier).set(
          PlaybackContext(
            controller: c,
            title: widget.args.title,
            subtitle: widget.args.subtitle,
            itemId: widget.args.itemId,
            isLive: widget.args.isLive,
          ),
        );
    final session = ref.read(receiverSessionControllerProvider);
    if (session.hasValue) {
      // Touch the bridge so it instantiates and listens for commands.
      ref.read(ensurePlayerBridgeProvider);
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
        // Force-publish on a transition (bypasses the position throttle)
        // so the bar's icon flips the moment playback resumes.
        _lastNowPlayingPositionAt =
            DateTime.fromMillisecondsSinceEpoch(0);
        ref.read(nowPlayingProvider.notifier).update(
              position: position,
              duration: widget.args.isLive ? Duration.zero : total,
              isPlaying: true,
            );
      case PlayerPaused(:final position, :final total):
        setState(() {
          _isPaused = true;
          _buffering = false;
          _position = position;
          _total = total;
          _showControls = true;
        });
        ref.read(nowPlayingProvider.notifier).update(
              position: position,
              duration: widget.args.isLive ? Duration.zero : total,
              isPlaying: false,
            );
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
        ref.read(nowPlayingProvider.notifier).update(isPlaying: false);
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

  Future<void> _onPipRequested() async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.pictureInPicture));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.pictureInPicture);
      return;
    }
    // On desktop we toggle the compact always-on-top window. On mobile
    // (iOS / Android) we drive the OS-native PiP via [MobilePip].
    if (!kIsWeb && isDesktopRuntime()) {
      try {
        await ref.read(pipWindowControllerProvider).toggle();
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PiP açılamadı: $e')),
        );
      }
      return;
    }
    if (!MobilePip.isPlatformSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu platform PiP destegine sahip degil.'),
        ),
      );
      return;
    }
    final result = await MobilePip.enter();
    if (!mounted) return;
    switch (result) {
      case MobilePipResult.entered:
        // Mirror to the in-app provider so any UI that wants to slim
        // the controls layer can pick it up. Best-effort — Android's
        // status stream pushes the same value asynchronously.
        ref.read(mobilePipModeProvider.notifier).set(true);
      case MobilePipResult.unsupported:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Bu cihaz Picture-in-Picture desteklemiyor.'),
          ),
        );
      case MobilePipResult.disabled:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PiP kapali — Ayarlar > Uygulamalar > AWAtv menusunden ac.',
            ),
          ),
        );
      case MobilePipResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PiP baslatilamadi.')),
        );
      case MobilePipResult.notMobile:
        // Already handled above by the desktop branch.
        break;
    }
  }

  /// Handles a tap on the always-on-top toggle (top bar pin icon /
  /// settings sheet switch / Cmd+Shift+T shortcut). Free users see the
  /// upsell sheet instead. Honours the toggle in PiP mode by exiting
  /// PiP first — PiP forces always-on-top regardless of preference, so
  /// untoggling while compact would leave the user with a tiny window
  /// they don't want pinned.
  Future<void> _onAlwaysOnTopRequested() async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.alwaysOnTop));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.alwaysOnTop);
      return;
    }
    if (!isDesktopRuntime()) {
      // Mobile / TV / web don't have the concept; surface a hint
      // rather than silently swallowing the gesture.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pencere sabitleme yalnızca masaüstünde kullanılabilir.',
          ),
        ),
      );
      return;
    }
    try {
      final next = await ref.read(alwaysOnTopProvider.notifier).toggle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Pencere üstte sabitlendi.'
                : 'Pencere sabitlemesi kaldırıldı.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sabitleme uygulanamadı: $e')),
      );
    }
  }

  Future<void> _onCastRequested() async {
    final c = _controller;
    if (c == null) return;
    _hideTimer?.cancel();
    final cast = ref.read(castControllerProvider);
    await CastDevicePicker.show(
      context,
      onConnectAndMirror: (CastDevice device) async {
        // 1) connect to the device,
        // 2) hand the active media source over to the engine,
        // 3) the engine emits a CastConnected state — the picker dismisses.
        await cast.connect(device);
        try {
          await cast.mirror(
            widget.args.source,
            localController: c,
            title: widget.args.title,
            subtitle: widget.args.subtitle,
            isLive: widget.args.isLive,
          );
        } on CastNotConnectedException {
          // Connect probably emitted CastError — the picker shows it.
        } on Object catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Yayın başlatılamadı: $e')),
          );
        }
      },
      onDisconnect: () async {
        await cast.unmirror(
          localController: c,
          // Live streams don't have a meaningful resume point — still
          // re-`play()` the local engine so the user sees the current
          // live frame instead of a paused one.
          resumeLocal: true,
        );
      },
    );
    if (!mounted) return;
    _scheduleHide();
  }

  Future<void> _onSettingsRequested() async {
    final c = _controller;
    if (c == null) return;
    _hideTimer?.cancel();
    await PlayerSettingsSheet.show(
      context,
      controller: c,
      onOpenTracks: _onTracksRequested,
    );
    if (!mounted) return;
    _scheduleHide();
  }

  /// Opens the unified audio / subtitle / quality picker. Triggered from
  /// the dedicated CC button in the top bar and from the "Audio /
  /// Subtitle / Quality" entries inside the settings sheet.
  Future<void> _onTracksRequested() async {
    final c = _controller;
    if (c == null) return;
    _hideTimer?.cancel();
    await PlayerTrackPickerSheet.show(
      context,
      controller: c,
      searchHint: widget.args.title,
    );
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

  Future<void> _onBackendToggleRequested() async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.vlcBackend));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.vlcBackend);
      return;
    }
    // The backend picker lives inside the unified settings sheet so the
    // user always reaches it through the same surface. Selecting a
    // different backend triggers `_switchBackend` below, which restarts
    // playback against the same source list.
    final c = _controller;
    if (c == null) return;
    _hideTimer?.cancel();
    await PlayerSettingsSheet.show(
      context,
      controller: c,
      onBackendChanged: _switchBackend,
    );
    if (!mounted) return;
    _scheduleHide();
  }

  /// Tears down the active controller and rebuilds it against [next].
  ///
  /// We persist the choice via [playerBackendPreferenceProvider] so the
  /// next launch picks the same engine, then walk the variant chain
  /// again so playback resumes against whichever URL shape the new
  /// backend likes best.
  Future<void> _switchBackend(PlayerBackend next) async {
    await ref.read(playerBackendPreferenceProvider.notifier).set(next);
    final old = _controller;
    if (old != null && old.backend == next) return;

    // Cancel current subscriptions before tearing down the controller —
    // otherwise we'd briefly receive late events from the disposed engine.
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _bufferedSub?.cancel();
    await _heightSub?.cancel();
    _stateSub = null;
    _positionSub = null;
    _bufferedSub = null;
    _heightSub = null;

    setState(() {
      _controller = null;
      _firstFrameSeen = false;
      _errorMessage = null;
    });
    if (old != null) {
      ref.read(activePlayerControllerProvider.notifier).detach(old);
    }
    try {
      await old?.dispose();
    } on Object {
      // Best-effort cleanup; the new engine doesn't depend on the old
      // one being fully torn down.
    }

    final fresh = AwaPlayerController.empty(backend: next);
    _controller = fresh;
    setState(() {});

    // Hand the fresh controller to the persistent bar / control registry
    // so its play-pause/volume buttons keep working across the swap.
    _publishNowPlaying(fresh);
    ref.read(activePlayerControllerProvider.notifier).attach(fresh);

    _stateSub = fresh.states.listen(
      _onPlayerState,
      onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() => _errorMessage = e.toString());
      },
    );
    _positionSub = fresh.positions.listen((Duration p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (!_firstFrameSeen && p > Duration.zero) _firstFrameSeen = true;
      });
      _tickNowPlayingPosition(p);
    });
    _bufferedSub = fresh.buffered.listen((Duration b) {
      if (!mounted) return;
      setState(() => _bufferedPos = b);
      _evaluateLowBandwidth();
    });
    _heightSub = fresh.videoHeightStream.listen((int? h) {
      if (!mounted) return;
      setState(() => _videoHeight = h);
    });

    try {
      await fresh.openWithFallbacks(widget.args.allSources);
    } on PlayerException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
    // Re-bind the sleep timer to the new engine so an active fade
    // continues to act on the new audio path.
    ref.read(sleepTimerProvider.notifier).attachController(fresh);
    // Re-attach the OS media-session bridge to the fresh controller so
    // lock-screen / Bluetooth controls keep working across an engine
    // swap. Best-effort; never blocks playback.
    try {
      ref.read(audioHandlerProvider)?.bind(fresh);
    } on Object {
      // best-effort
    }
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
    _channelToastTimer?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _heightSub?.cancel();
    // Detach the persistent-bar control pointer + hide the bar. We do
    // this before tearing the controller down so the bar's
    // `ref.watch(activePlayerControllerProvider)` doesn't briefly point
    // at a disposed engine.
    try {
      final c = _controller;
      if (c != null) {
        ref.read(activePlayerControllerProvider.notifier).detach(c);
      }
      ref.read(nowPlayingProvider.notifier).clear();
    } on Object {
      // best-effort
    }
    // Detach this player from the remote-control bridge before tearing
    // down the controller so the bridge does not hold a dangling ref.
    // Wrapped because the provider scope may already be gone if the
    // app is being torn down entirely.
    try {
      ref.read(activePlaybackProvider.notifier).clear();
    } on Object {
      // ignore: best-effort cleanup
    }
    // Detach the sleep-timer controller pointer (the timer itself is
    // app-scoped — cancelling it here would surprise users who set a
    // 30-min timer and then closed the player).
    try {
      ref.read(sleepTimerProvider.notifier).attachController(null);
    } on Object {
      // best-effort
    }
    // Tear down the OS media-session bridge so the lock-screen tile
    // disappears and the foreground-service notification gets cancelled
    // on Android. Wrapped because the audio handler may be null on web
    // / on platforms where init failed.
    try {
      ref.read(audioHandlerProvider)?.bind(null);
    } on Object {
      // best-effort
    }
    _controller?.dispose();
    _exitImmersive();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mobile (iOS / Android): respect OS-level background pause — when the
    // app moves off-screen we should release the audio focus and stop
    // decoding to play nice with other apps and the battery.
    //
    // Desktop (macOS / Windows / Linux): `inactive` fires whenever the
    // window simply loses focus — Cmd+Tab to a browser, clicking another
    // app, etc. Pausing the player there is wrong: the user expects
    // playback (especially live IPTV / a movie they're watching while
    // working) to keep going in the background. Only `detached` is a real
    // shutdown signal on desktop, and at that point we're tearing down
    // anyway, so a defensive pause is unnecessary.
    final bgEnabled = ref.read(backgroundPlaybackProvider);
    final canBg =
        ref.read(canUseFeatureProvider(PremiumFeature.backgroundPlayback));
    final canPip =
        ref.read(canUseFeatureProvider(PremiumFeature.pictureInPicture));
    final isMobile = !kIsWeb && !isDesktopRuntime();
    final isMobileBackground = isMobile &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive);
    // If the user is premium with PiP unlocked and we're on a mobile
    // platform that supports it, ask the OS to enter PiP rather than
    // pausing. The OS will start a floating frame; on resume we don't
    // need to do anything because the activity / scene comes back to
    // its previous state. Best-effort: a failure falls through to the
    // pause branch below.
    if (isMobileBackground &&
        canPip &&
        !_isPaused &&
        MobilePip.isPlatformSupported &&
        state == AppLifecycleState.inactive) {
      // Fire-and-forget — we can't await here without blocking the
      // lifecycle callback. Best case: PiP enters before paused
      // arrives. Worst case: we pause, then the user can rotate back.
      unawaited(MobilePip.enter().then((MobilePipResult r) {
        if (r == MobilePipResult.entered && mounted) {
          ref.read(mobilePipModeProvider.notifier).set(true);
        }
      }));
    }
    final shouldPauseOnBackground = isMobileBackground && !(bgEnabled && canBg);
    if (shouldPauseOnBackground) {
      // Remember we were playing so we can auto-resume on `resumed`.
      if (!_isPaused) {
        _wasPlayingBeforeBackground = true;
      }
      _controller?.pause();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Coming back from PiP / background — clear the local PiP flag
      // so the controls layer renders the full chrome again.
      ref.read(mobilePipModeProvider.notifier).set(false);
      if (_wasPlayingBeforeBackground) {
        _wasPlayingBeforeBackground = false;
        _controller?.play();
      }
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
    final inPip = isDesktop ? ref.watch(pipModeProvider) : false;
    final statusKind = _statusKindForOverlay();
    final showBuffering = _buffering && !_isPaused && _firstFrameSeen;
    // Cast affordances are mobile-only — Chromecast on Android, AirPlay on
    // iOS. On web / desktop / TV the engine is a NoOp and the icon is
    // hidden. We don't gate this on the premium feature flag — single-
    // device casting is free; only multi-device casting is premium.
    final castVisible = !kIsWeb &&
        !isDesktop &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final castActive = ref.watch(castIsActiveProvider);
    final castDeviceName = ref.watch(castConnectedDeviceNameProvider);
    // Always-on-top is desktop-only — the toggle is hidden on every
    // other runtime. We still watch the provider unconditionally so the
    // top bar pin icon flips immediately when the tray menu / settings
    // sheet / shortcut updates the state from elsewhere.
    final alwaysOnTopActive = isDesktop ? ref.watch(alwaysOnTopProvider) : false;
    final alwaysOnTopVisible = isDesktop;

    if (inPip) {
      // Compact PiP layout: video frame fills the small always-on-top
      // window, with a hover-revealed exit button. No nav, no top bar,
      // no settings — the regular layout returns the moment the user
      // exits PiP via the corner button or tray menu.
      return PopScope(
        // Intercept back navigation: if the user hits Escape or
        // platform-back while in PiP, exit PiP rather than dropping the
        // route. Prevents the awkward state where the window is still
        // tiny but the player route has unmounted.
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) async {
          if (didPop) return;
          await _onPipRequested();
        },
        child: _PipCompactLayout(
          controller: controller,
          videoFit: _videoFit,
          isPaused: _isPaused,
          onTogglePlay: _togglePlay,
          onExitPip: _onPipRequested,
          onClose: _onClose,
        ),
      );
    }

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
                  // unawaited(): VoidCallback wants `void Function()`,
                  // but `_onCastRequested` is async. Fire-and-forget — the
                  // sheet itself manages the async UX.
                  onCastRequested: () {
                    unawaited(_onCastRequested());
                  },
                  onSettingsRequested: _onSettingsRequested,
                  onScrubStartChanged: (bool active) {
                    setState(() => _scrubbing = active);
                    if (!active) _scheduleHide();
                  },
                  statusBadge: statusKind == null
                      ? null
                      : NetworkStatusBadge(kind: statusKind),
                  castVisible: castVisible,
                  castActive: castActive,
                  castDeviceName: castDeviceName,
                  alwaysOnTopVisible: alwaysOnTopVisible,
                  alwaysOnTopActive: alwaysOnTopActive,
                  onAlwaysOnTopRequested: () {
                    unawaited(_onAlwaysOnTopRequested());
                  },
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
                          tooltip: isDesktop
                              ? 'Picture in picture (kompakt pencere)'
                              : 'Picture in picture',
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
                        IconButton(
                          tooltip: 'Altyazı / ses / kalite',
                          onPressed: _onTracksRequested,
                          icon: const Icon(
                            Icons.closed_caption_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const _SleepTimerButton(),
                      ],
                    ),
                  ),
                ),
              ),
            // Smart channel switcher — P+ / Last / P- buttons stacked
            // vertically near the bottom-right of the centre cluster.
            // Only rendered for live streams (live=true). Visible only
            // while the controls layer is shown.
            if (widget.args.isLive && _showControls)
              Positioned(
                bottom: 96,
                right: DesignTokens.spaceM,
                child: _ChannelSwitcherCluster(
                  onNext: () =>
                      unawaited(_stepChannel(ChannelStepDirection.next)),
                  onPrev: () => unawaited(
                    _stepChannel(ChannelStepDirection.previous),
                  ),
                  onLast: () => unawaited(_switchToLastChannel()),
                ),
              ),
            // "Channel: BBC One" toast — fades in for 2 seconds after
            // a P+/P-/L switch.
            if (_channelToastText != null)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: _ChannelToast(text: _channelToastText!),
                ),
              ),
            // Parental lock overlay sits above gestures + controls when
            // the active profile is forbidden from this content. Wins
            // hit-test against everything underneath via Material's
            // opaque scrim.
            if (_parentalOutcome != ParentalGateOutcome.allowed)
              ParentalLockOverlay(
                outcome: _parentalOutcome,
                onUnlocked: _onParentalUnlocked,
                onCancel: _onParentalCancel,
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
            onToggleAlwaysOnTop: () {
              unawaited(_onAlwaysOnTopRequested());
            },
            onChannelNext: widget.args.isLive
                ? () => unawaited(
                      _stepChannel(ChannelStepDirection.next),
                    )
                : null,
            onChannelPrev: widget.args.isLive
                ? () => unawaited(
                      _stepChannel(ChannelStepDirection.previous),
                    )
                : null,
            onChannelLast: widget.args.isLive
                ? () => unawaited(_switchToLastChannel())
                : null,
            onChannelTuneTo: widget.args.isLive
                ? (int slot) => unawaited(_tuneToNumericSlot(slot))
                : null,
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

/// Minimal compact-mode layout used when the desktop window has been
/// resized into PiP form. We deliberately don't reuse `PlayerControlsLayer`
/// here — that widget assumes a full-size player with room for a top bar
/// and bottom scrub timeline. PiP gets a single play/pause button and an
/// exit-PiP affordance, both fading on hover so the video frame stays the
/// hero.
class _PipCompactLayout extends StatefulWidget {
  const _PipCompactLayout({
    required this.controller,
    required this.videoFit,
    required this.isPaused,
    required this.onTogglePlay,
    required this.onExitPip,
    required this.onClose,
  });

  final AwaPlayerController? controller;
  final BoxFit videoFit;
  final bool isPaused;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function() onExitPip;
  final VoidCallback onClose;

  @override
  State<_PipCompactLayout> createState() => _PipCompactLayoutState();
}

class _PipCompactLayoutState extends State<_PipCompactLayout> {
  bool _hover = false;
  Timer? _hideTimer;

  void _show() {
    setState(() => _hover = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _hover = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Material(
      color: Colors.black,
      child: MouseRegion(
        onHover: (_) => _show(),
        onEnter: (_) => _show(),
        onExit: (_) => setState(() => _hover = false),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (c != null)
              AwaPlayerView(controller: c, fit: widget.videoFit)
            else
              const ColoredBox(color: Colors.black),
            // Tap-anywhere toggles play/pause — matches user expectation
            // when the window is small enough that hitting an icon is
            // fiddly.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _show();
                  widget.onTogglePlay();
                },
                onPanStart: (_) {
                  // Drag from the video surface itself — handy because
                  // there's no titlebar in compact mode.
                  windowManager.startDragging();
                },
                onDoubleTap: widget.onExitPip,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_hover,
                child: _PipOverlayControls(
                  isPaused: widget.isPaused,
                  onTogglePlay: widget.onTogglePlay,
                  onExitPip: widget.onExitPip,
                  onClose: widget.onClose,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipOverlayControls extends StatelessWidget {
  const _PipOverlayControls({
    required this.isPaused,
    required this.onTogglePlay,
    required this.onExitPip,
    required this.onClose,
  });

  final bool isPaused;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function() onExitPip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scrim = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(child: scrim),
        // Top-right: exit PiP + close.
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PipBtn(
                icon: Icons.fullscreen_rounded,
                tooltip: 'Tam pencereye dön',
                onTap: onExitPip,
              ),
              _PipBtn(
                icon: Icons.close_rounded,
                tooltip: 'Kapat',
                onTap: () => onClose(),
              ),
            ],
          ),
        ),
        // Centre: play/pause.
        Center(
          child: _PipBtn(
            icon: isPaused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            tooltip: isPaused ? 'Oynat' : 'Duraklat',
            onTap: onTogglePlay,
            size: 44,
          ),
        ),
      ],
    );
  }
}

class _PipBtn extends StatelessWidget {
  const _PipBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final FutureOr<void> Function() onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              final r = onTap();
              if (r is Future) {
                // Fire-and-forget — the overlay caller doesn't care
                // when the platform call completes.
                unawaited(r);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, color: Colors.white, size: size),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-right control that opens the [SleepTimerSheet]. When a timer is
/// active the button collapses into a chip showing remaining time
/// ("44:28 kaldı") so the user can confirm at a glance — matching
/// the Netflix/YouTube TV UX.
class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerProvider);
    if (!state.isActive) {
      return IconButton(
        tooltip: 'Uyku zamanlayıcısı',
        onPressed: () => SleepTimerSheet.show(context),
        icon: const Icon(
          Icons.bedtime_outlined,
          color: Colors.white,
        ),
      );
    }
    // Watching the tick stream is what drives the chip's countdown.
    final now = ref.watch(sleepTimerTickProvider).value ?? DateTime.now();
    final remaining = state.remaining(now.toUtc()) ?? Duration.zero;
    final label = state.fading
        ? 'Sönüyor…'
        : '${_format(remaining)} kaldı';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Tooltip(
        message: 'Uyku zamanlayıcısı aktif',
        child: Material(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            onTap: () => SleepTimerSheet.show(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.bedtime_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

/// Vertical cluster of three small buttons surfaced near the bottom-
/// right of the live-channel player overlay. P+ steps to the next
/// channel inside the current pool, P- to the previous, and the rotate
/// arrow ("Last") flips back to the second-most-recently-watched.
class _ChannelSwitcherCluster extends StatelessWidget {
  const _ChannelSwitcherCluster({
    required this.onNext,
    required this.onPrev,
    required this.onLast,
  });

  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SwitcherBtn(
          icon: Icons.keyboard_arrow_up_rounded,
          tooltip: 'Sonraki kanal (P+)',
          onTap: onNext,
        ),
        const SizedBox(height: 8),
        _SwitcherBtn(
          icon: Icons.swap_calls_rounded,
          tooltip: 'Son kanal (L)',
          onTap: onLast,
        ),
        const SizedBox(height: 8),
        _SwitcherBtn(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: 'Onceki kanal (P-)',
          onTap: onPrev,
        ),
      ],
    );
  }
}

class _SwitcherBtn extends StatelessWidget {
  const _SwitcherBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Brief "Channel: X" toast surfaced after a P+/P-/L switch. Fades out
/// automatically after [_PlayerScreenState._kChannelToastDuration].
class _ChannelToast extends StatelessWidget {
  const _ChannelToast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 220),
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
            vertical: DesignTokens.spaceS,
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

