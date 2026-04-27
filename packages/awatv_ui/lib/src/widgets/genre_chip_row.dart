import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A horizontally scrollable row of selectable genre / category chips.
///
/// Tighter and darker than `FilterChip`, brand-tinted on selection. Multi-
/// select is supported — pass the current [selected] set, get a new set
/// back via [onChanged]. A trailing "Clear" button surfaces only when at
/// least one chip is active.
///
/// When [scrollable] is false the row wraps to multiple lines instead —
/// useful inside narrow filter sheets.
class GenreChipRow extends StatelessWidget {
  const GenreChipRow({
    required this.genres,
    required this.selected,
    required this.onChanged,
    this.scrollable = true,
    this.padding,
    super.key,
  });

  /// Available chip labels.
  final List<String> genres;

  /// Currently selected labels.
  final Set<String> selected;

  /// Emits the new selection when a chip is toggled or "Clear" is hit.
  final ValueChanged<Set<String>> onChanged;

  /// Toggle horizontal scroll vs. wrap-to-lines layout.
  final bool scrollable;

  /// Padding around the row. Defaults to a horizontal gutter only.
  final EdgeInsetsGeometry? padding;

  void _toggle(String genre) {
    final next = <String>{...selected};
    if (!next.add(genre)) {
      next.remove(genre);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasSelection = selected.isNotEmpty;

    final chips = <Widget>[
      for (final String g in genres)
        Padding(
          padding: const EdgeInsets.only(right: DesignTokens.spaceS),
          child: _GenreChip(
            label: g,
            selected: selected.contains(g),
            onTap: () => _toggle(g),
          ),
        ),
      if (hasSelection)
        Padding(
          padding: const EdgeInsets.only(right: DesignTokens.spaceS),
          child: _ClearChip(
            onTap: () => onChanged(<String>{}),
            color: scheme.onSurface,
          ),
        ),
    ];

    final resolvedPadding = padding ??
        const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM);

    if (!scrollable) {
      return Padding(
        padding: resolvedPadding,
        child: Wrap(
          spacing: 0,
          runSpacing: DesignTokens.spaceS,
          children: chips,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: resolvedPadding,
      child: Row(children: chips),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final bg = selected
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.85)
        : scheme.outline.withValues(alpha: 0.4);
    final fg = selected
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.78);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
          child: AnimatedContainer(
            duration: DesignTokens.motionFast,
            curve: DesignTokens.motionStandard,
            constraints: const BoxConstraints(
              minHeight: 36,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceXs + 2,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(DesignTokens.radiusXL),
              border: Border.all(color: borderColor, width: 0.8),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color:
                            scheme.primary.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: fg,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearChip extends StatelessWidget {
  const _ClearChip({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Clear filters',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceXs + 2,
            ),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(DesignTokens.radiusXL),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: color.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Text(
                  'Clear',
                  style: text.labelMedium?.copyWith(
                    color: color.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
