import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_source.freezed.dart';
part 'playlist_source.g.dart';

/// Kind of upstream playlist provider.
enum PlaylistKind {
  /// Plain M3U / M3U8 URL.
  m3u,

  /// Xtream Codes panel (server + username + password).
  xtream,
}

/// A user-added playlist source.
///
/// Stable identity is the [id] (UUID v4 generated when the user adds it).
/// Credentials are persisted only via secure storage on the app side; this
/// model carries them for in-memory work.
@freezed
class PlaylistSource with _$PlaylistSource {
  const factory PlaylistSource({
    required String id,
    required String name,
    required PlaylistKind kind,
    required String url,
    required DateTime addedAt,
    String? username,
    String? password,
    String? epgUrl,
    DateTime? lastSyncAt,
  }) = _PlaylistSource;

  factory PlaylistSource.fromJson(Map<String, dynamic> json) =>
      _$PlaylistSourceFromJson(json);
}
