import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One of the 8 sort orders surfaced by the grid app-bars.
///
/// Live channels only support 4 of these (added asc/desc, alpha asc/desc)
/// because `Channel` carries no `rating` or `year` fields. The UI gates
/// the unsupported entries via [SortMode.appliesToLive].
enum SortMode {
  /// Newest items first (default for VOD/series — based on `extras['added']`
  /// for live, fall back to load order).
  addedDesc,

  /// Oldest items first.
  addedAsc,

  /// A → Z by title / channel name.
  alphaAsc,

  /// Z → A by title / channel name.
  alphaDesc,

  /// Newest by release year first (VOD/series only).
  releaseDesc,

  /// Oldest by release year first.
  releaseAsc,

  /// Highest TMDB / panel rating first.
  ratingDesc,

  /// Lowest rating first.
  ratingAsc;

  /// Turkish UI label.
  String get label {
    switch (this) {
      case SortMode.addedDesc:
        return 'Eklenme: yeniden eskiye';
      case SortMode.addedAsc:
        return 'Eklenme: eskiden yeniye';
      case SortMode.alphaAsc:
        return 'Alfabetik: A-Z';
      case SortMode.alphaDesc:
        return 'Alfabetik: Z-A';
      case SortMode.releaseDesc:
        return 'Cikis yili: yeniden eskiye';
      case SortMode.releaseAsc:
        return 'Cikis yili: eskiden yeniye';
      case SortMode.ratingDesc:
        return 'Puan: yuksek-dusuk';
      case SortMode.ratingAsc:
        return 'Puan: dusuk-yuksek';
    }
  }

  /// True for the 4 modes that make sense on `Channel` (no rating/year).
  bool get appliesToLive {
    switch (this) {
      case SortMode.addedDesc:
      case SortMode.addedAsc:
      case SortMode.alphaAsc:
      case SortMode.alphaDesc:
        return true;
      case SortMode.releaseDesc:
      case SortMode.releaseAsc:
      case SortMode.ratingDesc:
      case SortMode.ratingAsc:
        return false;
    }
  }
}

/// Surface key for the sort-mode family. We persist + filter per-screen
/// so live, VOD and series can each have their own preferred mode.
enum SortSurface {
  live,
  vod,
  series;

  String get prefsKey => 'prefs:sort.$name';
}

/// Reads / writes the user's sort preference for a given `SortSurface`.
///
/// Default: `SortMode.addedDesc` for VOD/series, `SortMode.alphaAsc` for
/// live (channels are usually browsed alphabetically; provider "added"
/// timestamps are unreliable).
class SortModeNotifier extends FamilyNotifier<SortMode, SortSurface> {
  @override
  SortMode build(SortSurface arg) {
    final storage = ref.watch(awatvStorageProvider);
    try {
      final raw = storage.prefsBox.get(arg.prefsKey);
      if (raw is String) {
        for (final m in SortMode.values) {
          if (m.name == raw) return m;
        }
      }
    } on Object {
      // Storage might not be initialised in tests — fall through.
    }
    return arg == SortSurface.live ? SortMode.alphaAsc : SortMode.addedDesc;
  }

  Future<void> set(SortMode mode) async {
    state = mode;
    try {
      final storage = ref.read(awatvStorageProvider);
      await storage.prefsBox.put(arg.prefsKey, mode.name);
    } on Object {
      // Best-effort persistence.
    }
  }
}

final sortModeProvider =
    NotifierProvider.family<SortModeNotifier, SortMode, SortSurface>(
  SortModeNotifier.new,
);

