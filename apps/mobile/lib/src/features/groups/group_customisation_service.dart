import 'dart:async';
import 'dart:convert';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';

/// User customisation applied on top of the auto-built [CategoryTree].
///
/// Three things the user can change:
///   * **Order** — drag-to-reorder groups inside a kind bucket.
///   * **Visibility** — hide noisy groups so they disappear from the
///     sidebar tree, the home chip row, and `GroupFilterChips`.
///   * **Display name** — rename a group (the underlying playlist
///     source is untouched; we only override the visible label).
///
/// Persisted in the shared `prefs` Hive box under three keys (one per
/// [CategoryKind]) so the IPTV-Expert-class UI feels stable across
/// sessions and EPG syncs.
class GroupCustomisationService {
  GroupCustomisationService({required AwatvStorage storage})
      : _storage = storage;

  final AwatvStorage _storage;
  final StreamController<GroupCustomisations> _ctrl =
      StreamController<GroupCustomisations>.broadcast();

  /// Hive prefs keys.
  static String aliasesKey(CategoryKind kind) =>
      'prefs:groups.aliases.${kind.name}';
  static String orderKey(CategoryKind kind) =>
      'prefs:groups.order.${kind.name}';
  static String hiddenKey(CategoryKind kind) =>
      'prefs:groups.hidden.${kind.name}';

  /// Read the merged customisation snapshot.
  GroupCustomisations read() {
    final box = _storage.prefsBox;
    return GroupCustomisations(
      aliases: <CategoryKind, Map<String, String>>{
        for (final k in CategoryKind.values)
          k: _readMap(box.get(aliasesKey(k))),
      },
      order: <CategoryKind, List<String>>{
        for (final k in CategoryKind.values)
          k: _readList(box.get(orderKey(k))),
      },
      hidden: <CategoryKind, Set<String>>{
        for (final k in CategoryKind.values)
          k: _readList(box.get(hiddenKey(k))).toSet(),
      },
    );
  }

  Stream<GroupCustomisations> watch() async* {
    yield read();
    yield* _ctrl.stream;
  }

  /// Persist the user's preferred order. Pass the canonical group
  /// names (NOT the alias-rendered labels). The default-folder-style
  /// "all of kind" root is auto-pinned to position 0 by the consumer
  /// — we only persist the leaf order here.
  Future<void> setOrder(CategoryKind kind, List<String> orderedNames) async {
    await _storage.prefsBox.put(orderKey(kind), jsonEncode(orderedNames));
    _emit();
  }

  /// Toggle visibility for a single group.
  Future<void> setHidden(
    CategoryKind kind,
    String groupName, {
    required bool value,
  }) async {
    final current = read().hidden[kind] ?? const <String>{};
    final next = Set<String>.of(current);
    if (value) {
      next.add(groupName);
    } else {
      next.remove(groupName);
    }
    await _storage.prefsBox
        .put(hiddenKey(kind), jsonEncode(next.toList()));
    _emit();
  }

  /// Set or clear a display name override. Pass empty / equal-to-name
  /// to clear.
  Future<void> setAlias(
    CategoryKind kind,
    String groupName,
    String alias,
  ) async {
    final current =
        Map<String, String>.of(read().aliases[kind] ?? const <String, String>{});
    final clean = alias.trim();
    if (clean.isEmpty || clean == groupName) {
      current.remove(groupName);
    } else {
      current[groupName] = clean;
    }
    await _storage.prefsBox
        .put(aliasesKey(kind), jsonEncode(current));
    _emit();
  }

  /// Reset every customisation for [kind].
  Future<void> resetKind(CategoryKind kind) async {
    final box = _storage.prefsBox;
    await box.delete(aliasesKey(kind));
    await box.delete(orderKey(kind));
    await box.delete(hiddenKey(kind));
    _emit();
  }

  Future<void> resetAll() async {
    for (final k in CategoryKind.values) {
      await resetKind(k);
    }
  }

