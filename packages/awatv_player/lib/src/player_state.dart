/// Unified player state surface emitted by [AwaPlayerController.states].
///
/// Modelled as a Dart 3 sealed hierarchy so callers can switch exhaustively.
sealed class PlayerState {
  const PlayerState();
}

/// No media is loaded; the player is constructed but idle.
final class PlayerIdle extends PlayerState {
  const PlayerIdle();
}

/// A source has been opened and is buffering / preparing the first frame.
final class PlayerLoading extends PlayerState {
  const PlayerLoading();
}

/// Media is currently playing.
///
/// [total] is `null` for live streams (libmpv reports a zero/unknown
/// duration), which is the canonical signal that no seek bar should be
/// rendered for the source.
final class PlayerPlaying extends PlayerState {
  const PlayerPlaying({
    required this.position,
    required this.buffered,
    this.total,
  });

  final Duration position;
  final Duration buffered;
  final Duration? total;
}

/// Media is paused but loaded.
final class PlayerPaused extends PlayerState {
  const PlayerPaused({required this.position, this.total});

  final Duration position;
  final Duration? total;
}

/// VOD playback reached end-of-file.
final class PlayerEnded extends PlayerState {
  const PlayerEnded();
}

/// An unrecoverable error was reported by the underlying engine.
final class PlayerError extends PlayerState {
  const PlayerError(this.message, {this.cause});

  final String message;
  final Object? cause;
}
