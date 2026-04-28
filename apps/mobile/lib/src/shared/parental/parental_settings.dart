import 'package:flutter/material.dart';

/// Persisted parental-control configuration for one device.
///
/// Settings are global (not per-profile) because the lock applies to
/// every kids profile uniformly — a parent doesn't want different rules
/// on every child's tile. Per-profile escalation is covered by the
/// `UserProfile.requiresPin` flag.
@immutable
class ParentalSettings {
  const ParentalSettings({
    this.enabled = false,
    this.pinHash,
    this.pinSalt,
    this.maxRating = ParentalRating.allAges,
    this.blockedCategories = const <String>[],
    this.dailyWatchLimit = Duration.zero,
    this.bedtimeHour,
    this.bedtimeMinute,
  });

  /// Master switch. When `false` no gates apply, regardless of the
  /// other fields.
  final bool enabled;

  /// SHA-256 hex digest of the parental PIN.
  final String? pinHash;
  final String? pinSalt;

  /// One of [ParentalRating]. Stored as a small int code so the value
  /// survives JSON round-trips without an extra enum-name table.
  final int maxRating;

  /// User-specified list of category names (lower-cased) to hide from
  /// kids profiles.
  final List<String> blockedCategories;

  /// Cumulative watch time allowed per UTC day for kids profiles.
  /// `Duration.zero` means "no limit". Tracked elsewhere via the
  /// [parentalUsageTrackerProvider].
  final Duration dailyWatchLimit;

  /// Bedtime hour (0-23). When set, the player blocks new playback for
  /// kids profiles after this hour and before 6 AM.
  final int? bedtimeHour;
  final int? bedtimeMinute;

  TimeOfDay? get bedtimeOfDay {
    if (bedtimeHour == null) return null;
    return TimeOfDay(hour: bedtimeHour!, minute: bedtimeMinute ?? 0);
  }

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  ParentalSettings copyWith({
    bool? enabled,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    int? maxRating,
    List<String>? blockedCategories,
    Duration? dailyWatchLimit,
    int? bedtimeHour,
    int? bedtimeMinute,
    bool clearBedtime = false,
  }) {
    return ParentalSettings(
      enabled: enabled ?? this.enabled,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      maxRating: maxRating ?? this.maxRating,
      blockedCategories: blockedCategories ?? this.blockedCategories,
      dailyWatchLimit: dailyWatchLimit ?? this.dailyWatchLimit,
      bedtimeHour:
          clearBedtime ? null : (bedtimeHour ?? this.bedtimeHour),
      bedtimeMinute:
          clearBedtime ? null : (bedtimeMinute ?? this.bedtimeMinute),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'maxRating': maxRating,
        'blockedCategories': blockedCategories,
        'dailyWatchLimitSeconds': dailyWatchLimit.inSeconds,
        'bedtimeHour': bedtimeHour,
        'bedtimeMinute': bedtimeMinute,
      };

  factory ParentalSettings.fromJson(Map<String, dynamic> json) {
    final cats = json['blockedCategories'];
    final list = cats is List
        ? cats.whereType<String>().toList(growable: false)
        : const <String>[];
    final secs = json['dailyWatchLimitSeconds'];
    final dailyLimit = secs is num
        ? Duration(seconds: secs.toInt())
        : Duration.zero;
    return ParentalSettings(
      enabled: json['enabled'] as bool? ?? false,
      pinHash: json['pinHash'] as String?,
      pinSalt: json['pinSalt'] as String?,
      maxRating: (json['maxRating'] as num?)?.toInt() ?? ParentalRating.allAges,
      blockedCategories: list,
      dailyWatchLimit: dailyLimit,
      bedtimeHour: (json['bedtimeHour'] as num?)?.toInt(),
      bedtimeMinute: (json['bedtimeMinute'] as num?)?.toInt(),
    );
  }
}

/// Numeric rating bands aligned with the TMDB "certification" buckets
/// most IPTV providers ship. Stored as ints for stable JSON.
class ParentalRating {
  const ParentalRating._();

  static const int allAges = 0;
  static const int sevenPlus = 7;
  static const int thirteenPlus = 13;
  static const int sixteenPlus = 16;
  static const int eighteenPlus = 18;

  static const List<int> all = <int>[
    allAges,
    sevenPlus,
    thirteenPlus,
    sixteenPlus,
    eighteenPlus,
  ];

  static String label(int rating) {
    switch (rating) {
      case allAges:
        return 'Genel izleyici';
      case sevenPlus:
        return '7+';
      case thirteenPlus:
        return '13+';
      case sixteenPlus:
        return '16+';
      case eighteenPlus:
        return '18+';
      default:
        return '$rating+';
    }
  }

  /// Heuristic guess of a content's age band given its TMDB rating
  /// (0-10) and an optional MPAA-style certification string. Used by
  /// the parental gate when providers expose richer metadata; falls
  /// back to "all ages" when no signal is present.
  static int inferFromTmdb({double? voteRating, String? certification}) {
    final cert = certification?.toUpperCase().trim();
    if (cert != null && cert.isNotEmpty) {
      // Match the most common North-American MPAA certs — covers the
      // bulk of what TMDB returns for English-language films.
      if (cert.contains('NC-17') || cert == 'R' || cert == 'TV-MA') {
        return eighteenPlus;
      }
      if (cert.contains('PG-13') || cert == 'TV-14') return thirteenPlus;
      if (cert == 'PG' || cert == 'TV-PG') return sevenPlus;
      if (cert == 'G' || cert == 'TV-Y' || cert == 'TV-G') return allAges;
    }
    // Fall back to the vote rating proxy (which is technically a quality
    // metric, not an age rating) — but at the high-rating end TMDB
    // adult / horror titles cluster, so blocking 8+ keeps kids on
    // family stuff. Tunable.
    if (voteRating != null && voteRating >= 8.5) return sixteenPlus;
    return allAges;
  }
}