  Map<String, String> _readMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map<String, String>(
          (Object? k, Object? v) =>
              MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } on Object {
      return const <String, String>{};
    }
    return const <String, String>{};
  }

  List<String> _readList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <String>[
          for (final v in decoded)
            if (v is String && v.isNotEmpty) v,
        ];
      }
    } on Object {
      return const <String>[];
    }
    return const <String>[];
  }

  void _emit() {
    if (!_ctrl.isClosed) _ctrl.add(read());
  }

  Future<void> dispose() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  /// Apply persisted customisations to a raw [CategoryTree]. Returns a
  /// new tree with hidden groups stripped, leaves sorted by the
  /// persisted order, and aliases applied as the visible name. The
  /// root "all of kind" node always stays at position 0 — we only
  /// permute the leaves below it.
  static CategoryTree applyTo(
    CategoryTree raw,
    GroupCustomisations c,
  ) {
    return CategoryTree(
      live: _apply(raw.live, c, CategoryKind.live),
      movies: _apply(raw.movies, c, CategoryKind.movies),
      series: _apply(raw.series, c, CategoryKind.series),
    );
  }

  static List<CategoryNode> _apply(
    List<CategoryNode> bucket,
    GroupCustomisations c,
    CategoryKind kind,
  ) {
    if (bucket.isEmpty) return bucket;
    final root = bucket.first;
    final leaves = bucket.length > 1 ? bucket.sublist(1) : <CategoryNode>[];
    if (leaves.isEmpty) return bucket;
    final hidden = c.hidden[kind] ?? const <String>{};
    final aliases = c.aliases[kind] ?? const <String, String>{};
    final order = c.order[kind] ?? const <String>[];
    // 1. Strip hidden.
    final visible = <CategoryNode>[
      for (final n in leaves)
        if (!hidden.contains(n.name ?? '')) n,
    ];
    // 2. Sort by persisted order; unknown groups land at the tail
    //    while keeping the upstream "smart compare" (numeric prefix
    //    first) intact. Build an index map for O(1) lookups.
    final orderIdx = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    visible.sort((CategoryNode a, CategoryNode b) {
      final ai = orderIdx[a.name ?? ''];
      final bi = orderIdx[b.name ?? ''];
      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai != null) return -1;
      if (bi != null) return 1;
      return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
    });
    // 3. Apply aliases — wrap each node in a new CategoryNode with
    //    the alias surfacing as `name`. We keep the original `name`
    //    in the id via the kind prefix so existing selection
    //    persistence (categorySelectionProvider) still resolves to
    //    the same node after a rename.
    return <CategoryNode>[
      root,
      for (final n in visible)
        CategoryNode(
          kind: n.kind,
          name: aliases[n.name] ?? n.name,
          count: n.count,
        ),
    ];
  }
}

/// In-memory snapshot of user customisations. Immutable.
class GroupCustomisations {
  const GroupCustomisations({
    required this.aliases,
    required this.order,
    required this.hidden,
  });

  /// `groupName -> displayName` for each kind.
  final Map<CategoryKind, Map<String, String>> aliases;

  /// User-defined order of group names per kind.
  final Map<CategoryKind, List<String>> order;

  /// Group names hidden from the UI per kind.
  final Map<CategoryKind, Set<String>> hidden;

  /// True when [groupName] is hidden in [kind].
  bool isHidden(CategoryKind kind, String groupName) {
    return (hidden[kind] ?? const <String>{}).contains(groupName);
  }

  /// Display name for [groupName], honouring user aliases. Returns
  /// the original name when no override exists.
  String displayName(CategoryKind kind, String groupName) {
    final map = aliases[kind] ?? const <String, String>{};
    return map[groupName] ?? groupName;
  }

  /// Returns a new snapshot where everything is empty.
  static const GroupCustomisations empty = GroupCustomisations(
    aliases: <CategoryKind, Map<String, String>>{},
    order: <CategoryKind, List<String>>{},
    hidden: <CategoryKind, Set<String>>{},
  );
}
