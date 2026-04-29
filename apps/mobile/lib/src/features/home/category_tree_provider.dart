import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What category-tree section is currently expanded / selected.
///
/// IPTV-Expert-class apps surface their content under a top-level
/// taxonomy of `Live / Movies / Series` and below that the per-kind
/// "groups" (live) or "genres" (VOD/series). We model both the taxonomy
/// and a single user-selected leaf right here so the home screen, the
/// tree itself and the centre grid can all read from one place.

/// The 3 root buckets of the category tree.
enum CategoryKind {
  live,
  movies,
  series;

  String get label {
    switch (this) {
      case CategoryKind.live:
        return 'Canli';
      case CategoryKind.movies:
        return 'Filmler';
      case CategoryKind.series:
        return 'Diziler';
    }
  }
}

/// One entry in the tree — either a root bucket or one of its child
/// groups. `name == null` means "all of [kind]" (i.e. the root row).
class CategoryNode {
  const CategoryNode({
    required this.kind,
    this.name,
    this.count = 0,
  });

  final CategoryKind kind;

  /// Group / genre name. Null for the root "all of kind" row.
  final String? name;

  /// How many items live under this node. Surfaced as a badge in the UI.
  final int count;

  /// Stable id we feed into selection state so the tree can mark itself
  /// active without re-doing string-equality on every rebuild.
  String get id => name == null ? '${kind.name}::*' : '${kind.name}::$name';

  bool get isRoot => name == null;

  @override
  bool operator ==(Object other) {
    if (other is! CategoryNode) return false;
    return other.kind == kind && other.name == name;
  }

  @override
  int get hashCode => Object.hash(kind, name);
}

/// Aggregated category tree built from the playlist data.
///
/// Returns one `_TreeBucket` per [CategoryKind]; each bucket carries the
/// list of group/genre nodes sorted alphabetically. Empty buckets stay in
/// the result so the UI can still show the heading with a "0" badge.
class CategoryTree {
  const CategoryTree({
    required this.live,
    required this.movies,
    required this.series,
  });

  final List<CategoryNode> live;
  final List<CategoryNode> movies;
  final List<CategoryNode> series;

  /// Flat list across all 3 kinds — handy for "default selection" logic.
  List<CategoryNode> get all => <CategoryNode>[
        ...live,
        ...movies,
        ...series,
      ];

  /// Total counts per root bucket — surfaces on the kind heading.
  int countFor(CategoryKind kind) {
    final list = _bucketFor(kind);
    var sum = 0;
    for (final n in list) {
      sum += n.count;
    }
    return sum;
  }

  List<CategoryNode> _bucketFor(CategoryKind kind) {
    switch (kind) {
      case CategoryKind.live:
        return live;
      case CategoryKind.movies:
        return movies;
      case CategoryKind.series:
        return series;
    }
  }
}

/// Builds the category tree from the merged channel / VOD / series lists.
///
/// We deliberately don't depend on the Xtream `*_categories` API here —
/// the existing providers already give us the deduped item lists, and
/// extracting groups from them works equally well for M3U + Xtream +
/// Stalker without per-source branching.
final categoryTreeProvider = FutureProvider<CategoryTree>((Ref ref) async {
  final channelsFuture = ref.watch(allChannelsProvider.future);
  final vodFuture = ref.watch(allVodProvider.future);
  final seriesFuture = ref.watch(allSeriesProvider.future);

  final channels = await channelsFuture;
  final vod = await vodFuture;
  final series = await seriesFuture;

  return CategoryTree(
    live: _buildLiveBucket(channels),
    movies: _buildVodBucket(vod),
    series: _buildSeriesBucket(series),
  );
});

