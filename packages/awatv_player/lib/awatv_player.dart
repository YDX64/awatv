/// AWAtv unified video player.
library;

// Re-export the media_kit track types so app code can program against
// `VideoTrack` / `AudioTrack` / `SubtitleTrack` without taking a direct
// dependency on the media_kit package. Both backends emit these.
export 'package:media_kit/media_kit.dart'
    show AudioTrack, SubtitleTrack, Track, Tracks, VideoTrack;

export 'src/awa_player_controller.dart';
export 'src/awa_player_view.dart';
export 'src/media_source.dart';
export 'src/player_state.dart';
