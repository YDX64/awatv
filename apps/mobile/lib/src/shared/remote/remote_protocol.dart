/// Wire protocol for the AWAtv remote-control feature.
///
/// Two sealed hierarchies travel over a single Supabase Realtime broadcast
/// channel (`awatv:remote:<pairCode>`):
///
///   * [RemoteCommand] — sender → receiver. Things the phone tells the TV.
///   * [ReceiverState] — receiver → sender. Now-playing snapshot the phone
///     uses to render its now-playing card and reflect the live volume /
///     position even when the user is not actively touching a control.
///
/// Both are encoded as plain JSON maps so the implementation never depends
/// on `freezed` (not in pubspec) and stays trivially debuggable in the
/// Supabase dashboard's broadcast log.
library;

// =============================================================================
// Commands (sender → receiver)
// =============================================================================

/// Type discriminator embedded in every command JSON payload.
const String _kCmdTypeKey = 'type';

/// Concrete command tags. Kept as plain string constants so the JSON wire
/// format stays stable across Dart refactors.
abstract class RemoteCommandTypes {
  RemoteCommandTypes._();
  static const String playPause = 'playPause';
  static const String seekRelative = 'seekRelative';
  static const String seekAbsolute = 'seekAbsolute';
  static const String volume = 'volume';
  static const String mute = 'mute';
  static const String channelChange = 'channelChange';
  static const String openScreen = 'openScreen';
}

/// Top of the command sealed hierarchy. Subtypes encode the payload shape.
sealed class RemoteCommand {
  const RemoteCommand();

  /// Stable wire tag — never `runtimeType.toString()` because that would
  /// break the protocol the moment the class is renamed.
  String get type;

  Map<String, dynamic> toJson();

  /// Decodes any [RemoteCommand] from a Realtime broadcast payload.
  ///
  /// Unknown command types throw [FormatException] — the receiver layer
  /// catches and ignores those so newer senders can ship commands the
  /// receiver does not know about without crashing it.
  // ignore: prefer_constructors_over_static_methods — sealed root has no
  // single concrete type to construct; routing by `type` requires a
  // factory-style entrypoint.
  static RemoteCommand fromJson(Map<String, dynamic> json) {
    final type = json[_kCmdTypeKey];
    if (type is! String) {
      throw const FormatException('RemoteCommand: missing type');
    }
    return switch (type) {
      RemoteCommandTypes.playPause => const RemotePlayPauseCommand(),
      RemoteCommandTypes.seekRelative =>
        RemoteSeekRelativeCommand(seconds: (json['seconds'] as num).toInt()),
      RemoteCommandTypes.seekAbsolute => RemoteSeekAbsoluteCommand(
          position: Duration(milliseconds: (json['ms'] as num).toInt()),
        ),
      RemoteCommandTypes.volume =>
        RemoteVolumeCommand(volume: (json['volume'] as num).toDouble()),
      RemoteCommandTypes.mute => RemoteMuteCommand(muted: json['muted'] as bool),
      RemoteCommandTypes.channelChange => RemoteChannelChangeCommand(
          channelId: json['channelId'] as String,
        ),
      RemoteCommandTypes.openScreen =>
        RemoteOpenScreenCommand(route: json['route'] as String),
      _ => throw FormatException('RemoteCommand: unknown type "$type"'),
    };
  }
}

/// Toggle the receiver's playback state.
final class RemotePlayPauseCommand extends RemoteCommand {
  const RemotePlayPauseCommand();

  @override
  String get type => RemoteCommandTypes.playPause;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{_kCmdTypeKey: type};
}

/// Seek by ±[seconds] (negative for rewind).
final class RemoteSeekRelativeCommand extends RemoteCommand {
  const RemoteSeekRelativeCommand({required this.seconds});

  final int seconds;

  @override
  String get type => RemoteCommandTypes.seekRelative;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'seconds': seconds,
      };
}

/// Seek to an absolute [position] from the start of the stream.
final class RemoteSeekAbsoluteCommand extends RemoteCommand {
  const RemoteSeekAbsoluteCommand({required this.position});

  final Duration position;

  @override
  String get type => RemoteCommandTypes.seekAbsolute;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'ms': position.inMilliseconds,
      };
}

/// Set the receiver's master volume to [volume] in the 0..1 range.
final class RemoteVolumeCommand extends RemoteCommand {
  const RemoteVolumeCommand({required this.volume});

  final double volume;

  @override
  String get type => RemoteCommandTypes.volume;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'volume': volume.clamp(0.0, 1.0),
      };
}

/// Toggle whether the receiver is muted.
final class RemoteMuteCommand extends RemoteCommand {
  const RemoteMuteCommand({required this.muted});