List<CategoryNode> _buildLiveBucket(List<Channel> channels) {
  final liveOnly = channels.where(
    (Channel c) => c.kind == ChannelKind.live,
  );
  // Skip non-live for now — VOD-style channels are surfaced via the
  // movies bucket instead.

  final counts = <String, int>{};
  for (final c in liveOnly) {
    if (c.groups.isEmpty) {
      counts['Diger'] = (counts['Diger'] ?? 0) + 1;
      continue;
    }
    for (final g in c.groups) {
      final trimmed = g.trim();
      if (trimmed.isEmpty) continue;
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()..sort(_smartCompare);
  return <CategoryNode>[
    CategoryNode(
      kind: CategoryKind.live,
      count: liveOnly.length,
    ),
    for (final n in names)
      CategoryNode(
        kind: CategoryKind.live,
        name: n,
        count: counts[n] ?? 0,
      ),
  ];
}

List<CategoryNode> _buildVodBucket(List<VodItem> vod) {
  final counts = <String, int>{};
  for (final v in vod) {
    if (v.genres.isEmpty) {
      counts['Diger'] = (counts['Diger'] ?? 0) + 1;
      continue;
    }
    for (final g in v.genres) {
      final trimmed = g.trim();
      if (trimmed.isEmpty) continue;
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()..sort(_smartCompare);
  return <CategoryNode>[
    CategoryNode(
      kind: CategoryKind.movies,
      count: vod.length,
    ),
    for (final n in names)
      CategoryNode(
        kind: CategoryKind.movies,
        name: n,
        count: counts[n] ?? 0,
      ),
  ];
}

List<CategoryNode> _buildSeriesBucket(List<SeriesItem> series) {
  final counts = <String, int>{};
  for (final s in series) {
    if (s.genres.isEmpty) {
      counts['Diger'] = (counts['Diger'] ?? 0) + 1;
      continue;
    }
    for (final g in s.genres) {
      final trimmed = g.trim();
      if (trimmed.isEmpty) continue;
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()..sort(_smartCompare);
  return <CategoryNode>[
    CategoryNode(
      kind: CategoryKind.series,
      count: series.length,
    ),
    for (final n in names)
      CategoryNode(
        kind: CategoryKind.series,
        name: n,
        count: counts[n] ?? 0,
      ),
  ];
}

/// Smart sort: pure-numeric prefixes (e.g. "01 News", "02 Sports") first
/// in numeric order, then everything else case-insensitive.
int _smartCompare(String a, String b) {
  final aNum = _leadingInt(a);
  final bNum = _leadingInt(b);
  if (aNum != null && bNum != null && aNum != bNum) {
    return aNum.compareTo(bNum);
  }
  if (aNum != null && bNum == null) return -1;
  if (aNum == null && bNum != null) return 1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

int? _leadingInt(String s) {
  var i = 0;
  while (i < s.length && (s.codeUnitAt(i) ^ 0x30) <= 9) {
    i++;
  }
  if (i == 0) return null;
  return int.tryParse(s.substring(0, i));
}

// ---------------------------------------------------------------------------
// Selection state
// ---------------------------------------------------------------------------

/// Currently-selected node in the category tree. Drives the centre grid.
///
/// Defaults to "all live" when there is at least one live channel, then
/// falls back to "all movies" and finally "all series". Whichever bucket
/// has data first wins so a fresh user never lands on an empty grid.
class CategorySelectionController extends Notifier<CategoryNode?> {
  @override
  CategoryNode? build() {
    // Auto-select once data lands — but don't block the build either.
    final treeAsync = ref.watch(categoryTreeProvider);
    return treeAsync.when(
      data: _firstNonEmptyRoot,
      loading: () => null,
      error: (Object _, StackTrace __) => null,
    );
  }

  /// User clicked a node. Null clears selection (back to default).
  void select(CategoryNode? node) {
    state = node;
  }
}

CategoryNode? _firstNonEmptyRoot(CategoryTree tree) {
  if (tree.live.isNotEmpty && tree.live.first.count > 0) {
    return tree.live.first;
  }
  if (tree.movies.isNotEmpty && tree.movies.first.count > 0) {
    return tree.movies.first;
  }
  if (tree.series.isNotEmpty && tree.series.first.count > 0) {
    return tree.series.first;
  }
  return null;
}

final categorySelectionProvider =
    NotifierProvider<CategorySelectionController, CategoryNode?>(
  CategorySelectionController.new,
);

// ---------------------------------------------------------------------------
// Filtered content for the centre grid
// ---------------------------------------------------------------------------

/// Channels that match the current selection. Empty when the selection is
/// not in [CategoryKind.live] or when no selection is set.
final selectedLiveChannelsProvider =
    FutureProvider<List<Channel>>((Ref ref) async {
  final selection = ref.watch(categorySelectionProvider);
  if (selection == null || selection.kind != CategoryKind.live) {
    return const <Channel>[];
  }
  final all = await ref.watch(allChannelsProvider.future);
  final live = all.where((Channel c) => c.kind == ChannelKind.live);
  if (selection.isRoot) return live.toList(growable: false);

  final group = selection.name!;
  return live
      .where(
        (Channel c) =>
            c.groups.any((String g) => g.trim() == group) ||
            (c.groups.isEmpty && group == 'Diger'),
      )
      .toList(growable: false);
});

/// VOD items matching the current selection.
final selectedVodProvider = FutureProvider<List<VodItem>>((Ref ref) async {
  final selection = ref.watch(categorySelectionProvider);
  if (selection == null || selection.kind != CategoryKind.movies) {
    return const <VodItem>[];
  }
  final all = await ref.watch(allVodProvider.future);
  if (selection.isRoot) return all;

  final genre = selection.name!;
  return all
      .where(
        (VodItem v) =>
            v.genres.any((String g) => g.trim() == genre) ||
            (v.genres.isEmpty && genre == 'Diger'),
      )
      .toList(growable: false);
});

/// Series matching the current selection.
final selectedSeriesProvider =
    FutureProvider<List<SeriesItem>>((Ref ref) async {
  final selection = ref.watch(categorySelectionProvider);
  if (selection == null || selection.kind != CategoryKind.series) {
    return const <SeriesItem>[];
  }
  final all = await ref.watch(allSeriesProvider.future);
  if (selection.isRoot) return all;

  final genre = selection.name!;
  return all
      .where(
        (SeriesItem s) =>
            s.genres.any((String g) => g.trim() == genre) ||
            (s.genres.isEmpty && genre == 'Diger'),
      )
      .toList(growable: false);
});