/// Sorting helpers — keep the comparators pure and side-effect-free so
/// the same logic can be unit-tested with no widget tree.
extension SortModeChannel on SortMode {
  /// Returns the channels sorted in-place by `this` mode's semantics.
  /// Falls back to alphabetical for modes that don't apply to live.
  List<Channel> sortChannels(List<Channel> input) {
    final list = List<Channel>.of(input);
    int byAlpha(Channel a, Channel b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int byAdded(Channel a, Channel b) {
      final av = int.tryParse(a.extras['added'] ?? '') ?? 0;
      final bv = int.tryParse(b.extras['added'] ?? '') ?? 0;
      if (av == bv) return byAlpha(a, b);
      return av.compareTo(bv);
    }

    switch (this) {
      case SortMode.alphaAsc:
        list.sort(byAlpha);
      case SortMode.alphaDesc:
        list.sort((a, b) => -byAlpha(a, b));
      case SortMode.addedAsc:
        list.sort(byAdded);
      case SortMode.addedDesc:
        list.sort((a, b) => -byAdded(a, b));
      case SortMode.releaseAsc:
      case SortMode.releaseDesc:
      case SortMode.ratingAsc:
      case SortMode.ratingDesc:
        // Not applicable — fall back to alphabetical to keep the grid
        // deterministic even if the user somehow picks an invalid mode.
        list.sort(byAlpha);
    }
    return list;
  }
}

extension SortModeVod on SortMode {
  List<VodItem> sortVod(List<VodItem> input) {
    final list = List<VodItem>.of(input);
    int byAlpha(VodItem a, VodItem b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int byYear(VodItem a, VodItem b) {
      final av = a.year ?? 0;
      final bv = b.year ?? 0;
      if (av == bv) return byAlpha(a, b);
      return av.compareTo(bv);
    }

    int byRating(VodItem a, VodItem b) {
      final av = a.rating ?? -1;
      final bv = b.rating ?? -1;
      if (av == bv) return byAlpha(a, b);
      return av.compareTo(bv);
    }

    // VOD has no per-item "added" timestamp on the model; substitute
    // year as the closest proxy. Falls back to alpha when year missing.
    int byAdded(VodItem a, VodItem b) => byYear(a, b);

    switch (this) {
      case SortMode.alphaAsc:
        list.sort(byAlpha);
      case SortMode.alphaDesc:
        list.sort((a, b) => -byAlpha(a, b));
      case SortMode.releaseAsc:
        list.sort(byYear);
      case SortMode.releaseDesc:
        list.sort((a, b) => -byYear(a, b));
      case SortMode.ratingAsc:
        list.sort(byRating);
      case SortMode.ratingDesc:
        list.sort((a, b) => -byRating(a, b));
      case SortMode.addedAsc:
        list.sort(byAdded);
      case SortMode.addedDesc:
        list.sort((a, b) => -byAdded(a, b));
    }
    return list;
  }
}

extension SortModeSeries on SortMode {
  List<SeriesItem> sortSeries(List<SeriesItem> input) {
    final list = List<SeriesItem>.of(input);
    int byAlpha(SeriesItem a, SeriesItem b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int byYear(SeriesItem a, SeriesItem b) {
      final av = a.year ?? 0;
      final bv = b.year ?? 0;
      if (av == bv) return byAlpha(a, b);
      return av.compareTo(bv);
    }

    int byRating(SeriesItem a, SeriesItem b) {
      final av = a.rating ?? -1;
      final bv = b.rating ?? -1;
      if (av == bv) return byAlpha(a, b);
      return av.compareTo(bv);
    }

    int byAdded(SeriesItem a, SeriesItem b) => byYear(a, b);

    switch (this) {
      case SortMode.alphaAsc:
        list.sort(byAlpha);
      case SortMode.alphaDesc:
        list.sort((a, b) => -byAlpha(a, b));
      case SortMode.releaseAsc:
        list.sort(byYear);
      case SortMode.releaseDesc:
        list.sort((a, b) => -byYear(a, b));
      case SortMode.ratingAsc:
        list.sort(byRating);
      case SortMode.ratingDesc:
        list.sort((a, b) => -byRating(a, b));
      case SortMode.addedAsc:
        list.sort(byAdded);
      case SortMode.addedDesc:
        list.sort((a, b) => -byAdded(a, b));
    }
    return list;
  }
}
