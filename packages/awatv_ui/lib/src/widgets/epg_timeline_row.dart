import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// A single programme inside an EPG timeline strip.
///
/// `EpgTimelineRow` lays these out side-by-side, scaled by their duration,
/// so the visual width of each block matches its airtime. The id is used
/// purely for tap-callback identity (we don't reach back into core models
/// from the UI layer).
class EpgProgrammeBlock {
  const EpgProgrammeBlock({
    required this.id,
    required this.start,
    required this.stop,
    required this.title,
  });

  /// Stable identifier — consumer maps this back to its domain object.
  final String id;

  /// Start time (absolute, in the user's local timezone).
  final DateTime start;

  /// Stop time. Must be strictly after [start]; otherwise the block is
  /// dropped silently to avoid a divide-by-zero in width calculation.
  final DateTime stop;

  /// Programme title.
  final String title;
}

/// A horizontal EPG timeline strip.
///
/// Each programme is a fixed-width block whose width is its duration in
/// minutes multiplied by [pixelsPerMinute]. A glowing brand-cyan vertical
/// indicator marks "now"; programmes that already aired are dimmed, the
/// live programme picks up a brand-purple border + tinted fill, and
/// future programmes use the resting card style.
///
/// Use this inside a channel detail screen, a now-playing strip on top
/// of the player, or a horizontal "what's on" row of channels (one row
/// per channel).
class EpgTimelineRow extends StatelessWidget {
  const EpgTimelineRow({
    required this.programmes,
    this.now,
    this.pixelsPerMinute = 4.0,
    this.onTap,
    this.height = 72,
    super.key,
  });

  /// Programme blocks in chronological order. Out-of-order entries are
  /// rendered in the order supplied (caller controls sorting semantics).
  final List<EpgProgrammeBlock> programmes;

  /// "Current time" marker. Defaults to `DateTime.now()` at build time.
  final DateTime? now;

  /// Horizontal pixels each minute of programme time consumes. The
  /// default of 4px/min keeps a 30-minute block at 120px — comfortable
  /// for a tap target while still letting a few hours fit on screen.
  final double pixelsPerMinute;

  /// Tap callback per programme.
  final void Function(EpgProgrammeBlock)? onTap;

  /// Total row height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final clock = now ?? DateTime.now();

    // Normalise — drop zero/negative-duration blocks, keep ordering.
    final valid = <EpgProgrammeBlock>[
      for (final EpgProgrammeBlock p in programmes)
        if (p.stop.isAfter(p.start)) p,
    ];

    if (valid.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No programmes scheduled',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final timelineStart = valid.first.start;

    // Pre-compute live + offset for the now indicator.
    final indicatorOffset = clock
            .difference(timelineStart)
            .inSeconds /
        60.0 *
        pixelsPerMinute;

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final EpgProgrammeBlock p in valid)
                  _ProgrammeBlock(
                    block: p,
                    state: _resolveState(p, clock),
                    pixelsPerMinute: pixelsPerMinute,
                    onTap: onTap,
                    scheme: scheme,
                    text: text,
                  ),
              ],
            ),
            // "Now" indicator only renders when the clock falls inside
            // the visible window.
            if (_isClockInWindow(clock, valid))
              Positioned(
                left: indicatorOffset,
                top: -4,
                bottom: -4,
                child: IgnorePointer(
                  child: _NowIndicator(color: scheme.secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static _ProgrammeState _resolveState(
    EpgProgrammeBlock p,
    DateTime clock,
  ) {
    if (clock.isAfter(p.stop)) return _ProgrammeState.past;
    if (clock.isBefore(p.start)) return _ProgrammeState.upcoming;
    return _ProgrammeState.live;
  }

  static bool _isClockInWindow(
    DateTime clock,
    List<EpgProgrammeBlock> blocks,
  ) {
    final first = blocks.first.start;
    final last = blocks.last.stop;
    return !clock.isBefore(first) && !clock.isAfter(last);
  }
}

enum _ProgrammeState { past, live, upcoming }

class _ProgrammeBlock extends StatelessWidget {
  const _ProgrammeBlock({
    required this.block,
    required this.state,
    required this.pixelsPerMinute,
    required this.onTap,
    required this.scheme,
    required this.text,
  });

  final EpgProgrammeBlock block;
  final _ProgrammeState state;
  final double pixelsPerMinute;
  final void Function(EpgProgrammeBlock)? onTap;
  final ColorScheme scheme;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final minutes = block.stop.difference(block.start).inSeconds / 60.0;
    final width = (minutes * pixelsPerMinute).clamp(
      40.0,
      double.infinity,
    );
    final hh = block.start.hour.toString().padLeft(2, '0');
    final mm = block.start.minute.toString().padLeft(2, '0');

    final base = scheme.surfaceContainerHighest;
    final borderColor = switch (state) {
      _ProgrammeState.live => scheme.primary,
      _ProgrammeState.upcoming => scheme.outline.withValues(alpha: 0.45),
      _ProgrammeState.past => scheme.outline.withValues(alpha: 0.25),
    };
    final fill = switch (state) {
      _ProgrammeState.live => scheme.primary.withValues(alpha: 0.18),
      _ProgrammeState.upcoming => base.withValues(alpha: 0.85),
      _ProgrammeState.past => base.withValues(alpha: 0.35),
    };
    final opacity = state == _ProgrammeState.past ? 0.5 : 1.0;
    final titleStyle = text.bodySmall?.copyWith(
      color: scheme.onSurface.withValues(
        alpha: state == _ProgrammeState.past ? 0.6 : 0.95,
      ),
      fontWeight: state == _ProgrammeState.live
          ? FontWeight.w700
          : FontWeight.w500,
    );
    final timeStyle = text.labelSmall?.copyWith(
      color: state == _ProgrammeState.live
          ? scheme.primary
          : scheme.onSurface.withValues(alpha: 0.65),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );

    return Padding(
      padding: const EdgeInsets.only(right: DesignTokens.spaceXs),
      child: AnimatedOpacity(
        duration: DesignTokens.motionFast,
        opacity: opacity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(block),
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceS,
                vertical: DesignTokens.spaceXs + 2,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: borderColor,
                  width: state == _ProgrammeState.live ? 1.4 : 0.6,
                ),
                boxShadow: state == _ProgrammeState.live
                    ? <BoxShadow>[
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('$hh:$mm', style: timeStyle),
                  const SizedBox(height: 2),
                  Text(
                    block.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowIndicator extends StatefulWidget {
  const _NowIndicator({required this.color});
  final Color color;

  @override
  State<_NowIndicator> createState() => _NowIndicatorState();
}

class _NowIndicatorState extends State<_NowIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext _, Widget? __) {
        final t = _controller.value;
        return Semantics(
          label: 'Now',
          child: SizedBox(
            width: 18,
            child: Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                // Glowing rod down the middle.
                Center(
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: widget.color
                              .withValues(alpha: 0.5 + 0.4 * t),
                          blurRadius: 6 + 6 * t,
                        ),
                      ],
                    ),
                  ),
                ),
                // Top dot — same colour, also glows.
                Positioned(
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: BrandColors.background.withValues(alpha: 0.6),
                        width: 0.5,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: widget.color
                              .withValues(alpha: 0.6 + 0.3 * t),
                          blurRadius: 8 + 4 * t,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
