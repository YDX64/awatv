import 'package:meta/meta.dart';

/// One archived programme entry returned by Xtream
/// `action=get_simple_data_table`.
///
/// Mirrors what XMLTV would call a programme but adds the [hasArchive]
/// flag so the UI knows whether the panel actually retains the
/// recording. Rows with `hasArchive == false` are kept in the result
/// for context (so the user sees the full schedule and can spot which
/// past programmes the panel chose not to keep).
@immutable
class CatchupProgramme {
  const CatchupProgramme({
    required this.streamId,
    required this.title,
    required this.start,
    required this.stop,
    required this.hasArchive,
    this.epgId,
    this.description,
    this.nowPlaying = false,
  });

  /// The Xtream live `stream_id` this programme aired on.
  final int streamId;

  /// Optional EPG event id from the panel (string in some forks).
  final String? epgId;

  /// Programme title (already base64-decoded by the caller).
  final String title;

  /// Optional long description (base64-decoded).
  final String? description;

  /// Programme start in UTC.
  final DateTime start;

  /// Programme stop in UTC.
  final DateTime stop;

  /// Set when the programme is currently airing.
  final bool nowPlaying;

  /// Set when the panel keeps a recording of this programme. Rows with
  /// [hasArchive] == false should be greyed out / non-tappable in the UI.
  final bool hasArchive;

  /// Programme duration. Convenience around `stop.difference(start)`.
  Duration get duration => stop.difference(start);

  /// True when the programme stop is in the past (relative to [now]).
  bool isPast(DateTime now) => stop.isBefore(now);

  /// True when the programme has not started yet (relative to [now]).
  bool isFuture(DateTime now) => start.isAfter(now);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CatchupProgramme &&
        other.streamId == streamId &&
        other.epgId == epgId &&
        other.title == title &&
        other.start == start &&
        other.stop == stop &&
        other.hasArchive == hasArchive;
  }

  @override
  int get hashCode =>
      Object.hash(streamId, epgId, title, start, stop, hasArchive);

  @override
  String toString() =>
      'CatchupProgramme($streamId, $title, $start–$stop, archive=$hasArchive)';
}
