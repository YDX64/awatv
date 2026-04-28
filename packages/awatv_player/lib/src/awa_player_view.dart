import 'dart:io' show Platform;

import 'package:awatv_player/src/awa_player_controller.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Renders the video frame for an [AwaPlayerController].
///
/// This widget is intentionally controls-free: the host app draws its
/// own overlay (play/pause, seek bar, EPG strip, casting button, ...)
/// and binds them to the controller's streams and methods. That keeps
/// the player package shell-agnostic and makes the same controller
/// reusable on phone, tablet, TV, and desktop without dragging Material
/// chrome along.
///
/// The widget is backend-agnostic: it asks the controller to build the
/// concrete frame primitive (media_kit's `Video` for the libmpv path,
/// `VlcPlayer` for the VLC path). Lifecycle flags like wakelock and
/// auto-pause on background are gated to mobile here and forwarded down.
class AwaPlayerView extends StatelessWidget {
  const AwaPlayerView({
    required this.controller, super.key,
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
    // Wakelock + auto background pause/resume only make sense on mobile
    // platforms. On desktop, suspending decoding when the window loses
    // focus would be a regression — users explicitly want long-running
    // streams (live IPTV, films) to keep playing while they switch to
    // another app. On web we can't poke power-management APIs anyway.
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return controller.buildVideoSurface(
      fit: fit,
      backgroundColor: backgroundColor,
      wakelock: isMobile,
      pauseInBackground: isMobile,
      resumeInForeground: isMobile,
    );
  }
}
