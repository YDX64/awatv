import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What is currently playing — surfaced by the persistent player bar.
///
/// This is a *display-only* mirror of the actual player state. The player
/// screen writes to it as it loads / pauses / resumes a stream so the
/// shell can paint a mini player without taking a dependency on
/// `package:awatv_player` (… well, almost — see [source] below).
///
/// When nothing is playing — i.e. the user has never opened the player
/// or has explicitly stopped — `state` is null and the bar hides.
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.kind,
    this.subtitle,
    this.thumbnailUrl,
    this.itemId,
    this.isLive = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.source,
  });

  /// Foreground title — channel name / movie title / episode title.
  final String title;

  /// What kind of media is playing — drives the icon + the route the
  /// "expand" button pushes.
  final HistoryKind kind;

  /// Smaller line under the title (channel group / season+episode / year).
  final String? subtitle;

  /// Logo or poster URL — square 40×40 tile in the bar. May be null.
  final String? thumbnailUrl;

  /// Underlying item id — used to deep-link the expand button to the
  /// detail screen, and the prev/next buttons can use this to find the
  /// neighbouring item in its catalog.
  final String? itemId;

  /// Live streams hide the seek bar and show a striped progress instead.
  final bool isLive;

  /// Current position. Always `Duration.zero` for live.
  final Duration position;

  /// Total duration. Always `Duration.zero` for live.
  final Duration duration;

  /// True while the player is actively pulling frames — UI swaps the
  /// pause icon for a play icon when false.
  final bool isPlaying;

  /// The currently-loaded [MediaSource]. The persistent bar hands this
  /// off to the cast engine when the user picks a device, so the receiver
  /// gets the *exact* URL/headers/UA the local engine is using rather than
  /// a guess. Null while the bar is mirroring a stub state (e.g. before
  /// the controller has loaded its first source).
  ///
  /// Note: importing `awatv_player` here is intentional — `MediaSource`
  /// is a pure value type with no platform dependencies, so widgets that
  /// only consume the bar's display state still don't pull in libmpv.
  final MediaSource? source;

  /// Convenience: progress in [0..1] for the slim filled bar. Zero for
  /// live; clamped for VOD even when the duration sneaks past total.
  double get progress {
    if (isLive) return 0;
    final t = duration.inMilliseconds;
    if (t <= 0) return 0;
    return (position.inMilliseconds / t).clamp(0, 1).toDouble();
  }

  NowPlaying copyWith({
    String? title,
    HistoryKind? kind,
    String? subtitle,
    String? thumbnailUrl,
    String? itemId,
    bool? isLive,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    MediaSource? source,
  }) {
    return NowPlaying(
      title: title ?? this.title,
      kind: kind ?? this.kind,
      subtitle: subtitle ?? this.subtitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      itemId: itemId ?? this.itemId,
      isLive: isLive ?? this.isLive,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      source: source ?? this.source,
    );
  }
}

/// Display state for the persistent player bar. Null hides the bar.
class NowPlayingNotifier extends Notifier<NowPlaying?> {
  @override
  NowPlaying? build() => null;

  /// Player feature calls this when a new media starts loading so the
  /// shell can paint the bar immediately (with isPlaying=false until the
  /// first frame lands).
  void start(NowPlaying value) {
    state = value;
  }

  /// Mid-playback ping — typically invoked from the player feature on a
  /// position-throttled timer. No-op when [state] is null.
  void update({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    String? title,
    String? subtitle,
    String? thumbnailUrl,
    MediaSource? source,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      title: title,
      subtitle: subtitle,
      thumbnailUrl: thumbnailUrl,
      source: source,
    );
  }

  /// Manual pause/resume from the bar — toggles the `isPlaying` mirror so
  /// the icon flips immediately. The actual player package observes this
  /// flag (when wired) and reacts. We keep the mirror authoritative for
  /// the UI so the bar stays responsive even if the player is busy.
  void togglePlay() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(isPlaying: !current.isPlaying);
  }

  /// Player closed / stream ended — bar hides on next frame.
  void clear() {
    state = null;
  }
}

final nowPlayingProvider = NotifierProvider<NowPlayingNotifier, NowPlaying?>(
  NowPlayingNotifier.new,
);
