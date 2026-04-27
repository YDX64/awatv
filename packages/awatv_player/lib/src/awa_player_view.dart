import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'awa_player_controller.dart';

/// Renders the video frame for an [AwaPlayerController].
///
/// This widget is intentionally controls-free: the host app draws its
/// own overlay (play/pause, seek bar, EPG strip, casting button, ...)
/// and binds them to the controller's streams and methods. That keeps
/// the player package shell-agnostic and makes the same controller
/// reusable on phone, tablet, TV, and desktop without dragging Material
/// chrome along.
class AwaPlayerView extends StatelessWidget {
  const AwaPlayerView({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.backgroundColor = Colors.black,
  });

  final AwaPlayerController controller;

  /// How the video frame is fitted into the available box.
  /// Use [BoxFit.contain] for letterboxed (default), [BoxFit.cover] for
  /// edge-to-edge with cropping.
  final BoxFit fit;

  /// Letterbox/pillarbox colour shown around the video frame.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Video(
        controller: controller.videoController,
        fit: fit,
        fill: backgroundColor,
        // Disable built-in controls; the host app provides its own UI.
        // Spelled out as a builder to dodge a typing-quirk where the bare
        // `NoVideoControls` constant resolves to dynamic in some lints.
        controls: (VideoState state) => const SizedBox.shrink(),
        // Keep the screen awake during playback, mirroring native player
        // behaviour. Cheap to leave on; libmpv handles the platform call.
        wakelock: true,
        // Auto-pause on background, auto-resume is the host app's call
        // (some flows want PiP-like continuation).
        pauseUponEnteringBackgroundMode: true,
        resumeUponEnteringForegroundMode: false,
      ),
    );
  }
}
