import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// Claims the OS audio session for AWAtv.
///
/// The configuration matches the typical media-player profile used by
/// Netflix / VLC / IPTV Expert: long-form `playback` category, ducks
/// other apps' audio while a stream is active, and lets the engine keep
/// running while the app is backgrounded so the lock-screen tile stays
/// useful.
///
/// Web has no audio-session API — we early-out to avoid the dart:io
/// dependency the package pulls in transitively. Failures elsewhere are
/// non-fatal: the player still works without a registered session, the
/// user just loses the "duck other apps" / lock-screen-controls UX.
Future<void> configureAudioSession() async {
  if (kIsWeb) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        // iOS: `playback` is the only category that keeps audio alive
        // while the screen is locked / the app is in the background.
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        // Quietly drops other apps' audio (Spotify, Podcasts) while a
        // stream is active so the user doesn't hear two soundtracks.
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        // When we go inactive, signal other apps so they can resume —
        // exactly what the system Music app does on its way out.
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          flags: AndroidAudioFlags.audibilityEnforced,
          usage: AndroidAudioUsage.media,
        ),
        // While another app holds focus and ducks us, pause hard rather
        // than fade-down — IPTV streams don't have a server-side mixer
        // and a half-volume rendition sounds broken to most users.
        androidWillPauseWhenDucked: true,
      ),
    );
  } on Object catch (e) {
    if (kDebugMode) {
      debugPrint('configureAudioSession failed: $e');
    }
  }
}
