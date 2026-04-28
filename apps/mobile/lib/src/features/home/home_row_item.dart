import 'package:awatv_core/awatv_core.dart';
import 'package:flutter/foundation.dart';

/// One row item shown in any of the home rows.
///
/// Sealed so the rendering layer can pattern-match instead of relying on
/// nullable accessors. Each variant carries enough information to render
/// a `PosterCard` (poster, title, optional year/rating) and to navigate
/// the user to the right detail screen on tap.
@immutable
sealed class HomeRowItem {
  const HomeRowItem();

  /// Stable id — used as the Hero tag and for list keys.
  String get id;

  /// User-facing title.
  String get title;

  /// 2:3 poster URL (TMDB or provider-supplied). May be `null` — the
  /// poster card falls back to a gradient placeholder.
  String? get posterUrl;

  /// 16:9 backdrop URL — used by the hero carousel. Often `null` for
  /// channels and provider-only metadata.
  String? get backdropUrl;

  /// Release year (if known).
  int? get year;

  /// 0-10 rating (if known).
  double? get rating;

  /// Short plot / overview shown in the hero carousel scrim.
  String? get plot;

  /// Optional resume progress (0..1). Non-null only on movie / series /
  /// channel variants when there is a corresponding `HistoryEntry`.
  double? get progress;

  /// Route the user lands on when tapping this card.
  String get detailRoute;
}

/// Movie poster.
class MovieRowItem extends HomeRowItem {
  const MovieRowItem({
    required this.vod,
    this.progress,
  });

  final VodItem vod;

  @override
  final double? progress;

  @override
  String get id => vod.id;

  @override
  String get title => vod.title;

  @override
  String? get posterUrl => vod.posterUrl;

  @override
  String? get backdropUrl => vod.backdropUrl;

  @override
  int? get year => vod.year;

  @override
  double? get rating => vod.rating;

  @override
  String? get plot => vod.plot;

  @override
  String get detailRoute => '/movie/${vod.id}';
}

/// Series poster.
class SeriesRowItem extends HomeRowItem {
  const SeriesRowItem({
    required this.series,
    this.progress,
  });

  final SeriesItem series;

  @override
  final double? progress;

  @override
  String get id => series.id;

  @override
  String get title => series.title;

  @override
  String? get posterUrl => series.posterUrl;

  @override
  String? get backdropUrl => series.backdropUrl;

  @override
  int? get year => series.year;

  @override
  double? get rating => series.rating;

  @override
  String? get plot => series.plot;

  @override
  String get detailRoute => '/series/${series.id}';
}

/// Live channel — typically used in the "Trending now" row.
class ChannelRowItem extends HomeRowItem {
  const ChannelRowItem({
    required this.channel,
    this.currentProgramme,
    this.progress,
  });

  final Channel channel;

  /// EPG programme currently airing (if any). Drives the subtitle.
  final EpgProgramme? currentProgramme;

  @override
  final double? progress;

  @override
  String get id => channel.id;

  @override
  String get title => channel.name;

  @override
  String? get posterUrl => channel.logoUrl;

  @override
  String? get backdropUrl => null;

  @override
  int? get year => null;

  @override
  double? get rating => null;

  @override
  String? get plot => currentProgramme?.title;

  @override
  String get detailRoute => '/channel/${channel.id}';
}

/// External "Editor's Picks" — sourced directly from TMDB discover API
/// when the user is premium and a TMDB key is configured. Carries no
/// playable url — tapping should open a search dialog or fall back to
/// the matching VOD/series item the user already has.
class EditorsPickItem extends HomeRowItem {
  const EditorsPickItem({
    required this.tmdbId,
    required this.kind,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.plot,
  });

  final int tmdbId;

  /// movie or series.
  final MediaType kind;

  @override
  final String title;

  @override
  final String? posterUrl;

  @override
  final String? backdropUrl;

  @override
  final int? year;

  @override
  final double? rating;

  @override
  final String? plot;

  @override
  double? get progress => null;

  @override
  String get id => 'tmdb:${kind.name}:$tmdbId';

  @override
  String get detailRoute =>
      kind == MediaType.movie ? '/movie/tmdb-$tmdbId' : '/series/tmdb-$tmdbId';
}
