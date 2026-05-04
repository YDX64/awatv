/// TMDB `/movie/{id}/credits` and `/tv/{id}/credits` response shape.
///
/// Plain Dart (no `freezed` / `json_serializable`) so the package can be
/// rebuilt without a build_runner pass. The same JSON shape round-trips
/// through `AwatvStorage.putMetadataJson` for the 24-hour cache used by
/// `MetadataService.credits`.
class TmdbCastMember {
  const TmdbCastMember({
    required this.id,
    required this.name,
    required this.character,
    this.profilePath,
    this.order,
  });

  factory TmdbCastMember.fromJson(Map<String, dynamic> json) {
    final rawProfile = (json['profile_path'] as String?)?.trim();
    return TmdbCastMember(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?)?.trim() ?? '',
      character: (json['character'] as String?)?.trim() ?? '',
      profilePath:
          (rawProfile == null || rawProfile.isEmpty) ? null : rawProfile,
      order: (json['order'] as num?)?.toInt(),
    );
  }

  /// TMDB person id. Used as the route param for the cast detail stub
  /// (`/cast/{id}`) and as the dedupe key when merging cast lists.
  final int id;
  final String name;

  /// The character / role the actor plays in this title. Empty string when
  /// TMDB returns a missing or null `character` field.
  final String character;

  /// `profile_path` as returned by TMDB. Caller composes the full URL via
  /// `https://image.tmdb.org/t/p/w185{profilePath}` — kept partial here so
  /// the cache survives an `imageBase` change.
  final String? profilePath;

  /// Cast list ordering as returned by TMDB. Used to keep the top-billed
  /// actors first after JSON round-trips.
  final int? order;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'character': character,
        if (profilePath != null) 'profile_path': profilePath,
        if (order != null) 'order': order,
      };
}

/// TMDB credits crew member (director, writer, …).
class TmdbCrewMember {
  const TmdbCrewMember({
    required this.id,
    required this.name,
    required this.job,
    required this.department,
    this.profilePath,
  });

  factory TmdbCrewMember.fromJson(Map<String, dynamic> json) {
    final rawProfile = (json['profile_path'] as String?)?.trim();
    return TmdbCrewMember(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?)?.trim() ?? '',
      job: (json['job'] as String?)?.trim() ?? '',
      department: (json['department'] as String?)?.trim() ?? '',
      profilePath:
          (rawProfile == null || rawProfile.isEmpty) ? null : rawProfile,
    );
  }

  final int id;
  final String name;

  /// e.g. `Director`, `Writer`, `Screenplay`, `Producer`.
  final String job;

  /// e.g. `Directing`, `Writing`, `Production`.
  final String department;

  final String? profilePath;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'job': job,
        'department': department,
        if (profilePath != null) 'profile_path': profilePath,
      };
}

/// Bundle returned by `MetadataService.credits` — 8 cast + 4 crew.
///
/// Cast members are ordered by their TMDB `order` index (top-billed first).
/// Crew is filtered to the most relevant jobs: `Director`, `Writer`,
/// `Screenplay`, `Story`, `Producer`.
class TmdbCredits {
  const TmdbCredits({
    required this.cast,
    required this.crew,
  });

  factory TmdbCredits.fromJson(Map<String, dynamic> json) {
    final castRaw = json['cast'];
    final crewRaw = json['crew'];
    final cast = <TmdbCastMember>[];
    if (castRaw is List) {
      for (final e in castRaw) {
        if (e is Map) {
          cast.add(TmdbCastMember.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    final crew = <TmdbCrewMember>[];
    if (crewRaw is List) {
      for (final e in crewRaw) {
        if (e is Map) {
          crew.add(TmdbCrewMember.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return TmdbCredits(cast: cast, crew: crew);
  }

  /// Empty bundle. Returned when:
  /// - `Env.tmdbApiKey` is not configured
  /// - the lookup target has no `tmdbId`
  /// - TMDB responds with an empty `cast` + `crew`
  static const TmdbCredits empty = TmdbCredits(
    cast: <TmdbCastMember>[],
    crew: <TmdbCrewMember>[],
  );

  final List<TmdbCastMember> cast;
  final List<TmdbCrewMember> crew;

  bool get isEmpty => cast.isEmpty && crew.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// First credited director, if any. Convenience for headline display.
  TmdbCrewMember? get director {
    for (final c in crew) {
      if (c.job.toLowerCase() == 'director') return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cast': cast.map((c) => c.toJson()).toList(),
        'crew': crew.map((c) => c.toJson()).toList(),
      };
}
