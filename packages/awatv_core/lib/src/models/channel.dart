import 'package:freezed_annotation/freezed_annotation.dart';

part 'channel.freezed.dart';
part 'channel.g.dart';

/// What kind of stream a channel points to.
enum ChannelKind {
  /// Live linear TV.
  live,

  /// On-demand movie.
  vod,

  /// Series episode placeholder (for TV-style listings of series).
  series,
}

/// A single playable item.
///
/// Stable id formula: `"${sourceId}::${tvgId ?? streamId ?? name}"`.
@freezed
class Channel with _$Channel {
  const factory Channel({
    required String id,
    required String sourceId,
    required String name,
    required String streamUrl,
    required ChannelKind kind,
    @Default(<String>[]) List<String> groups,
    String? tvgId,
    String? logoUrl,
    int? tmdbId,
    @Default(<String, String>{}) Map<String, String> extras,
  }) = _Channel;

  factory Channel.fromJson(Map<String, dynamic> json) =>
      _$ChannelFromJson(json);

  /// Compute the canonical id from its parts.
  static String buildId({
    required String sourceId,
    String? tvgId,
    String? streamId,
    required String name,
  }) {
    final tail = (tvgId != null && tvgId.isNotEmpty)
        ? tvgId
        : (streamId != null && streamId.isNotEmpty)
            ? streamId
            : name;
    return '$sourceId::$tail';
  }
}
