import 'package:awatv_mobile/src/features/channels/sort_mode_provider.dart';
import 'package:awatv_mobile/src/features/groups/group_customisation_provider.dart';
import 'package:awatv_mobile/src/features/groups/group_customisation_service.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selection state for the [GroupFilterChips] strip.
///
/// We intentionally keep this independent of the home-screen
/// `categorySelectionProvider` — chips on the dedicated grids
/// (live / vod / series) live alongside the category-tree-driven home
/// and may be set/cleared independently. When a chip is selected here
/// it overrides any tree selection visually because the grid renders
/// its own filter pipeline.
class GroupFilterState {
  const GroupFilterState({
    this.selected = const <String>{},
    this.multiMode = false,
  });

  /// Currently-selected group names. Empty == "all".
  final Set<String> selected;

  /// Whether long-press multi-select mode is active.
  final bool multiMode;

  GroupFilterState copyWith({
    Set<String>? selected,
    bool? multiMode,
  }) =>
      GroupFilterState(
        selected: selected ?? this.selected,
        multiMode: multiMode ?? this.multiMode,
      );
}

/// Per-surface persisted filter state.
///
/// Hive prefs keys:
///   `prefs:filter.live` → live channels
///   `prefs:filter.vod` → movies grid
///   `prefs:filter.series` → series grid
class GroupFilterNotifier
    extends FamilyNotifier<GroupFilterState, SortSurface> {
  @override
  GroupFilterState build(SortSurface arg) {
    final storage = ref.watch(awatvStorageProvider);
    try {
      final raw = storage.prefsBox.get('prefs:filter.${arg.name}');
      if (raw is List) {
        final selected = <String>{};
        for (final v in raw) {
          if (v is String && v.isNotEmpty) selected.add(v);
        }
        return GroupFilterState(selected: selected);
      }
    } on Object {
      // Storage might not be initialised in tests.
    }
    return const GroupFilterState();
  }

  Future<void> _persist() async {
    try {
      final storage = ref.read(awatvStorageProvider);
      await storage.prefsBox
          .put('prefs:filter.${arg.name}', state.selected.toList());
    } on Object {
      // Best-effort persistence.
    }
  }

  /// Toggle [group] under multi-select; otherwise replace the set.
  void toggle(String group) {
    if (state.multiMode) {
      final next = Set<String>.of(state.selected);
      if (next.contains(group)) {
        next.remove(group);
      } else {
        next.add(group);
      }
      state = state.copyWith(selected: next);
    } else {
      // Single-select: clicking the active chip clears, otherwise replaces.
      if (state.selected.length == 1 && state.selected.first == group) {
        state = state.copyWith(selected: <String>{});
      } else {
        state = state.copyWith(selected: <String>{group});
      }
    }
    _persist();
  }

  /// Long-press: enter multi-select mode and pre-add [group].
  void enterMulti(String group) {
    final next = Set<String>.of(state.selected)..add(group);
    state = state.copyWith(selected: next, multiMode: true);
    _persist();
  }

  /// Exit multi-select mode (chip set is preserved).
  void exitMulti() {
    state = state.copyWith(multiMode: false);
  }

  /// Clear selection (back to "all").
  void clear() {
    state = const GroupFilterState();
    _persist();
  }
}

final groupFilterProvider = NotifierProvider.family<GroupFilterNotifier,
    GroupFilterState, SortSurface>(GroupFilterNotifier.new);

/// Counts each group across the supplied items so chip badges can show
/// "Spor (32)" style numbers.
typedef GroupCounter = Map<String, int> Function();

/// A horizontally scrolling chip row above the grid.
///
/// - First chip: "Tumu" → clears selection
/// - Each chip: brand-purple background + scale 1.05 when selected
/// - Long-press: enters multi-select mode (checkmarks appear); a "Bitir"
///   chip surfaces at the tail to leave multi-mode.
class GroupFilterChips extends ConsumerWidget {
  const GroupFilterChips({
    required this.surface,
    required this.groups,
    required this.counts,
    super.key,
  });

  /// Which surface we're rendering for (drives the persistence key).
  final SortSurface surface;

  /// Ordered list of group names (already de-duped + sorted upstream).
  final List<String> groups;

  /// Item count per group for the badge labels.
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(groupFilterProvider(surface));
    final notifier = ref.read(groupFilterProvider(surface).notifier);
    final scheme = Theme.of(context).colorScheme;
    // Apply user customisations: hidden groups disappear, custom
    // order is honoured, and aliases override the visible chip
    // label. The selection state still keys on the original group
    // name (notifier.toggle(originalName)) so persisted filter state
    // never breaks when the user renames a chip.
    final customs = ref.watch(groupCustomisationsProvider).valueOrNull ??
        GroupCustomisations.empty;
    final kind = _kindFor(surface);
    final visibleGroups = _applyCustomisationOrder(groups, customs, kind);