  final bool muted;

  @override
  String get type => RemoteCommandTypes.mute;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'muted': muted,
      };
}

/// Switch the receiver to a different channel by ID. Receiver resolves the
/// ID through its own channel list — the sender does not need to know the
/// stream URL.
final class RemoteChannelChangeCommand extends RemoteCommand {
  const RemoteChannelChangeCommand({required this.channelId});

  final String channelId;

  @override
  String get type => RemoteCommandTypes.channelChange;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'channelId': channelId,
      };
}

/// Ask the receiver to navigate to [route] (a `go_router` path such as
/// `/live` or `/movies`).
final class RemoteOpenScreenCommand extends RemoteCommand {
  const RemoteOpenScreenCommand({required this.route});

  final String route;

  @override
  String get type => RemoteCommandTypes.openScreen;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        _kCmdTypeKey: type,
        'route': route,
      };
}

// =============================================================================
// State (receiver → sender)
// =============================================================================

/// What the receiver is currently doing. Mirrored by the sender so its
/// now-playing card stays accurate without the user touching anything.
enum ReceiverPlayback { idle, loading, playing, paused, ended, error }

/// Snapshot of the receiver's player. Sent on every meaningful change
/// (state transition, position tick rate-limited to ~1 Hz) and on
/// connection establishment so a freshly-connected sender hydrates its
/// UI immediately.
class ReceiverState {
  const ReceiverState({
    required this.playback,
    this.position = Duration.zero,
    this.total,
    this.volume = 1.0,
    this.muted = false,
    this.currentTitle,
    this.currentSubtitle,
    this.currentArtwork,
    this.currentChannelId,
    this.errorMessage,
  });

  /// Idle, freshly-connected default — surfaced on the sender before the
  /// receiver echoes its first meaningful state.
  static const ReceiverState empty = ReceiverState(playback: ReceiverPlayback.idle);

  final ReceiverPlayback playback;
  final Duration position;
  final Duration? total;
  final double volume;
  final bool muted;
  final String? currentTitle;
  final String? currentSubtitle;
  final String? currentArtwork;
  final String? currentChannelId;
  final String? errorMessage;

  bool get isPlaying => playback == ReceiverPlayback.playing;

  ReceiverState copyWith({
    ReceiverPlayback? playback,
    Duration? position,
    Duration? total,
    bool clearTotal = false,
    double? volume,
    bool? muted,
    String? currentTitle,
    bool clearTitle = false,
    String? currentSubtitle,
    bool clearSubtitle = false,
    String? currentArtwork,
    bool clearArtwork = false,
    String? currentChannelId,
    bool clearChannelId = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReceiverState(
      playback: playback ?? this.playback,
      position: position ?? this.position,
      total: clearTotal ? null : (total ?? this.total),
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      currentTitle: clearTitle ? null : (currentTitle ?? this.currentTitle),
      currentSubtitle:
          clearSubtitle ? null : (currentSubtitle ?? this.currentSubtitle),
      currentArtwork:
          clearArtwork ? null : (currentArtwork ?? this.currentArtwork),
      currentChannelId:
          clearChannelId ? null : (currentChannelId ?? this.currentChannelId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playback': playback.name,
        'positionMs': position.inMilliseconds,
        if (total != null) 'totalMs': total!.inMilliseconds,
        'volume': volume,
        'muted': muted,
        if (currentTitle != null) 'title': currentTitle,
        if (currentSubtitle != null) 'subtitle': currentSubtitle,
        if (currentArtwork != null) 'artwork': currentArtwork,
        if (currentChannelId != null) 'channelId': currentChannelId,
        if (errorMessage != null) 'error': errorMessage,
      };

  static ReceiverState fromJson(Map<String, dynamic> json) {
    final playbackName = json['playback'] as String? ?? 'idle';
    final playback = ReceiverPlayback.values.firstWhere(
      (ReceiverPlayback p) => p.name == playbackName,
      orElse: () => ReceiverPlayback.idle,
    );
    final totalMs = json['totalMs'];
    return ReceiverState(
      playback: playback,
      position: Duration(milliseconds: (json['positionMs'] as num? ?? 0).toInt()),
      total: totalMs is num ? Duration(milliseconds: totalMs.toInt()) : null,
      volume: (json['volume'] as num? ?? 1).toDouble(),
      muted: json['muted'] as bool? ?? false,
      currentTitle: json['title'] as String?,
      currentSubtitle: json['subtitle'] as String?,
      currentArtwork: json['artwork'] as String?,
      currentChannelId: json['channelId'] as String?,
      errorMessage: json['error'] as String?,
    );
  }
}
