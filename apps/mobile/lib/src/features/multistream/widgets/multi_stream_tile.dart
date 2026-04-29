import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_session.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_state.dart';
import 'package:awatv_mobile/src/features/player/player_backend_preference.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One tile in the 4-channel multi-stream grid.
///
/// Owns a single [AwaPlayerController]: created in `initState`, opened
/// against the slot's source list, disposed in `dispose`. Audio is
/// driven by the session's [MultiStreamState.activeSlotIndex] —
/// every other tile pulls volume to 0 so the user only hears the
/// active stream.
///
/// Tap to mark active. Long-press opens a "Cikar" / "Degistir" menu.
class MultiStreamTile extends ConsumerStatefulWidget {
  const MultiStreamTile({
    required this.slot,
    required this.index,
    required this.isActive,
    required this.masterMuted,
    super.key,
  });

  final MultiStreamSlot slot;
  final int index;
  final bool isActive;
  final bool masterMuted;

  @override
  ConsumerState<MultiStreamTile> createState() => _MultiStreamTileState();
}

class _MultiStreamTileState extends ConsumerState<MultiStreamTile> {
  AwaPlayerController? _controller;
  StreamSubscription<PlayerState>? _stateSub;
  bool _booting = true;
  String? _errorMessage;
  bool _firstFrameSeen = false;

  @override
  void initState() {
    super.initState();
    // Defer to post-frame so the tile lays out first; opening many
    // controllers on the same micro-task spike causes early decoders
    // to time out on slower phones.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    try {
      // Use the user's persisted backend preference so the multi-grid
      // honours the same engine choice as the single-stream player.
      final preferred = ref.read(playerBackendPreferenceProvider);
      final c = AwaPlayerController.empty(backend: preferred);
      _controller = c;
      _stateSub = c.states.listen(_onState, onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() => _errorMessage = e.toString());
      });
      // Start muted; the audio-routing effect below will unmute the
      // active tile after the first frame lands.
      await c.setVolume(0);
      try {
        await c.openWithFallbacks(widget.slot.allSources);
      } on PlayerException catch (e) {
        if (!mounted) return;
        setState(() => _errorMessage = e.message);
      }
      if (!mounted) return;
      setState(() => _booting = false);
      unawaited(_applyAudioRouting());
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _onState(PlayerState state) {
    if (!mounted) return;
    switch (state) {
      case PlayerPlaying():
        if (!_firstFrameSeen) {
          setState(() {
            _firstFrameSeen = true;
            _errorMessage = null;
          });
          _applyAudioRouting();
        }
      case PlayerError(:final message):
        setState(() => _errorMessage = message);
      case PlayerLoading():
      case PlayerPaused():
      case PlayerEnded():
      case PlayerIdle():
        break;
    }
  }

  /// Pushes the right volume into the engine for this tile based on
  /// `isActive` + `masterMuted`. Wrapped because changing volume
  /// before the first frame can race media_kit's init.
  Future<void> _applyAudioRouting() async {
    final c = _controller;
    if (c == null) return;
    try {
      final shouldHearMe = widget.isActive && !widget.masterMuted;
      await c.setVolume(shouldHearMe ? 100 : 0);
    } on Object catch (e) {
      // Best-effort; never bubble engine volume errors to the UI.
      debugPrint('[multi_stream_tile] volume failed: $e');
    }
  }

  @override
  void didUpdateWidget(MultiStreamTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.masterMuted != widget.masterMuted) {
      _applyAudioRouting();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _stateSub = null;
    final c = _controller;
    _controller = null;
    if (c != null) {
      // Detach asynchronously so we don't block the widget tree pump.
      unawaited(_safeDispose(c));
    }
    super.dispose();
  }

  Future<void> _safeDispose(AwaPlayerController c) async {
    try {
      await c.stop();
    } on Object {
      // ignore
    }
    try {
      await c.dispose();
    } on Object {
      // ignore — engine may already be torn down
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = widget.isActive;
    final borderColor =
        isActive ? scheme.primary : scheme.outline.withValues(alpha: 0.18);
    final glow = isActive
        ? <BoxShadow>[
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.55),
              blurRadius: 16,
            ),
          ]
        : const <BoxShadow>[];

    return AnimatedContainer(
      duration: DesignTokens.motionFast,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(color: borderColor, width: isActive ? 3 : 1),
        boxShadow: glow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Video frame — controller may still be null for the first
            // few frames; show the channel logo as a placeholder so the
            // tile never blinks black.
            if (_controller != null)
              AwaPlayerView(
                controller: _controller!,
                fit: BoxFit.cover,
              )
            else
              _LogoPlaceholder(channel: widget.slot.channel),
            if (_errorMessage != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.78),
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spaceM),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(height: DesignTokens.spaceXs),
                          const Text(
                            'Yayin acilamadi',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: DesignTokens.spaceXs),
                          Text(
                            _errorMessage!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Top-left chip with the channel name. Always visible so the
            // user always knows which tile is which when they're hopping
            // between four streams.
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: _TileNameChip(
                name: widget.slot.channel.name,
                active: isActive,
                muted: !isActive || widget.masterMuted,
              ),
            ),
            // Bottom-right "remove" affordance — only visible on the
            // active tile so the user has to tap a tile first before
            // they can accidentally close it.
            if (isActive)
              Positioned(
                bottom: 6,
                right: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => ref
                        .read(multiStreamSessionProvider.notifier)
                        .removeSlot(widget.index),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            // Hit target — tap to make active, long-press for menu.
            // Last in the stack so it captures gestures before child
            // widgets (the AwaPlayerView is already pointer-transparent).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(multiStreamSessionProvider.notifier)
                    .setActive(widget.index),
                onLongPress: () => _showTileMenu(context),
              ),
            ),
            // Boot spinner only while no frame has landed yet — keeps
            // the tile responsive instead of looking frozen.
            if (_booting && !_firstFrameSeen && _errorMessage == null)
              const Positioned(
                bottom: 8,
                left: 8,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTileMenu(BuildContext context) async {
    final notifier = ref.read(multiStreamSessionProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.volume_up_rounded),
                title: const Text('Sesini ac'),
                subtitle: const Text(
                  'Bu kanali aktif yap, digerlerini sustur.',
                ),
                onTap: () {
                  notifier.setActive(widget.index);
                  Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Kanali cikar'),
                onTap: () {
                  notifier.removeSlot(widget.index);
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          ),
        );
      },
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = channel.logoUrl;
    final fallbackLetter =
        channel.name.isEmpty ? '?' : channel.name.characters.first;
    if (url == null || url.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              scheme.primary.withValues(alpha: 0.35),
              scheme.secondary.withValues(alpha: 0.18),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          fallbackLetter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        fadeInDuration: DesignTokens.motionFast,
        errorWidget: (_, __, ___) => Center(
          child: Text(
            fallbackLetter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _TileNameChip extends StatelessWidget {
  const _TileNameChip({
    required this.name,
    required this.active,
    required this.muted,
  });

  final String name;
  final bool active;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: active
              ? theme.colorScheme.primary
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 14,
            color: muted
                ? Colors.white.withValues(alpha: 0.55)
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
