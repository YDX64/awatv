import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_chat_panel.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_controller.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_member_bar.dart';
import 'package:awatv_mobile/src/features/watch_party/watch_party_state.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart'
    show RemoteConnectionState;
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Threshold above which non-host members will auto-seek their player
/// to align with the host. Two seconds matches Netflix Party / Teleparty
/// — close enough that the talking heads stay in sync, far enough to
/// avoid jitter on a flaky connection.
const Duration _kDriftResyncThreshold = Duration(seconds: 2);

/// Cooldown between automatic re-syncs. Prevents a host with a noisy
/// position stream from causing the member to seek every second.
const Duration _kResyncCooldown = Duration(seconds: 5);

/// The actual party room. Top-left: a small video frame that mirrors
/// the host's playback. Top-right: collapsible chat panel. Top bar:
/// member chips with online status. Bottom: host transport controls
/// (host only) or a "syncing with host" line for guests.
class WatchPartyScreen extends ConsumerStatefulWidget {
  const WatchPartyScreen({
    required this.partyId,
    required this.userName,
    required this.isHost,
    super.key,
  });

  final String partyId;
  final String userName;
  final bool isHost;

  @override
  ConsumerState<WatchPartyScreen> createState() => _WatchPartyScreenState();
}

class _WatchPartyScreenState extends ConsumerState<WatchPartyScreen>
    with WidgetsBindingObserver {
  AwaPlayerController? _controller;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PartyCommand>? _cmdSub;

  bool _chatOpen = true;
  bool _isPaused = true;
  Duration _position = Duration.zero;
  Duration? _total;
  String? _activeChannelId;
  String? _errorMessage;
  Timer? _hostHeartbeatTimer;

  WatchPartyArgs get _args => WatchPartyArgs(
        partyId: widget.partyId,
        userName: widget.userName,
        isHost: widget.isHost,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootController();
    _attachCommandStream();
    if (widget.isHost) {
      _hostHeartbeatTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _publishSyncIfHost(),
      );
    }
  }

  Future<void> _bootController() async {
    try {
      final c = AwaPlayerController.empty();
      _controller = c;
      setState(() {});
      _stateSub = c.states.listen(_onPlayerState);
      _posSub = c.positions.listen((Duration p) {
        if (!mounted) return;
        setState(() => _position = p);
        _evaluateDrift();
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  void _onPlayerState(PlayerState s) {
    if (!mounted) return;
    switch (s) {
      case PlayerPlaying(:final position, :final total):
        setState(() {
          _isPaused = false;
          _position = position;
          _total = total;
          _errorMessage = null;
        });
        if (widget.isHost) _publishSyncIfHost();
      case PlayerPaused(:final position, :final total):
        setState(() {
          _isPaused = true;
          _position = position;
          _total = total;
        });
        if (widget.isHost) _publishSyncIfHost();
      case PlayerLoading():
        // Keep current state.
        break;
      case PlayerEnded():
        setState(() => _isPaused = true);
      case PlayerError(:final message):
        setState(() => _errorMessage = message);
      case PlayerIdle():
        break;
    }
  }

  void _attachCommandStream() {
    // Wait for the controller to be ready before subscribing — we do
    // this in build by reading the providers; this method just clears
    // any stale subscription so a hot-reload doesn't double-fire.
    _cmdSub?.cancel();
    _cmdSub = ref
        .read(watchPartyCommandStreamProvider(_args))
        .listen(_onPartyCommand);
  }

  void _onPartyCommand(PartyCommand cmd) {
    if (!mounted) return;
    if (cmd is PartySyncCommand && cmd.fromHost) {
      _onHostSync(cmd);
    }
  }

  Future<void> _onHostSync(PartySyncCommand cmd) async {
    // 1) Channel switch — if the host is on a different channel, switch
    //    our own player. Live channels carry the channelId so we can
    //    resolve the stream URL through the channels provider.
    final hostChannelId = cmd.channelId;
    if (hostChannelId != null &&
        hostChannelId.isNotEmpty &&
        hostChannelId != _activeChannelId &&
        !widget.isHost) {
      await _switchToChannel(hostChannelId);
    }

    // 2) Play/pause alignment. Only act when the local state contradicts.
    if (!widget.isHost) {
      final c = _controller;
      if (c == null) return;
      if (cmd.isPlaying && _isPaused) await c.play();
      if (!cmd.isPlaying && !_isPaused) await c.pause();

      // 3) Position alignment for VOD only — live streams have no
      //    seekable position, so we skip the drift check there.
      if (!cmd.isLive) {
        final drift =
            (_position.inMilliseconds - cmd.position.inMilliseconds).abs();
        if (drift > _kDriftResyncThreshold.inMilliseconds &&
            _shouldAttemptResync()) {
          await c.seek(cmd.position);
          ref
              .read(watchPartyControllerProvider(_args).notifier)
              .markResync();
        }
      }
    }
  }

  bool _shouldAttemptResync() {
    final last = ref
            .read(watchPartyControllerProvider(_args))
            .valueOrNull
            ?.lastResyncAtMs ??
        0;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return nowMs - last >= _kResyncCooldown.inMilliseconds;
  }

  void _evaluateDrift() {
    if (widget.isHost) return;
    final last = ref.read(watchPartyControllerProvider(_args)).valueOrNull;
    final hostSync = last?.lastSync;
    if (hostSync == null) return;
    final drift =
        _position.inMilliseconds - hostSync.position.inMilliseconds;
    ref
        .read(watchPartyControllerProvider(_args).notifier)
        .recordDrift(drift);
  }

  Future<void> _switchToChannel(String channelId) async {
    final c = _controller;
    if (c == null) return;
    final channels = await ref.read(liveChannelsProvider.future);
    Channel? target;
    for (final ch in channels) {
      if (ch.id == channelId) {
        target = ch;
        break;
      }
    }
    if (target == null) return;
    final urls =
        streamUrlVariants(target.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: target.name,
      userAgent: target.extras['http-user-agent'] ??
          target.extras['user-agent'],
    );
    final all = <MediaSource>[
      if (variants.isNotEmpty)
        variants.first
      else
        MediaSource(url: proxify(target.streamUrl), title: target.name),
      ...variants.length > 1
          ? variants.sublist(1)
          : const <MediaSource>[],
    ];
    setState(() {
      _activeChannelId = channelId;
      _total = null;
    });
    try {
      await c.openWithFallbacks(all);
      await c.play();
    } on PlayerException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    }
  }

  void _publishSyncIfHost() {
    if (!widget.isHost) return;
    final ctrl = ref.read(watchPartyControllerProvider(_args).notifier);
    final isLive = _total == null || _total == Duration.zero;
    unawaited(
      ctrl.publishSync(
        position: _position,
        isPlaying: !_isPaused,
        channelId: _activeChannelId,
        isLive: isLive,
      ),
    );
  }

  Future<void> _onChannelTapFromList(Channel ch) async {
    if (!widget.isHost) return;
    await _switchToChannel(ch.id);
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (_isPaused) {
      await c.play();
    } else {
      await c.pause();
    }
    _publishSyncIfHost();
  }

  @override
  void dispose() {
    _hostHeartbeatTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _cmdSub?.cancel();
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    final asyncSession = ref.watch(watchPartyControllerProvider(args));

    // Re-subscribe to the command stream whenever the controller flips
    // from loading to data.
    ref.listen(
      watchPartyControllerProvider(args),
      (AsyncValue<WatchPartyState>? prev, AsyncValue<WatchPartyState> next) {
        if (next.hasValue && _cmdSub == null) {
          _attachCommandStream();
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Watch parti  ·  ${widget.partyId}'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Parti kodunu kopyala',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.partyId));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Parti kodu kopyalandi: ${widget.partyId}'),
                ),
              );
            },
          ),
          IconButton(
            tooltip: _chatOpen ? 'Sohbeti kapat' : 'Sohbeti ac',
            icon: Icon(
              _chatOpen
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
            ),
            onPressed: () => setState(() => _chatOpen = !_chatOpen),
          ),
          IconButton(
            tooltip: 'Partiden ayril',
            icon: const Icon(Icons.exit_to_app_rounded),
            onPressed: () async {
              await ref
                  .read(watchPartyControllerProvider(args).notifier)
                  .leave();
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: asyncSession.when(
        loading: () => const LoadingView(label: 'Partiye baglaniyor'),
        error: (Object e, StackTrace _) => Center(
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Partiye baglanilamadi',
            subtitle: e.toString(),
          ),
        ),
        data: (WatchPartyState state) => _PartyBody(
          state: state,
          controller: _controller,
          chatOpen: _chatOpen,
          isPaused: _isPaused,
          isHost: widget.isHost,
          activeChannelId: _activeChannelId,
          errorMessage: _errorMessage,
          onTogglePlay: _togglePlay,
          onPickChannel: _onChannelTapFromList,
          onSendChat: (String message) => ref
              .read(watchPartyControllerProvider(args).notifier)
              .sendChat(message),
        ),
      ),
    );
  }
}

