import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Full-screen YouTube trailer player.
///
/// Backed by `youtube_player_flutter` (which embeds the official YT
/// IFrame on iOS / Android / web; on macOS / Windows / Linux the
/// package falls back to the system webview). The chrome we paint on
/// top is intentionally minimal: a close button, a mute toggle, and a
/// gentle scrim so the user doesn't lose the action affordances on
/// bright trailer footage.
///
/// We deliberately hide the player's own playback controls (skip,
/// quality menu, fullscreen) because the entire route IS already
/// fullscreen and skipping makes no sense for a 90-second trailer.
class TrailerScreen extends StatefulWidget {
  const TrailerScreen({required this.youtubeId, super.key, this.title});

  final String youtubeId;
  final String? title;

  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends State<TrailerScreen> {
  late YoutubePlayerController _controller;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _controller = YoutubePlayerController(
      initialVideoId: widget.youtubeId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        // Strict embed prevents related-video chrome from leaking onto
        // the screen at the end of the trailer.
        useHybridComposition: true,
        forceHD: false,
        enableCaption: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) {
      _controller.mute();
    } else {
      _controller.unMute();
    }
  }

  void _onClose() {
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Theme.of(context).colorScheme.primary,
        // Suppress the package's own top + bottom action rows; we paint
        // our own minimal chrome.
        bottomActions: const <Widget>[],
        topActions: const <Widget>[],
      ),
      builder: (BuildContext ctx, Widget player) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(child: AspectRatio(aspectRatio: 16 / 9, child: player)),
              const _Scrim(),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spaceXs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ChromeButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Kapat',
                        onTap: _onClose,
                      ),
                      const Spacer(),
                      if (widget.title != null && widget.title!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spaceM,
                          ),
                          child: Text(
                            widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      const Spacer(),
                      _ChromeButton(
                        icon: _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        tooltip: _muted ? 'Sesi ac' : 'Sesi kapat',
                        onTap: _toggleMute,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x99000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0x66000000),
            ],
            stops: <double>[0, 0.18, 0.82, 1],
          ),
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
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
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