    if (visibleGroups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceS,
        ),
        itemCount: visibleGroups.length + (filter.multiMode ? 2 : 1),
        separatorBuilder: (_, __) =>
            const SizedBox(width: DesignTokens.spaceS),
        itemBuilder: (BuildContext ctx, int i) {
          if (i == 0) {
            final selected = filter.selected.isEmpty;
            return _Chip(
              label: 'Tumu',
              count: null,
              selected: selected,
              accent: scheme.primary,
              checkmark: false,
              onTap: notifier.clear,
            );
          }

          // After "Tumu" come the group chips, then (optionally) the
          // "Bitir" exit-multi chip at the tail.
          if (filter.multiMode && i == visibleGroups.length + 1) {
            return _Chip(
              label: 'Bitir',
              count: null,
              selected: false,
              accent: scheme.tertiary,
              checkmark: false,
              icon: Icons.done_all_rounded,
              onTap: notifier.exitMulti,
            );
          }

          final g = visibleGroups[i - 1];
          final selected = filter.selected.contains(g);
          final label = customs.displayName(kind, g);
          return _Chip(
            label: label,
            count: counts[g],
            selected: selected,
            accent: scheme.primary,
            checkmark: filter.multiMode,
            onTap: () => notifier.toggle(g),
            onLongPress: () => notifier.enterMulti(g),
          );
        },
      ),
    );
  }

  /// Map the chip surface to a [CategoryKind] so we can look up the
  /// matching customisation slice.
  CategoryKind _kindFor(SortSurface s) {
    switch (s) {
      case SortSurface.live:
        return CategoryKind.live;
      case SortSurface.vod:
        return CategoryKind.movies;
      case SortSurface.series:
        return CategoryKind.series;
    }
  }

  /// Filter [groups] by hidden + reorder by user-defined order. Items
  /// without a custom order keep their upstream alphabetical position.
  List<String> _applyCustomisationOrder(
    List<String> groups,
    GroupCustomisations customs,
    CategoryKind kind,
  ) {
    final hidden = customs.hidden[kind] ?? const <String>{};
    final visible = <String>[
      for (final g in groups)
        if (!hidden.contains(g)) g,
    ];
    final order = customs.order[kind] ?? const <String>[];
    if (order.isEmpty) return visible;
    final idx = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    visible.sort((String a, String b) {
      final ai = idx[a];
      final bi = idx[b];
      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai != null) return -1;
      if (bi != null) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return visible;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.checkmark,
    required this.onTap,
    this.icon,
    this.onLongPress,
  });

  final String label;
  final int? count;
  final bool selected;
  final Color accent;
  final bool checkmark;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? accent : scheme.surfaceContainerHighest;
    final fg = selected ? Colors.white : scheme.onSurface;
    return GestureDetector(
      onLongPress: onLongPress,
      child: AnimatedScale(
        duration: DesignTokens.motionFast,
        scale: selected ? 1.05 : 1.0,
        child: AnimatedContainer(
          duration: DesignTokens.motionFast,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent
                  : scheme.outline.withValues(alpha: 0.18),
              width: selected ? 0 : 1,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (checkmark)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 14,
                        color: fg,
                      ),
                    ),
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(icon, size: 14, color: fg),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "sort menu" icon button rendered in the grid app-bars.
///
/// Pops up a checkmark menu of all 8 sort modes, automatically pruning
/// the rating/year-based options on `SortSurface.live` because
/// `Channel` carries no rating or release year.
class SortModeButton extends ConsumerWidget {
  const SortModeButton({required this.surface, super.key});

  final SortSurface surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(sortModeProvider(surface));
    return PopupMenuButton<SortMode>(
      tooltip: 'Sirala',
      icon: const Icon(Icons.sort_rounded),
      onSelected: (SortMode v) =>
          ref.read(sortModeProvider(surface).notifier).set(v),
      itemBuilder: (BuildContext _) {
        final available = <SortMode>[
          for (final m in SortMode.values)
            if (surface != SortSurface.live || m.appliesToLive) m,
        ];
        return <PopupMenuEntry<SortMode>>[
          for (final m in available)
            CheckedPopupMenuItem<SortMode>(
              value: m,
              checked: m == mode,
              child: Text(m.label),
            ),
        ];
      },
    );
  }
}