class _PartyBody extends ConsumerWidget {
  const _PartyBody({
    required this.state,
    required this.controller,
    required this.chatOpen,
    required this.isPaused,
    required this.isHost,
    required this.activeChannelId,
    required this.errorMessage,
    required this.onTogglePlay,
    required this.onPickChannel,
    required this.onSendChat,
  });

  final WatchPartyState state;
  final AwaPlayerController? controller;
  final bool chatOpen;
  final bool isPaused;
  final bool isHost;
  final String? activeChannelId;
  final String? errorMessage;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function(Channel ch) onPickChannel;
  final Future<void> Function(String message) onSendChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connecting = state.connection != RemoteConnectionState.connected;

    return Column(
      children: <Widget>[
        WatchPartyMemberBar(state: state),
        if (connecting)
          LinearProgressIndicator(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext _, BoxConstraints c) {
              final wide = c.maxWidth > 720;
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _PlayerFrame(
                      controller: controller,
                      isPaused: isPaused,
                      isHost: isHost,
                      onTogglePlay: onTogglePlay,
                      errorMessage: errorMessage,
                    ),
                  ),
                  Expanded(
                    child: _ChannelPickerOrSyncBanner(
                      isHost: isHost,
                      activeChannelId: activeChannelId,
                      hostSync: state.lastSync,
                      onPick: onPickChannel,
                    ),
                  ),
                ],
              );

              if (!wide || !chatOpen) {
                return Stack(
                  children: <Widget>[
                    body,
                    if (chatOpen)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(
                          width: c.maxWidth,
                          height: 240,
                          child: WatchPartyChatPanel(
                            state: state,
                            onSend: onSendChat,
                          ),
                        ),
                      ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: body),
                  SizedBox(
                    width: 320,
                    child: WatchPartyChatPanel(
                      state: state,
                      onSend: onSendChat,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlayerFrame extends StatelessWidget {
  const _PlayerFrame({
    required this.controller,
    required this.isPaused,
    required this.isHost,
    required this.onTogglePlay,
    required this.errorMessage,
  });

  final AwaPlayerController? controller;
  final bool isPaused;
  final bool isHost;
  final Future<void> Function() onTogglePlay;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (controller != null)
            AwaPlayerView(controller: controller!)
          else
            const ColoredBox(color: Colors.black),
          if (errorMessage != null)
            Center(
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            )
          else if (isHost)
            Positioned(
              bottom: 12,
              left: 12,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary.withValues(alpha: 0.9),
                ),
                onPressed: onTogglePlay,
                icon: Icon(
                  isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                label: Text(isPaused ? 'Oynat' : 'Duraklat'),
              ),
            )
          else
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusM),
                ),
                child: const Text(
                  'Host kontrol ediyor',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelPickerOrSyncBanner extends ConsumerWidget {
  const _ChannelPickerOrSyncBanner({
    required this.isHost,
    required this.activeChannelId,
    required this.hostSync,
    required this.onPick,
  });

  final bool isHost;
  final String? activeChannelId;
  final PartySyncCommand? hostSync;
  final Future<void> Function(Channel ch) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isHost) {
      // Members see what the host is watching.
      final hostChannel = hostSync?.channelId;
      return Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            Expanded(
              child: Text(
                hostChannel == null
                    ? 'Host yayina baslamadi'
                    : 'Host kanali: $hostChannel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    final channelsAsync = ref.watch(liveChannelsProvider);
    return channelsAsync.when(
      loading: () => const LoadingView(label: 'Kanallar yukleniyor'),
      error: (Object e, StackTrace _) => ErrorView(message: e.toString()),
      data: (List<Channel> all) {
        if (all.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Kanal yok',
              subtitle: 'Bir playlist ekleyince kanallarin burada gozukur.',
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
          itemCount: all.length,
          itemBuilder: (BuildContext _, int i) {
            final ch = all[i];
            final isActive = ch.id == activeChannelId;
            return ListTile(
              leading: Icon(
                isActive
                    ? Icons.play_circle_filled_rounded
                    : Icons.live_tv_outlined,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(ch.name),
              subtitle: ch.groups.isEmpty
                  ? null
                  : Text(ch.groups.first),
              onTap: () => onPick(ch),
            );
          },
        );
      },
    );
  }
}
